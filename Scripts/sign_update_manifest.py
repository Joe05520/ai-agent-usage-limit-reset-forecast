#!/usr/bin/env python3
"""CI release only. Signing seed enters through environment, never gets printed or written."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding,PublicFormat
root=Path(__file__).resolve().parents[1]
version=sys.argv[1];channel=sys.argv[2];folder=Path(sys.argv[3])
if not re.fullmatch(r'[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}',version) or channel not in ['stable','preview']:raise SystemExit('Invalid release version/channel')
key=Ed25519PrivateKey.from_private_bytes(base64.b64decode(os.environ['UPDATES_ED25519_KEY'],validate=True))
expected=json.loads((root/'OpenAIUsageSentinel/Resources/ServiceConfig.json').read_text())['updatePublicKey']
if base64.b64encode(key.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)).decode()!=expected:raise SystemExit('Signing key does not match app public key')
assets=[]
for platform,suffix in [('macOS','macOS-universal.zip'),('Windows','Windows-x64.zip'),('Linux','Linux-x64.tar.gz')]:
 file=folder/f'UsageSentinel-{version}-{suffix}';size=file.stat().st_size
 if not 1_000_000<size<=250_000_000:raise SystemExit('Invalid release asset size')
 assets.append(dict(platform=platform,url=f'https://github.com/Joe05520/ai-agent-usage-limit-reset-forecast/releases/download/v{version}/{file.name}',sha256=hashlib.sha256(file.read_bytes()).hexdigest(),size=size))
manifest=dict(schema=1,version=version,channel=channel,releaseURL=f'https://github.com/Joe05520/ai-agent-usage-limit-reset-forecast/releases/tag/v{version}',assets=assets)
data=json.dumps(manifest,sort_keys=True,separators=(',',':')).encode();output=root/'docs/updates';output.mkdir(exist_ok=True)
(output/f'{channel}.json').write_bytes(data);(output/f'{channel}.json.sig').write_text(base64.b64encode(key.sign(data)).decode()+'\n')
print(f'Signed {channel} manifest for {version}')

# Old binaries validate exact old repository URLs. Serve this separately at the
# former Pages path; GitHub keeps the repository alias redirect after rename.
legacy=json.loads(data)
for asset in legacy['assets']:
 asset['url']=asset['url'].replace('/ai-agent-usage-limit-reset-forecast/','/usage-sentinel/')
legacy['releaseURL']=legacy['releaseURL'].replace('/ai-agent-usage-limit-reset-forecast/','/usage-sentinel/')
legacy_data=json.dumps(legacy,sort_keys=True,separators=(',',':')).encode()
legacy_output=output/'legacy';legacy_output.mkdir(exist_ok=True)
(legacy_output/f'{channel}.json').write_bytes(legacy_data)
(legacy_output/f'{channel}.json.sig').write_text(base64.b64encode(key.sign(legacy_data)).decode()+'\n')
print('Signed legacy migration manifest with the existing key')
