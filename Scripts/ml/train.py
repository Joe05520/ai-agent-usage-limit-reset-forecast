"""Dependency-free CART trainer. Synthetic, grouped pilot evaluation, NOT real-world accuracy."""
import json, math, re, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
FEATURES={
'unrelated':r'password|api key|factory reset|reset your browser',
'negative':r'no (global )?reset|not (been )?reset|not been processed|not processed|not yet processed|never received|did not (get|receive)|hasn.t reset|won.t reset|reset (is |was )?cancelled',
'regular':r'scheduled reset|regular reset|weekly window ended|resets every week',
'exception':r'unexpected|suddenly|early reset|global reset',
'poll':r'vote|voting|poll|choose|update or (a )?reset|updates or (a )?reset',
'wish':r'hope|hopefully|wish|maybe|rumou?r',
'future':r'tomorrow|next week|coming|will reset|landing|即將|明天',
'completed':r'processed|propagated|reset is complete|limits (have been|were) reset|returned to 100|back to 100|allowance restored',
'firsthand':r'my |mine |i got|i received|我',
'reset':r'reset|quota|allowance|重置'}
# Distinct wording families; variants within a family never cross the split.
FAMILIES={
'irrelevant':['Reset your API key for security','Factory reset the laptop','Password reset instructions','Reset your browser preferences'],
'negative':['No global reset is planned','My quota has not been reset','I never received a reset','The reset was cancelled'],
'regular':['My scheduled reset arrived','The weekly window ended and quota reset','Usage resets every week','A regular reset restored my limit'],
'poll':['Vote for an update or a reset','Choose updates or a reset','A reset poll is open','Voting: global reset or new tools'],
'uncertain':['I hope we get a reset','Maybe a global reset happens','Hopefully my quota resets','A reset rumor is spreading'],
'forecast':['Global reset landing tomorrow','The quota reset is coming','Limits will reset next week','Tomorrow we will reset allowance'],
'completed':['The reset has been processed','Reset all propagated','The reset is complete','All limits have been reset'],
'accountReport':['My quota returned to 100%','Mine is back to 100% suddenly','I got my allowance restored','I received a reset, back to 100%']}
MIXED={
'negative':['No global reset; quota returned to 100% was just a rumor','The reset has not been processed','My quota has not been reset to 100%','No reset was processed despite the vote'],
'regular':['My scheduled reset returned to 100%','My regular reset has been processed','The weekly window ended and mine is back to 100%','Scheduled reset: all limits have been reset'],
'uncertain':['I hope the reset has been processed','Hopefully my quota returned to 100%','Maybe reset all propagated','I wish my allowance was back to 100%'],
'irrelevant':['Reset your API key: processed','Password reset is complete','Factory reset processed','Reset your browser: back to 100%'],
}
rows=[]
for label,phrases in FAMILIES.items():
 for i,phrase in enumerate(phrases):
  for product in ['Codex','ChatGPT','OpenAI']:
   rows.append(dict(text=product+' '+phrase,label=label,group=label+':'+str(i),split='test' if i==3 else 'train',provenance='author-written synthetic fixture'))
for label,phrases in MIXED.items():
 for i,phrase in enumerate(phrases):
  for product in ['Codex','ChatGPT','OpenAI']:
   rows.append(dict(text=product+' '+phrase,label=label,group='mixed:'+label+':'+str(i),split='test' if i==3 else 'train',provenance='author-written adversarial fixture'))
path=Path(__file__).with_name('fixtures.json');path.write_text(json.dumps(rows,indent=2)+'\n')
def features(text):return {k:bool(re.search(v,text.lower().replace('’',"'"))) for k,v in FEATURES.items()}
def impurity(rows):
 counts={label:sum(r['label']==label for r in rows) for label in FAMILIES}
 return 1-sum((v/len(rows))**2 for v in counts.values())
def tree(rows,keys,depth=0):
 counts={label:sum(r['label']==label for r in rows) for label in FAMILIES};label=max(counts,key=counts.get)
 leaf=dict(label=label,support=len(rows),purity=counts[label]/len(rows))
 if depth>=6 or impurity(rows)==0:return leaf
 candidates=[]
 for k in keys:
  yes=[r for r in rows if features(r['text'])[k]];no=[r for r in rows if not features(r['text'])[k]]
  if yes and no:candidates.append((impurity(rows)-(len(yes)*impurity(yes)+len(no)*impurity(no))/len(rows),k,yes,no))
 if not candidates:return leaf
 gain,k,yes,no=max(candidates,key=lambda x:(x[0],x[1]))
 if gain<=0:return leaf
 return dict(feature=k,yes=tree(yes,[x for x in keys if x!=k],depth+1),no=tree(no,[x for x in keys if x!=k],depth+1))
model=dict(schema=1,version='pilot-1',features=FEATURES,tree=tree([r for r in rows if r['split']=='train'],list(FEATURES)),factors={'completed':1,'accountReport':1,'forecast':.65,'poll':.45,'uncertain':.25,'negative':0,'regular':0,'irrelevant':0},training='108 synthetic examples; 36 grouped held-out synthetic examples; English pilot only')
def predict(text):
 node=model['tree'];f=features(text)
 while 'feature' in node:node=node['yes' if f[node['feature']] else 'no']
 return node['label']
test=[r for r in rows if r['split']=='test'];results=[dict(**r,predicted=predict(r['text'])) for r in test]
report=dict(description='Synthetic grouped smoke evaluation; not a production accuracy estimate',train=108,test=36,correct=sum(r['label']==r['predicted'] for r in results),results=results,datasetSHA256=hashlib.sha256(path.read_bytes()).hexdigest())
for dest in ['OpenAIUsageSentinel/Resources/ResetSemanticModel.json','Portable/sentinel/ResetSemanticModel.json','docs/reset-semantic-model.json']:(ROOT/dest).write_text(json.dumps(model,indent=2)+'\n')
Path(__file__).with_name('evaluation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"Grouped synthetic test: {report['correct']}/{len(test)}; NOT real-world accuracy")
(ROOT/'docs/reset-semantic.js').write_text('const resetSemanticModel='+json.dumps(model,separators=(',',':'))+';\n'+Path(__file__).with_name('web-runtime.js').read_text())
