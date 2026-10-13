"""Offline shared CART pilot. Abstain on unknown wording; no inference requests."""
import json,re
from pathlib import Path
try:
 MODEL=json.loads(Path(__file__).with_name('ResetSemanticModel.json').read_text())
except (OSError,ValueError):
 MODEL=None
REQUIRED={'forecast':'future','poll':'poll','completed':'completed','accountReport':'completed','uncertain':'wish','regular':'regular','negative':'negative','irrelevant':'unrelated'}
def assess(text):
 if not MODEL or MODEL.get('schema')!=1 or len(text)>100000:return None
 features={k:bool(re.search(v,text.lower().replace('’',"'"))) for k,v in MODEL['features'].items()}
 if not any(v for k,v in features.items() if k!='reset'):return None
 node=MODEL['tree'];reasons=[]
 for _ in range(16):
  if 'feature' not in node:break
  key=node['feature'];hit=features.get(key,False)
  if hit:reasons.append(key)
  node=node['yes' if hit else 'no']
 label=node.get('label')
 if not features.get(REQUIRED.get(label)):return None
 if label=='regular' and features['exception']:return None
 return dict(label=label,factor=MODEL['factors'][label],reasons=reasons)
def factor(source):
 if source['platform'].startswith(('Local','Manual')):return 1
 return (assess(source['title']+' '+source['snippet']) or {}).get('factor',1)
