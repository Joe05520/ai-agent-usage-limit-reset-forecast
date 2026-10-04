"""Consent-gated analytics and signature-verified updates. No vendor credentials."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time
import urllib.request
from urllib.parse import urlparse
import uuid
from . import __version__

CONFIG = json.loads((Path(__file__).with_name('ServiceConfig.json')).read_text(encoding='utf-8'))


def safe_url(value):
    try:
        u = urlparse(value)
        return u.scheme == 'https' and bool(u.hostname) and not u.username and not u.password and u.port in (None,443)
    except (ValueError, TypeError): return False


class Redirects(urllib.request.HTTPRedirectHandler):
    def __init__(self, allowed=()): self.allowed=set(allowed)
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        if not safe_url(newurl) or urlparse(newurl).hostname not in self.allowed: raise RuntimeError('Redirect rejected')
        return super().redirect_request(req,fp,code,msg,headers,newurl)


def request(url,body=None,method=None,limit=100_000,allowed=()):
    if not safe_url(url): raise ValueError('HTTPS required')
    req=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'User-Agent':'UsageSentinel/'+__version__,'Content-Type':'application/json'})
    with urllib.request.build_opener(Redirects(allowed)).open(req,timeout=20) as response:
        data=response.read(limit+1)
        if len(data)>limit: raise ValueError('Response exceeds limit')
        return data


def version(value):
    if not isinstance(value,str) or not re.fullmatch(r'[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}',value): raise ValueError('Invalid version')
    return tuple(map(int,value.split('.')))


def verify_manifest(data,signature,public_key,channel):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    if len(data)>100_000: raise ValueError('Manifest too large')
    Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key,validate=True)).verify(base64.b64decode(signature.strip(),validate=True),data)
    m=json.loads(data); version(m['version'])
    v=m['version']; release=f'https://github.com/Joe05520/usage-sentinel/releases/tag/v{v}'
    if m.get('schema')!=1 or m.get('channel')!=channel or channel not in ('preview','stable') or m.get('releaseURL')!=release or len(m.get('assets',[]))!=3 or {a['platform'] for a in m['assets']}!={'macOS','Windows','Linux'}: raise ValueError('Invalid manifest')
    for a in m['assets']:
        suffix={'macOS':'macOS-universal.zip','Windows':'Windows-x64.zip','Linux':'Linux-x64.tar.gz'}[a['platform']]
        expected=f'https://github.com/Joe05520/usage-sentinel/releases/download/v{v}/UsageSentinel-{v}-{suffix}'
        if a['url']!=expected or not re.fullmatch('[0-9a-fA-F]{64}',a['sha256']) or type(a['size']) is not int or not 1_000_000<a['size']<=250_000_000: raise ValueError('Invalid asset')
    return m


def check_update(preview=True):
    channel='preview' if preview else 'stable'
    url=f'https://joe05520.github.io/usage-sentinel/updates/{channel}.json'
    try: data=request(url)
    except urllib.error.HTTPError as e:
        if e.code==404: return None
        raise
    return verify_manifest(data,request(url+'.sig',limit=1024),CONFIG['updatePublicKey'],channel)


def download_update(manifest,directory=None):
    platform='Windows' if sys.platform=='win32' else 'Linux' if sys.platform=='linux' else 'macOS'
    asset=next(a for a in manifest['assets'] if a['platform']==platform)
    directory=Path(directory or Path.home()/'Downloads'); directory.mkdir(parents=True,exist_ok=True)
    target=directory/asset['url'].rsplit('/',1)[1]
    opener=urllib.request.build_opener(Redirects(['github.com','release-assets.githubusercontent.com','objects.githubusercontent.com']))
    temporary=None
    try:
        with tempfile.NamedTemporaryFile(dir=directory,prefix='.sentinel-update-',delete=False) as output:
            temporary=Path(output.name); digest=hashlib.sha256(); size=0
            with opener.open(urllib.request.Request(asset['url'],headers={'User-Agent':'UsageSentinel/'+__version__}),timeout=30) as response:
                while chunk:=response.read(65536):
                    size+=len(chunk)
                    if size>asset['size']: raise ValueError('Update exceeds declared size')
                    output.write(chunk); digest.update(chunk)
            if size!=asset['size'] or digest.hexdigest()!=asset['sha256'].lower(): raise ValueError('Update checksum mismatch')
        os.link(temporary,target)  # Exclusive creation; never overwrites existing downloads.
        return str(target)
    finally:
        if temporary: temporary.unlink(missing_ok=True)


def vault():
    if sys.platform=='win32':
        from keyring.backends.Windows import WinVaultKeyring
        backend=WinVaultKeyring()
    elif sys.platform=='darwin':
        from keyring.backends.macOS import Keyring
        backend=Keyring()
    else:
        from keyring.backends.SecretService import Keyring
        backend=Keyring()
    if backend.priority<=0: raise RuntimeError('OS credential storage unavailable; analytics cannot be enabled')
    return backend


def identity(now=None):
    month=time.strftime('%Y-%m',time.gmtime(now or time.time())); backend=vault()
    raw=backend.get_password('UsageSentinel','analytics-identity-v1')
    saved=json.loads(raw) if raw else {'month':month,'current':str(uuid.uuid4()),'retained':[]}
    if saved['month']!=month: saved={'month':month,'current':str(uuid.uuid4()),'retained':(saved['retained']+[saved['current']])[-2:]}
    backend.set_password('UsageSentinel','analytics-identity-v1',json.dumps(saved));return saved['current']


def payload(settings,state,client,now=None):
    now=now or time.time(); day=time.strftime('%Y-%m-%d',time.gmtime(now))
    if not settings.get('analytics') or not state.get('closed') or state.get('sent')==state['closed']['day']: return None
    state=state['closed']
    if state['day'] not in [day,time.strftime('%Y-%m-%d',time.gmtime(now-86400))]: return None
    return dict(schema=1,consent=True,client=client,day=state['day'],kind='app',platform='Windows' if sys.platform=='win32' else 'Linux' if sys.platform=='linux' else 'macOS',version=__version__,agent=state.get('agent','custom'),quotaBand=state.get('quotaBand','unknown') if settings.get('share_quota') else 'unknown',activityBand='0' if state['observations']==0 else '1-5' if state['observations']<=5 else '6-20' if state['observations']<=20 else '21+',reminders=len(settings['stages']))


def send_analytics(settings,state):
    endpoint=CONFIG.get('analyticsEndpoint')
    if not settings.get('analytics') or not endpoint: return None
    body=payload(settings,state,identity())
    if body: request(endpoint.rstrip('/')+'/v1/report',body,method='POST',limit=2048)
    return body


def delete_analytics():
    endpoint=CONFIG.get('analyticsEndpoint')
    if not endpoint: raise ValueError('Analytics not configured')
    backend=vault(); raw=backend.get_password('UsageSentinel','analytics-identity-v1')
    if not raw:return
    saved=json.loads(raw)
    for client in saved['retained']+[saved['current']]: request(endpoint.rstrip('/')+'/v1/report',dict(client=client),method='DELETE',limit=2048)
    backend.delete_password('UsageSentinel','analytics-identity-v1')
