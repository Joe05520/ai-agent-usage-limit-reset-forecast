import unittest
from sentinel.reset_watch import weight,classify_watch,parse_feed
from sentinel import core

class ResetWatchTests(unittest.TestCase):
    def source(self,text='Vote for a reset',handle='thsottiaux',via=None):
        return dict(title='Codex',url=f'https://x.com/{handle}/status/123',platform='X',publishedAt=100000,fetchedAt=100000,author=handle,snippet=text,official=False,**({'viaURL':via} if via else {}))
    def test_policy_and_spoof(self):
        self.assertEqual(weight(self.source(handle='codex_resets')),.75)
        self.assertEqual(weight(self.source()),.85)
        s=self.source();s['url']='https://x.com.evil.test/thsottiaux/status/123';self.assertIsNone(weight(s))
        self.assertIsNone(weight(self.source(via='https://evil.test')))
    def test_poll_tease_complete(self):
        self.assertEqual(core.classify(self.source())['type'],'poll')
        self.assertEqual(core.classify(self.source('I do like giving resets'))['type'],'forecast')
        self.assertEqual(core.classify(self.source('Reset all propagated'))['type'],'suspectedGlobal')
        self.assertIsNone(classify_watch(self.source('No reset today')))
    def test_mirror_dedup_decay(self):
        a=self.source(via='https://codex-resets.com');b=self.source(via='https://codex-reset.com')
        self.assertEqual(len(core.dedup([a,b])),1)
        self.assertEqual(core.confidence([a,b],False,100000),.85)
        self.assertLess(core.confidence([a,b],False,107200),.85)
    def test_expired_poll(self):
        signal=core.classify(self.source());self.assertEqual(core.merge([], [signal],[],186401),[])
        event=core.merge([], [signal],[],100000)[0]
        self.assertTrue(core.should_notify(event,{},100000))
        self.assertFalse(core.should_notify(event,{},186401))
    def test_same_post_completion_upgrades(self):
        event=core.merge([], [core.classify(self.source())],[],100000)
        self.assertEqual(core.merge(event,[core.classify(self.source('Reset all propagated'))],[],100100)[0]['type'],'suspectedGlobal')
    def test_related_vote_and_stale(self):
        root=dict(profile=dict(handle='thsottiaux'),stale=False,tweets=[dict(id='123',url='https://x.com/thsottiaux/status/123',text='I accept your vote',at=100000,tibo_lane='reset_related')])
        self.assertEqual(parse_feed(root,'radar',100000)[0]['type'],'poll')
        root['stale']=True
        with self.assertRaises(ValueError):parse_feed(root,'radar',100000)
