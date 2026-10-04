import copy
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from sentinel import core
from sentinel.storage import Database

NOW=1791100800


def usage(percent=30, seconds=0, reset=None, agent="Codex"):
    return core.parse_export(dict(schemaVersion=1,timestamp=NOW+seconds,profile="fixture",buckets=[dict(id="weekly",name="Weekly",remainingPercent=percent,resetAt=reset if reset is not None else NOW+3*86400,windowDurationMins=10080)]),agent,NOW+seconds)


def source(i=1, platform="Reddit", official=False, text=None, age=0, product="Codex"):
    return dict(title=text or f"My {product} quota reset unexpectedly {i}",url=f"https://example.com/mock/{platform}/{i}",platform=platform,official=official,publishedAt=NOW-age,fetchedAt=NOW,author=f"user{i}",snippet=f"My weekly allowance was refreshed; evidence number {i}.")


class QuotaTests(unittest.TestCase):
    def test_five_stages_once_and_restart(self):
        engine=core.ReminderEngine(); settings=dict(stages=[50,30,20,10,5])
        for i,value in enumerate(settings["stages"]):
            state=usage(value,i); engine.observe(state); alerts=engine.pending(state,settings,NOW+i)
            self.assertEqual(len(alerts),1); self.assertEqual(alerts[0]["threshold"],value); engine.delivered(alerts[0])
            engine=core.ReminderEngine(json.loads(json.dumps(engine.cycles)))
            self.assertFalse(engine.pending(state,settings,NOW+i))
    def test_jump_consolidates_all_five(self):
        engine=core.ReminderEngine(); state=usage(3); engine.observe(state); alert=engine.pending(state,dict(stages=[50,30,20,10,5]),NOW)
        self.assertEqual(len(alert),1); self.assertEqual(alert[0]["covered"],[5,10,20,30,50]); self.assertTrue(alert[0]["critical"])
    def test_limit_duplicates_and_invalid(self):
        self.assertEqual(core.thresholds([50,30,20,10,5,1,30,True,-1,100,float('nan')]),[50,30,20,10,5])
    def test_disabled_snoozed_stale_excluded(self):
        engine=core.ReminderEngine(); state=usage(5); engine.observe(state)
        for settings, now in [(dict(reminders_enabled=False),NOW),(dict(snooze=NOW+1),NOW),(dict(excluded=[state['buckets'][0]['id']]),NOW),({},NOW+601)]: self.assertFalse(engine.pending(state,settings,now))
    def test_recovery_rearms(self):
        engine=core.ReminderEngine(); state=usage(20); engine.observe(state); engine.delivered(engine.pending(state,{},NOW)[0])
        recovered=usage(100,1); engine.observe(recovered); state=usage(20,2); engine.observe(state)
        self.assertEqual(len(engine.pending(state,{},NOW+2)),1)
    def test_oscillation_and_out_of_order_dont_rearm(self):
        engine=core.ReminderEngine(); state=usage(20,2); engine.observe(state); engine.delivered(engine.pending(state,{},NOW+2)[0])
        engine.observe(usage(100,1)); engine.observe(usage(22,3)); state=usage(20,4); engine.observe(state); self.assertFalse(engine.pending(state,{},NOW+4))
    def test_denied_not_marked(self):
        engine=core.ReminderEngine(); state=usage(20); engine.observe(state)
        self.assertEqual(len(engine.pending(state,{},NOW)),1); self.assertEqual(len(engine.pending(state,{},NOW)),1)
    def test_scheduled_reset(self):
        before=usage(23,reset=NOW+30); after=usage(100,seconds=60)
        self.assertEqual(core.personal_resets(before,after)[0]['type'],'scheduled')
    def test_unexpected_and_non_openai_source(self):
        before=usage(23,agent='Claude'); after=usage(100,60,agent='Claude'); event=core.personal_resets(before,after)[0]
        self.assertEqual(event['type'],'accountUnexpected'); self.assertIn('code.claude.com',event['sources'][0]['url'])
    def test_banked_and_purchased_intent(self):
        for kind in ['banked','purchased']:
            self.assertEqual(core.personal_resets(usage(23),usage(100,60),dict(type=kind,at=NOW))[0]['type'],kind)
    def test_credit_decrease_ambiguous(self):
        before=usage(23); after=usage(100,60); before['credits']=2; after['credits']=1
        self.assertEqual(core.personal_resets(before,after)[0]['type'],'unknown')
    def test_account_switch_and_large_gap(self):
        before=usage(23); after=usage(100,60); after['account']='different'; self.assertFalse(core.personal_resets(before,after))
        self.assertFalse(core.personal_resets(before,usage(100,86400)))
    def test_missing_schedule_is_unknown(self):
        before=usage(23); before['buckets'][0]['reset']=None
        self.assertEqual(core.personal_resets(before,usage(100,60))[0]['type'],'unknown')
    def test_codex_dynamic_windows_and_null(self):
        state=core.parse_codex(dict(rateLimitsByLimitId={'future':dict(limitName='Future',primary=dict(usedPercent=32,windowDurationMins=60,resetsAt=NOW+1000),secondary=None)}),NOW)
        self.assertEqual(len(state['buckets']),1); self.assertEqual(state['buckets'][0]['remaining'],68)
        with self.assertRaises(ValueError): core.parse_codex(dict(rateLimits={}),NOW)
    def test_exports_reject_future_duplicate_boolean(self):
        for value in [True,101,-1,float('nan')]:
            root=dict(schemaVersion=1,timestamp=NOW,buckets=[dict(id='x',name='Weekly',remainingPercent=value)])
            with self.assertRaises(ValueError): core.parse_export(root,'Grok',NOW)
        with self.assertRaises(ValueError): usage(20,reset='bad')
    def test_sqlite_roundtrip_and_provider_history(self):
        with tempfile.TemporaryDirectory() as folder:
            db=Database(Path(folder)/'usage.sqlite'); db.save('cycles',dict(test=[1,2])); self.assertEqual(db.load('cycles')['test'],[1,2])
            state=usage(); db.append(state); db.append(usage(agent='Claude'))
            self.assertEqual(db.latest(state['source'])['buckets'][0]['product'],'Codex')
            db.db.close()


class SignalTests(unittest.TestCase):
    def test_two_reddit_early_notification(self):
        signals=[core.classify(source(i)) for i in [1,2]]; events=core.merge([],signals,[],NOW)
        self.assertEqual(len(events),1); self.assertAlmostEqual(events[0]['confidence'],.28); self.assertTrue(core.should_notify(events[0],{},NOW))
    def test_official_confirmation(self):
        event=core.merge([],[core.classify(source(1,'OpenAI News',True))],[],NOW)[0]
        self.assertGreaterEqual(event['confidence'],.9); self.assertEqual(event['type'],'automaticGlobal')
    def test_duplicate_text_url_and_author_no_extra(self):
        a=source(); b=source(2); b['title']=a['title']; b['snippet']=a['snippet']; self.assertEqual(len(core.dedup([a,b])),1)
        b=source(2); b['author']=a['author']; self.assertEqual(len(core.dedup([a,b])),1)
    def test_old_no_current_event(self):
        self.assertFalse(core.merge([],[core.classify(source(age=86401))],[],NOW))
    def test_age_decay(self):
        self.assertLess(core.confidence([source(age=90000)],False,NOW),core.confidence([source()],False,NOW))
    def test_own_quota_strengthens_cluster(self):
        events=core.merge([],[core.classify(source(i)) for i in [1,2]],[],NOW)
        own=core.personal_resets(usage(17),usage(100,60)); events=core.merge(events,[],own,NOW+60)
        self.assertEqual(len(events),1); self.assertTrue(events[0]['own']); self.assertGreater(events[0]['confidence'],.28); self.assertLess(events[0]['confidence'],.6)
    def test_official_codex_personal_evidence_gets_full_weight(self):
        before=core.parse_codex(dict(rateLimits=dict(primary=dict(usedPercent=83,windowDurationMins=10080,resetsAt=NOW+3*86400))),NOW)
        after=core.parse_codex(dict(rateLimits=dict(primary=dict(usedPercent=0,windowDurationMins=10080,resetsAt=NOW+3*86400))),NOW+60)
        own=core.personal_resets(before,after)
        events=core.merge([],[core.classify(source(i)) for i in [1,2]],[],NOW)
        events=core.merge(events,[],own,NOW+60)
        self.assertEqual(len(events),1); self.assertGreaterEqual(events[0]['confidence'],.6)
    def test_no_duplicate_notification_tiny_score_change(self):
        event=core.merge([],[core.classify(source(i)) for i in [1,2]],[],NOW)[0]; event['notified']=core.level(event['confidence'])
        event['confidence']+=.01; self.assertFalse(core.should_notify(event,{},NOW)); event['confidence']=.65; self.assertTrue(core.should_notify(event,{},NOW))
    def test_segmentation_and_negative_posts(self):
        events=core.merge([],[core.classify(source(1,product='Claude')),core.classify(source(2,product='Codex'))],[],NOW)
        self.assertEqual(len(events),2); self.assertIsNone(core.classify(source(text='Codex password reset')))
    def test_community_cannot_confirm(self):
        self.assertLess(core.confidence([source(i) for i in range(30)],True,NOW),.9)
    def test_scheduled_silent(self):
        event=core.personal_resets(usage(20,reset=NOW+30),usage(100,60))[0]; self.assertFalse(core.should_notify(event,{},NOW+60))


class ClaudeBridgeTests(unittest.TestCase):
    def test_official_schema_only_exported(self):
        path=Path(__file__).resolve().parents[2]/'Scripts/claude_statusline_bridge.py'
        spec=importlib.util.spec_from_file_location('bridge',path); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        root=dict(rate_limits=dict(five_hour=dict(used_percentage=28,resets_at=NOW+5000)),transcript_path='PRIVATE',session_id='PRIVATE',context_window=dict(used_percentage=95))
        export=module.convert(root,'fixture',datetime.fromtimestamp(NOW,timezone.utc))
        self.assertEqual(export['buckets'][0]['remainingPercent'],72); self.assertNotIn('PRIVATE',json.dumps(export)); self.assertEqual(len(export['buckets']),1)
    def test_missing_quota_not_context_window(self):
        path=Path(__file__).resolve().parents[2]/'Scripts/claude_statusline_bridge.py'
        spec=importlib.util.spec_from_file_location('bridge2',path); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        self.assertEqual(module.convert(dict(context_window=dict(used_percentage=1)))['buckets'],[])

if __name__=='__main__': unittest.main()
