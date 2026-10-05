'use strict';
const chinese = {
skip:'跳至主要內容',language:'語言',navFeatures:'功能',navAgents:'AI 代理',navDownload:'下載',eyebrow:'開放原始碼・資料留在裝置',hero:'AI 剩餘額度，<br>隨時看得見。<br><em>安心繼續工作。</em>',lede:'知道還剩多少，在用完前得到提醒。非例行 reset 有跡象時，也能提早掌握消息。',getApp:'下載 AI Usage Sentinel',viewSource:'探索原始碼 ↗',platforms:'原生 macOS・Windows / Linux 測試版・免費 MIT 授權',fiveHour:'5 小時',weekly:'每週',exampleReset:'例行重置還有 2 小時 14 分',exampleWeekly:'例行重置還有 3 天 7 小時',possible:'可能出現 重置訊號',signalExample:'初期重置訊號・可信度 38%',exampleUpdate:'剛剛更新',illustration:'示意介面：這些是範例數值，不是即時帳號資料。',tryStyle:'試試選單列樣式',standard:'標準',compact:'精簡',percentages:'只有百分比',single:'單一額度',icon:'只有圖示',showCount:'顯示重置訊號數量',principle1:'不收集瀏覽器 Cookie',principle2:'統計須經使用者同意',principle3:'每則重置訊號都附上來源',principle4:'App 支援五種介面語言',overview:'安靜而實用的小幫手',featureTitle:'少一點反覆查看。<br>多一點心中有數。',meterTitle:'用量就在工作的位置。',meterBody:'顯示實際剩餘額度、例行 reset 時間與最後成功更新。不補上不存在的 limit；讀取失敗就明確顯示未知。',reminderTitle:'依照你的節奏提醒。',reminderBody:'最多設定五個剩餘額度門檻，每週期每階段只提醒一次。需要專心時，可以暫停一小時。',resetTitle:'留意不尋常的變化。',resetBody:'額度在原定 reset 前增加，會成為帳號觀察證據。例行 reset 保持安靜；banked、purchased 與 complimentary reset 各自分類。',staged:'五個階段，由你決定',reminderHeading:'在歸零之前，<br>先提醒一下。',reminderExplanation:'可新增、刪除或修改 0–99% 的不同門檻。一次更新跨越多階段時，只發一則合併提醒。重開 App 不會重複已送出的提醒。',tryDemo:'試試範例：向下調整剩餘額度，再重置週期。',demoLabel:'提醒互動示範',remainingLabel:'剩餘額度',addStage:'+ 新增階段',resetCycle:'重置示範週期 ↻',demoReady:'往下移動，低於門檻後預覽提醒。',demoDisclaimer:'僅為瀏覽器範例，不連接帳號，也不發送系統通知。',signalsEyebrow:'消息提早出現，不代表已經確定',signalsTitle:'看見重置訊號，<br>也看得見<br>背後的證據。',signalsBody:'分別檢查 OpenAI 官方資訊、GitHub 和 Reddit。相關回報會合併；重複文字或同一作者不會灌高可信度。你的額度真的增加，也能強化既有重置訊號。',confidenceGuide:'了解可信度計算方式 ↗',rumor:'傳聞',rumorBody:'證據有限，值得查看但尚待確認。',early:'初期重置訊號',earlyBody:'新出現的社群回報，尚未獲得官方證實。',thresholdDefault:'預設從可信度 25% 開始通知。',likely:'可能性高',likelyBody:'有更強的交叉證據，仍不等於官方證實。',confirmed:'官方確認',confirmedBody:'有官方證據，適用帳號請閱讀原始來源。',agentsEyebrow:'不同的代理，誠實的資料',agentsTitle:'多種代理，<br>同一個查看位置。',agentsIntro:'選擇用量來源。App 一次顯示一個選定的代理，歷史留在本機。整合方式依各家正式開放的資訊而定。',automatic:'自動讀取本機正式資料',bridge:'官方狀態列橋接',localImport:'本機 JSON / 手動',codexBody:'登入官方 Codex 後，透過正式本機 app-server 讀取實際回傳的額度。不送出推論 prompt。',claudeBody:'從 Claude Code 官方狀態列匯入只有額度欄位的 JSON。需先設定，並由 Claude session 提供 rate-limit 資料。',geminiBody:'接受有權讀取的本機額度匯出或手動數值。不假設存在未支援的個人用量 endpoint。',grokBody:'接受本機額度證據。不把 API rate limit 當成 SuperGrok 訂閱剩餘用量。',agentsLimit:'外部 reset 消息目前聚焦 OpenAI / Codex，其他代理的消息來源尚未整合。過期匯出檔不會被當作新用量。',setupGuide:'閱讀代理設定指南 ↗',privacyEyebrow:'你的用量，屬於你自己',privacyTitle:'資料預設留在本機。',privacyBody:'帳號歷史預設留在本機。1.5 提供自願匿名統計；每日使用變動區間與粗略額度須由使用者選擇同意。公開消息請求不含帳號歷史或憑證。官方 Codex 處理其登入。詳見公開統計頁的欄位與隱私說明。',privacyGuide:'隱私與安全說明 ↗',downloadEyebrow:'小工具，歡迎所有人使用',downloadTitle:'在選單列，<br>留一個位置。',downloadIntro:'版本 1.6.0・免費、開源，Sentinel 本身不要求帳號。自動讀取 Codex 額度需要已登入的官方 Codex。',macSpec:'macOS 14+・Apple Silicon 與 Intel<br>SwiftUI / MenuBarExtra',downloadMac:'下載 macOS 版 ↓',macNote:'使用 ad-hoc 簽章，尚未 notarize。請依 macOS「隱私權與安全性」明確允許開啟，保留系統安全防護。',winSpec:'Windows 10/11・x64<br>原生 Qt 系統匣',downloadWin:'下載 Windows 版 ↓',winNote:'解壓縮整個資料夾後執行 UsageSentinel.exe。此預覽版未使用付費簽章，請閱讀發布內容並依系統信任提示操作。',linuxSpec:'Linux x64・glibc 2.35+<br>Qt tray / 相容桌面環境',downloadLinux:'下載 Linux 版 ↓',linuxNote:'解壓縮後執行 UsageSentinel/UsageSentinel。部分桌面需安裝 Qt 系統套件或 tray 擴充；沒有 tray 時會保留視窗。',releaseNotes:'發布說明與檔案雜湊 ↗',platformGuide:'Windows / Linux 安裝指南 ↗',buildGuide:'從原始碼建置 ↗',betaLimit:'Windows / Linux 是測試版：CI build 與 smoke test 不等於真實桌面的通知、休眠與登入驗證。macOS 有較完整的圖表及選單列樣式；平台差異請見指南。',faqTitle:'幾件值得先了解的事',faq1:'所有 ChatGPT 額度都能顯示嗎？',faq1Body:'目前不能。Codex 的自動用量只顯示正式 provider 回傳的 windows；其他 ChatGPT 個人額度可能無法取得。資料缺少時顯示未知，不會填上假百分比。',faq2:'初期重置訊號代表我的額度一定會 reset 嗎？',faq2Body:'不代表。社群回報可能只適用單一帳號、發生誤判，或屬於有限 rollout。通知會附可信度與來源，Sentinel 不預測下一次 global reset 的日期。',faq3:'通知一定會立刻出現嗎？',faq3Body:'偵測在成功更新時進行，預設每五分鐘；macOS 喚醒或開啟選單後會更新。休眠、專注模式、勿擾模式或桌面通知支援可能延後或隱藏通知。',faq4:'可以貢獻或要求其他 AI 代理嗎？',faq4Body:'可以。歡迎 provider adapter、翻譯、問題回報與各平台驗證。請附官方文件，並避免在 issue 上傳私人帳號資料。',contribute:'貢獻指南 ↗',openTitle:'開放開發，<br>讓你的觀察也有幫助。',openBody:'覺得好用，歡迎分享專案。覺得有地方能改善，歡迎開 issue。每個有用的回報，都能讓這個小幫手更可靠。',visitGitHub:'前往 GitHub ↗',independent:'獨立社群專案，與 OpenAI、Anthropic、Google 或 xAI 無隸屬或背書關係。',reportIssue:'回報問題 ↗'
};
Object.assign(chinese, {panelModeLabel:'面板可視化',professionalMode:'專業模式',ringMode:'直覺・圓環',batteryMode:'直覺・電量',compactMode:'精簡模式',animationLabel:'額度變化動畫',visualDemoLabel:'預覽額度變化'});
const english = Object.fromEntries([...document.querySelectorAll('[data-i18n]')].map(e => [e.dataset.i18n, e.innerHTML]));
let language = 'en';
try { language = localStorage.getItem('sentinel-site-language') || (navigator.language === 'zh-TW' || navigator.language === 'zh-HK' ? 'zh-Hant' : 'en'); } catch (_) {}
if (!['en','zh-Hant'].includes(language)) language='en';
const languageSelect=document.getElementById('language');
function setLanguage(value) {
 language=value; document.documentElement.lang=value; languageSelect.value=value;
 document.querySelectorAll('[data-i18n]').forEach(e=>{const key=e.dataset.i18n;e.innerHTML=(value==='zh-Hant'?chinese[key]:english[key])||english[key]||key;});
 document.title=value==='zh-Hant'?'AI Usage Sentinel — AI 剩餘額度，隨時看得見。':'AI Usage Sentinel — AI Quota Monitor & Reset Alerts';
 try { localStorage.setItem('sentinel-site-language',value); } catch (_) {}
 renderStages(); updateMenu(); resetDemo(false);
}
languageSelect.addEventListener('change', e=>setLanguage(e.target.value));
function updateMenu() {
 const style=document.getElementById('displayStyle').value;
 const values={standard:'◉ 5h 72% · W 61%',compact:'◉ 72 / 61',percent:'72% · 61%',single:'◉ W 61%',icon:'◉'};
 document.getElementById('menuPreview').textContent=values[style]+(document.getElementById('signalCount').checked?' · ⚡1':'');
}
document.getElementById('displayStyle').addEventListener('change',updateMenu);document.getElementById('signalCount').addEventListener('change',updateMenu);
let stages=[50,30,20,10,5], delivered=new Set();
function renderStages() {
 const container=document.getElementById('stages');container.replaceChildren();
 stages.forEach((value,index)=>{
  const row=document.createElement('div');row.className='stage'+(delivered.has(value)?' delivered':'');
  const input=document.createElement('input');input.type='number';input.min='0';input.max='99';input.value=value;input.setAttribute('aria-label',(language==='zh-Hant'?'第 ':'Stage ')+(index+1)+(language==='zh-Hant'?' 階段百分比':' percentage'));
  input.addEventListener('change',()=>{const changed=Number(input.value);if(!Number.isInteger(changed)||changed<0||changed>99||stages.some((v,i)=>i!==index&&v===changed)){input.value=value;return;}stages[index]=changed;stages.sort((a,b)=>b-a);renderStages();});
  const percent=document.createElement('span');percent.textContent='%';const remove=document.createElement('button');remove.textContent='×';remove.setAttribute('aria-label',(language==='zh-Hant'?'移除第 ':'Remove stage ')+(index+1));remove.addEventListener('click',()=>{stages.splice(index,1);renderStages();});row.append(input,percent,remove);container.append(row);
 });document.getElementById('addStage').disabled=stages.length>=5;
}
document.getElementById('addStage').addEventListener('click',()=>{if(stages.length>=5)return;const next=[50,30,20,10,5,...Array.from({length:100},(_,i)=>99-i)].find(v=>!stages.includes(v));stages.push(next);stages.sort((a,b)=>b-a);renderStages();});
const range=document.getElementById('remaining');
range.addEventListener('input',()=>{const value=Number(range.value);document.getElementById('remainingOutput').textContent=value;const crossed=stages.filter(v=>value<=v&&!delivered.has(v));if(crossed.length){crossed.forEach(v=>delivered.add(v));const threshold=Math.min(...crossed);document.getElementById('demoMessage').textContent=language==='zh-Hant'?`範例提醒：剩餘 ${value}%，已跨越 ${crossed.length} 個階段。合併提醒門檻：≤${threshold}%。`:`Demo reminder: ${value}% remaining, ${crossed.length} stage(s) crossed. One alert at ≤${threshold}%.`;renderStages();}});
function resetDemo(resetValue=true){delivered=new Set();if(resetValue){range.value=80;document.getElementById('remainingOutput').textContent='80';}renderStages();document.getElementById('demoMessage').textContent=language==='zh-Hant'?chinese.demoReady:english.demoReady;}
document.getElementById('resetDemo').addEventListener('click',()=>resetDemo());
setLanguage(language);

// Finite sample transitions. Never connects to an account or predicts real quota.
const panelMode=document.getElementById('panelMode'), animationToggle=document.getElementById('animatePanel');
let visualRemaining=72;
function renderVisualization(){
 const mode=panelMode.value, reduced=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
 const panel=document.querySelector('.popover'); panel.dataset.visualMode=mode;
 panel.classList.toggle('no-animation',!animationToggle.checked||reduced);
 document.querySelectorAll('.quota-row').forEach((row,index)=>{
  const remaining=index===0?visualRemaining:61;
  row.style.setProperty('--remaining',remaining+'%');
  row.querySelector('strong').innerHTML=remaining+'<span>%</span>';
  row.querySelector('.progress i').style.width=remaining+'%';
 });
}
panelMode.addEventListener('change',renderVisualization);
animationToggle.addEventListener('change',renderVisualization);
document.getElementById('visualDemo').addEventListener('click',()=>{visualRemaining=visualRemaining===72?23:72;renderVisualization();});
renderVisualization();
