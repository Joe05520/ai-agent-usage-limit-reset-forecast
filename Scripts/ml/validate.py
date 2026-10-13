"""Cross-runtime consistency and grouped fixture checks; no network."""
import json,sys,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2];sys.path.insert(0,str(root/'Portable'))
from sentinel.semantic import assess
rows=json.loads(Path(__file__).with_name('fixtures.json').read_text())
train={r['group'] for r in rows if r['split']=='train'};test={r['group'] for r in rows if r['split']=='test'}
assert not train & test
for r in rows:assert assess(r['text'])['label']==r['label'],r
js=(root/'docs/reset-semantic.js').read_text()+"\nconsole.log(JSON.stringify("+json.dumps([r['text'] for r in rows])+".map(assessResetText)));"
web=json.loads(subprocess.check_output(['node','-e',js]))
assert web==[assess(r['text']) for r in rows]
models=[json.loads((root/p).read_text()) for p in ['OpenAIUsageSentinel/Resources/ResetSemanticModel.json','Portable/sentinel/ResetSemanticModel.json','docs/reset-semantic-model.json']]
assert models[0]==models[1]==models[2]
print(f'{len(rows)} synthetic cases: Python/JavaScript parity, shared models, disjoint group split passed')
