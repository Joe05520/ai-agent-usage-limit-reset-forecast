import base64
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding,PublicFormat
from sentinel import extensions as e

class ExtensionsTests(unittest.TestCase):
    def fixture(self):
        v='1.5.0'
        return dict(schema=1,version=v,channel='preview',releaseURL=f'https://github.com/Joe05520/ai-agent-usage-limit-reset-forecast/releases/tag/v{v}',assets=[dict(platform=p,url=f'https://github.com/Joe05520/ai-agent-usage-limit-reset-forecast/releases/download/v{v}/UsageSentinel-{v}-'+s,sha256='a'*64,size=2000000) for p,s in [('macOS','macOS-universal.zip'),('Windows','Windows-x64.zip'),('Linux','Linux-x64.tar.gz')]])
    def test_signed_update_tampering_and_foreign_assets(self):
        key=Ed25519PrivateKey.generate(); public=base64.b64encode(key.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)).decode(); raw=json.dumps(self.fixture()).encode();sig=base64.b64encode(key.sign(raw))
        self.assertEqual(e.verify_manifest(raw,sig,public,'preview')['version'],'1.5.0')
        for changes in [raw+b' ',raw.replace(b'1.5.0',b'9.9.9')]:
            with self.assertRaises(Exception):e.verify_manifest(changes,sig,public,'preview')
        fixture=self.fixture();fixture['assets'][0]['url']='https://evil.test/a.zip';raw=json.dumps(fixture).encode()
        with self.assertRaises(Exception):e.verify_manifest(raw,base64.b64encode(key.sign(raw)),public,'preview')
    def test_rename_keeps_exact_repository_validation(self):
        key=Ed25519PrivateKey.generate(); public=base64.b64encode(key.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)).decode()
        raw=json.dumps(self.fixture()).encode()
        for bad in [raw.replace(b'ai-agent-usage-limit-reset-forecast',b'usage-sentinel'),raw.replace(b'Joe05520',b'someone-else')]:
            with self.assertRaises(Exception): e.verify_manifest(bad,base64.b64encode(key.sign(bad)),public,'preview')
    def test_version_and_link_security(self):
        self.assertTrue(e.version('1.5.0')>e.version('1.4.0'))
        for value in ['1.2','1.2.3.4','1.2.-3','1.2.٣']:
            with self.assertRaises(ValueError):e.version(value)
        for value in ['file:///tmp/a','javascript:alert(1)','http://example.com','https://user:pass@example.com','https://example.com:444']:self.assertFalse(e.safe_url(value))
    def test_no_request_without_consent_and_no_exact_quota(self):
        yesterday=time.strftime('%Y-%m-%d',time.gmtime(time.time()-86400));settings=dict(agent='Codex',stages=[30,10],analytics=False,share_quota=False);state=dict(closed=dict(day=yesterday,observations=3,quotaBand='20-49',agent='codex'))
        self.assertIsNone(e.payload(settings,state,'test'))
        with patch.object(e,'request') as request:
            self.assertIsNone(e.send_analytics(settings,state));request.assert_not_called()
        settings['analytics']=True;body=e.payload(settings,state,'test');self.assertEqual(body['quotaBand'],'unknown');self.assertNotIn('remaining',body);settings['share_quota']=True;self.assertEqual(e.payload(settings,state,'test')['quotaBand'],'20-49')
        state['sent']=yesterday;self.assertIsNone(e.payload(settings,state,'test'))
    def test_redirect_rejects_downgrade_and_other_hosts(self):
        from urllib.request import Request
        redirect=e.Redirects(['github.com'])
        for value in ['https://evil.test/app','http://github.com/app']:
            with self.assertRaises(RuntimeError):redirect.redirect_request(Request('https://github.com/a'),None,302,'',{},value)
