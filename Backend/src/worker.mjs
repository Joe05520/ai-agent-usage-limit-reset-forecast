import {dashboard} from './dashboard.mjs';
const REPO = 'https://api.github.com/repos/Joe05520/usage-sentinel/releases?per_page=100';
const platforms = new Set(['macOS','Windows','Linux']);
const agents = new Set(['codex','claude','gemini','grok','custom']);
const bands = new Set(['unknown','0-4','5-19','20-49','50-100']);
const activity = new Set(['0','1-5','6-20','21+']);
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
const enc = new TextEncoder();
export const headers = {'Content-Type':'application/json; charset=utf-8','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'; frame-ancestors 'none'",'Strict-Transport-Security':'max-age=31536000'};
function json(value,status=200,extra={}) {return new Response(JSON.stringify(value),{status,headers:{...headers,...extra}});}
export function validate(body,now=new Date()) {
 if (!body || Array.isArray(body) || typeof body!=='object') throw Error('Invalid report');
 const keys = ['schema','consent','client','day','kind','platform','version','agent','quotaBand','activityBand','reminders'];
 if(Object.keys(body).some(k=>!keys.includes(k))) throw Error('Unknown field');
 if(body.schema!==1 || body.consent!==true || !UUID.test(body.client) || !platforms.has(body.platform) || !/^\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(body.version) || !['app','download'].includes(body.kind)) throw Error('Invalid report');
 const today=now.toISOString().slice(0,10), yesterday=new Date(+now-86400000).toISOString().slice(0,10);
 if(![today,yesterday].includes(body.day)) throw Error('Outside report window');
 if(body.kind==='download') {
  if(['agent','quotaBand','activityBand','reminders'].some(k=>k in body)) throw Error('Download has usage fields');
 } else if(!agents.has(body.agent)||!bands.has(body.quotaBand)||!activity.has(body.activityBand)||!Number.isInteger(body.reminders)||body.reminders<0||body.reminders>5) throw Error('Invalid usage fields');
 return body;
}
async function mac(value,secret) {
 if(!secret || secret.length<32) throw Error('Service not configured');
 const key=await crypto.subtle.importKey('raw',enc.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return [...new Uint8Array(await crypto.subtle.sign('HMAC',key,enc.encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');
}
function country(request) {const c=request.cf?.country; return typeof c==='string'&&/^[A-Z]{2}$/.test(c)&&!['XX','T1'].includes(c)?c:'Unknown';}
export async function readBounded(request,limit=2048) {
 if(Number(request.headers.get('Content-Length'))>limit) throw Error('Too large');
 const reader=request.body?.getReader(); if(!reader)throw Error('Missing body');
 let length=0,chunks=[];
 while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>limit){await reader.cancel();throw Error('Too large');}chunks.push(value);}
 const bytes=new Uint8Array(length);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}return JSON.parse(new TextDecoder().decode(bytes));
}
function unbase64(s) {return Uint8Array.from(atob(s.replace(/-/g,'+').replace(/_/g,'/')),c=>c.charCodeAt(0));}
let jwksCache;
export async function authorize(request,env,fetcher=fetch,now=Date.now()/1000) {
 // Access authentication is mandatory. No local or public bypass and no API token in browser storage.
 if(!/^[a-z0-9-]+$/.test(env.ACCESS_TEAM||'')||!(env.ACCESS_AUD||'').trim())return false;
 const token=request.headers.get('Cf-Access-Jwt-Assertion'); if(!token||token.length>8192)return false;
 try {
  const parts=token.split('.');if(parts.length!==3)return false;
  const head=JSON.parse(new TextDecoder().decode(unbase64(parts[0]))),claims=JSON.parse(new TextDecoder().decode(unbase64(parts[1])));
  const issuer=`https://${env.ACCESS_TEAM}.cloudflareaccess.com`;
  if(head.alg!=='RS256'||typeof head.kid!=='string'||claims.iss!==issuer||!Array.isArray(claims.aud)||!claims.aud.includes(env.ACCESS_AUD)||!Number.isFinite(claims.exp)||claims.exp<=now||!Number.isFinite(claims.iat)||claims.iat>now+60||(claims.nbf!=null&&(!Number.isFinite(claims.nbf)||claims.nbf>now+60)))return false;
  if(!jwksCache||jwksCache.issuer!==issuer||jwksCache.until<Date.now()){
   const response=await fetcher(issuer+'/cdn-cgi/access/certs',{redirect:'error',signal:AbortSignal.timeout(10000)});if(!response.ok)return false;
   const keys=await readBounded(response,65536);
   jwksCache={issuer,until:Date.now()+300000,keys:keys.keys};
  }
  const jwk=jwksCache.keys.find(k=>k.kid===head.kid&&k.kty==='RSA');if(!jwk)return false;
  const key=await crypto.subtle.importKey('jwk',jwk,{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['verify']);
  return await crypto.subtle.verify('RSASSA-PKCS1-v1_5',key,unbase64(parts[2]),enc.encode(parts[0]+'.'+parts[1]));
 }catch{return false;}
}
export function aggregate(rows,k=10,now=new Date()) {
 const recent=rows.filter(r=>r.day>=new Date(+now-30*86400000).toISOString().slice(0,10));
 const app=recent.filter(r=>r.kind==='app'),download=recent.filter(r=>r.kind==='download');
 const distinct=(rs)=>new Set(rs.map(r=>r.client)).size;
 function groups(rs,key){const map=new Map();for(const r of rs){const label=r[key];if(label==null)continue;const list=map.get(label)||[];list.push(r);map.set(label,list);}return [...map].filter(([,v])=>distinct(v)>=k).map(([label,v])=>({label,count:v.length,contributors:distinct(v)})).sort((a,b)=>b.count-a.count);}
 // No residual "other" totals or parent sums: avoids recovering suppressed cells by subtraction.
 return {schema:1,windowDays:30,minimumContributors:k,definitions:{download:'Consented download clicks; not completed downloads',app:'Opt-in daily reports; quota bands are self-reported, not tokens or spend',contributors:'Rotating monthly anonymous identities; not verified people'},downloads:{countries:groups(download,'country'),platforms:groups(download,'platform'),daily:groups(download,'day')},usage:{agents:groups(app,'agent'),quotaBands:groups(app,'quota_band'),activityBands:groups(app,'activity_band'),reminderStages:groups(app,'reminders'),daily:groups(app,'day')}};
}
async function stats(env,admin=false) {
 const since=new Date(Date.now()-30*86400000).toISOString().slice(0,10),k=admin?1:10;
 const dimensions=[['download','country'],['download','platform'],['download','day'],['app','country'],['app','agent'],['app','quota_band'],['app','activity_band'],['app','reminders'],['app','day']];
 const queries=dimensions.map(([kind,column])=>env.DB.prepare(`SELECT ${column} AS label, COUNT(*) AS count, COUNT(DISTINCT client) AS contributors FROM reports WHERE day >= ? AND kind = ? AND ${column} IS NOT NULL GROUP BY ${column} HAVING COUNT(DISTINCT client) >= ? ORDER BY count DESC`).bind(since,kind,k));
 queries.push(env.DB.prepare('SELECT day,platform,downloads FROM github_downloads WHERE day >= ? ORDER BY day').bind(since));
 const results=await env.DB.batch(queries),v=results.map(r=>r.results);
 return {schema:1,windowDays:30,minimumContributors:k,generatedAt:new Date().toISOString(),downloads:{countries:v[0],platforms:v[1],daily:v[2]},usage:{countries:v[3],agents:v[4],quotaBands:v[5],activityBands:v[6],reminderStages:v[7],daily:v[8]},githubDownloads:v[9]};
}
export async function passwordMatches(password,secret) {
 if(typeof password!=='string'||password.length>128||!secret||secret.length<40)return false;
 const key=await crypto.subtle.importKey('raw',enc.encode('UsageSentinelAdminComparison'),{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);
 const expected=await crypto.subtle.sign('HMAC',key,enc.encode(secret));
 return crypto.subtle.verify('HMAC',key,expected,enc.encode(password));
}
export async function adminSession(request,env) {
 if(await authorize(request,env))return true;
 if(!env.ADMIN_SECRET||env.ADMIN_SECRET.length<40)return false;
 const cookie=request.headers.get('Cookie')||'',value=cookie.split(';').map(v=>v.trim()).find(v=>v.startsWith('__Host-sentinel='))?.slice(16);
 if(!value||value.length>200)return false;
 const [expiry,nonce,signature]=value.split('.');
 if(!/^\d+$/.test(expiry)||!UUID.test(nonce)||Number(expiry)<=Date.now()/1000||Number(expiry)>Date.now()/1000+1800)return false;
 try{const key=await crypto.subtle.importKey('raw',enc.encode(env.ADMIN_SECRET),{name:'HMAC',hash:'SHA-256'},false,['verify']);return await crypto.subtle.verify('HMAC',key,unbase64(signature),enc.encode('session:'+expiry+'.'+nonce));}catch{return false;}
}
function page(content,nonce){return new Response(content,{headers:{...headers,'Content-Type':'text/html; charset=utf-8','Content-Security-Policy':`default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'`}});}
async function fetchHandler(request,env) {
 const url=new URL(request.url),origin=request.headers.get('Origin');
 const cors=origin===env.SITE_ORIGIN?{'Access-Control-Allow-Origin':origin,'Vary':'Origin'}:{};
 if(origin&&origin!==env.SITE_ORIGIN&&!(url.pathname.startsWith('/admin')&&origin===url.origin))return json({error:'Origin not allowed'},403);
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers:{...headers,...cors,'Access-Control-Allow-Methods':'POST, GET, DELETE','Access-Control-Allow-Headers':'Content-Type'}});
 if(url.pathname==='/health'&&request.method==='GET')return json({status:'ok'},200,cors);
 if(url.pathname==='/admin'&&request.method==='GET'){
  const nonce=crypto.randomUUID();return page(dashboard(await adminSession(request,env),nonce),nonce);
 }
 if(url.pathname==='/admin/login'&&request.method==='POST'){
  if(origin!==url.origin||!request.headers.get('Content-Type')?.startsWith('application/json'))return json({error:'Invalid origin'},403);
  const key=await mac('admin:'+ (request.headers.get('CF-Connecting-IP')||'unknown'),env.INGEST_SECRET);
  if(!env.ADMIN_LIMIT||!(await env.ADMIN_LIMIT.limit({key})).success)return json({error:'Rate limited'},429,{'Retry-After':'60'});
  const body=await readBounded(request);
  if(Object.keys(body).length!==1||!await passwordMatches(body.password,env.ADMIN_SECRET))return json({error:'Unauthorized'},401);
  const expiry=String(Math.floor(Date.now()/1000)+1800),nonce=crypto.randomUUID();
  const hex=await mac('session:'+expiry+'.'+nonce,env.ADMIN_SECRET),signature=btoa(String.fromCharCode(...hex.match(/../g).map(v=>parseInt(v,16)))).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
  return json({signedIn:true},200,{'Set-Cookie':`__Host-sentinel=${expiry}.${nonce}.${signature}; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=1800`});
 }
 if(url.pathname==='/admin/logout'&&request.method==='POST'){
  if(origin!==url.origin)return json({error:'Invalid origin'},403);
  return json({signedOut:true},200,{'Set-Cookie':'__Host-sentinel=; Secure; HttpOnly; SameSite=Strict; Path=/; Max-Age=0'});
 }
 if(url.pathname==='/public/stats'&&request.method==='GET'){
  const key=new Request(url.origin+'/public/stats'),cache=globalThis.caches?.default;
  let response=cache?await cache.match(key):null;
  if(!response){response=json(await stats(env),200,{'Cache-Control':'public, max-age=3600'});if(cache)await cache.put(key,response.clone());}
  const result=new Response(response.body,response);for(const [key,value]of Object.entries(cors))result.headers.set(key,value);return result;
 }
 if(url.pathname==='/admin/stats'&&request.method==='GET'){
  if(!await adminSession(request,env))return json({error:'Cloudflare Access sign-in required'},401);
  return json(await stats(env,true));
 }
 if(url.pathname==='/v1/report'&&request.method==='POST'){
  if(!request.headers.get('Content-Type')?.startsWith('application/json'))return json({error:'JSON required'},415,cors);
  const ip=request.headers.get('CF-Connecting-IP')||'unknown';
  const key=await mac('rate:'+ip+':'+new Date().toISOString().slice(0,10),env.INGEST_SECRET);
  if(!env.INGEST_LIMIT||!(await env.INGEST_LIMIT.limit({key})).success)return json({error:'Rate limited'},429,{...cors,'Retry-After':'60'});
  let body;try{body=validate(await readBounded(request));}catch{return json({error:'Invalid or oversized report'},400,cors);}
  const client=await mac('client:'+body.client,env.INGEST_SECRET);
  await env.DB.prepare('INSERT OR IGNORE INTO reports VALUES (?,?,?,?,?,?,?,?,?,?)').bind(body.day,client,body.kind,country(request),body.platform,body.version,body.agent??null,body.quotaBand??null,body.activityBand??null,body.reminders??null).run();
  return json({accepted:true},202,cors);
 }
 if(url.pathname==='/v1/report'&&request.method==='DELETE'){
  const key=await mac('delete:'+(request.headers.get('CF-Connecting-IP')||'unknown'),env.INGEST_SECRET);
  if(!env.INGEST_LIMIT||!(await env.INGEST_LIMIT.limit({key})).success)return json({error:'Rate limited'},429,{...cors,'Retry-After':'60'});
  const body=await readBounded(request);if(Object.keys(body).length!==1||!UUID.test(body.client))return json({error:'Invalid deletion'},400,cors);
  const client=await mac('client:'+body.client,env.INGEST_SECRET);await env.DB.prepare('DELETE FROM reports WHERE client=?').bind(client).run();return json({deleted:true},200,cors);
 }
 return json({error:'Not found'},404,cors);
}
export async function scheduled(env,fetcher=fetch) {
 // Retain reports only 35 days. Deletion precedes external requests, even if GitHub is unavailable.
 await env.DB.prepare('DELETE FROM reports WHERE day < ?').bind(new Date(Date.now()-35*86400000).toISOString().slice(0,10)).run();
 await env.DB.prepare('DELETE FROM github_downloads WHERE day < ?').bind(new Date(Date.now()-365*86400000).toISOString().slice(0,10)).run();
 const response=await fetcher(REPO,{headers:{'Accept':'application/vnd.github+json','User-Agent':'UsageSentinelStats/1.5'},redirect:'error',signal:AbortSignal.timeout(15000)});if(!response.ok)return;
 const releases=await readBounded(response,2000000),counts={macOS:0,Windows:0,Linux:0};
 for(const release of releases){if(release.draft)continue;for(const asset of release.assets||[]){const match=/^UsageSentinel-\d+\.\d+\.\d+-(macOS-universal\.zip|Windows-x64\.zip|Linux-x64\.tar\.gz)$/.exec(asset.name);if(match&&Number.isSafeInteger(asset.download_count)&&asset.download_count>=0){const p=match[1].startsWith('macOS')?'macOS':match[1].startsWith('Windows')?'Windows':'Linux';counts[p]+=asset.download_count;}}}
 const day=new Date().toISOString().slice(0,10);
 await env.DB.batch(Object.entries(counts).map(([platform,count])=>env.DB.prepare('INSERT OR REPLACE INTO github_downloads VALUES (?,?,?)').bind(day,platform,count)));
}
export default {async fetch(request,env){try{return await fetchHandler(request,env);}catch{return json({error:'Service temporarily unavailable'},503);}},async scheduled(_controller,env,ctx){ctx.waitUntil(scheduled(env));}};
