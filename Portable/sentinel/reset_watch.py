"""Free public secondary feeds. Editorial weights are not forecast probabilities."""
from urllib.parse import urlsplit
from .core import epoch

def weight(source):
    url = urlsplit(source.get('url', '')); parts = url.path.strip('/').split('/')
    if url.scheme != 'https' or url.netloc.lower() not in ('x.com','www.x.com','twitter.com','www.twitter.com') or len(parts) != 3 or parts[1] != 'status' or not parts[2].isdigit(): return None
    author = parts[0].lower()
    if author not in ('thsottiaux','codex_resets') or source.get('author','').lower().lstrip('@') != author: return None
    via = source.get('viaURL')
    if via:
        via = urlsplit(via)
        if via.scheme != 'https' or via.netloc not in ('codex-resets.com','codex-reset.com'): return None
        if via.netloc == 'codex-resets.com': return .75
        return .85 if author == 'thsottiaux' else None
    return .85 if author == 'thsottiaux' else .75

def classify_watch(source):
    if weight(source) is None: return None
    text = source.get('snippet','').lower().replace('’',"'"); context = source.get('watchContext','').lower()
    if not ('reset' in text or 'reset' in context and any(k in text for k in ('vote','poll'))): return None
    if any(k in text for k in ('password','factory reset','no reset','not reset',"won't reset","can't really give a reset","didn't get the reset","did not get the reset")): return None
    completed = any(k in text for k in ('reset all propagated','resets all propagated','reset has been processed','limits have been reset','all reset for everyone','reset is complete'))
    kind = 'banked' if 'banked' in text else 'suspectedGlobal' if completed else 'poll' if any(k in text for k in ('vote','voting','poll','choose','how was day')) else 'forecast'
    source = dict(source)
    if kind in ('poll','forecast'): source.setdefault('expiresAt', (source.get('publishedAt') or source['fetchedAt'])+86400)
    if source.get('viaURL'): source['official'] = False
    return dict(source=source, product='Codex', model=None, type=kind)

def parse_feed(root, kind, now):
    result = []
    if kind == 'radar':
        if root.get('stale') or root.get('profile',{}).get('handle') != 'thsottiaux' or not isinstance(root.get('tweets'),list): raise ValueError('Stale or unavailable Tibo radar')
        rows = root['tweets']; texts = {r.get('id'): r.get('text','') for r in rows}
        for r in rows:
            context = texts.get(r.get('in_reply_to_tweet_id'),'')
            if not 'reset' in context.lower() and r.get('tibo_lane') == 'reset_related': context = 'Reset-related thread (secondary feed classification)'
            source = dict(title='Codex · Tibo @thsottiaux',url=r.get('url',''),platform='X via Tibo radar',publishedAt=epoch(r['at']),fetchedAt=now,author='thsottiaux',snippet=r.get('text','')[:1500],official=False,viaURL='https://codex-reset.com',watchContext=context)
            if source['publishedAt'] <= now+300:
                signal = classify_watch(source)
                if signal: result.append(signal)
    else:
        data = root.get('data')
        if not isinstance(data,(list,dict)): raise ValueError('Codex Resets schema unavailable')
        rows = data if isinstance(data,list) else [data.get(k) for k in ('latest_reset','active_watch','scheduled_reset')]
        for r in rows:
            if not r or r.get('source',{}).get('type') != 'x_post': continue
            evidence = r['source']; stamp = r.get('announced_at') or r.get('observed_at')
            if not stamp: continue
            source = dict(title='Codex · @'+evidence.get('author',''),url=evidence.get('url',''),platform='X via Codex Resets',publishedAt=epoch(stamp),fetchedAt=now,author=evidence.get('author',''),snippet=r.get('text','')[:1500],official=False,viaURL='https://codex-resets.com')
            if source['publishedAt'] > now+300: continue
            signal = classify_watch(source)
            if signal:
                if r.get('scheduled_for') or r.get('expires_at'):
                    signal['type'] = 'poll' if 'poll' in source['snippet'].lower() else 'forecast'
                    source['expiresAt'] = epoch(r['expires_at']) if r.get('expires_at') else source['publishedAt']+86400
                    if r.get('scheduled_for'): source['announcedTarget'] = epoch(r['scheduled_for'])
                    signal['source'] = source
                result.append(signal)
    return result
