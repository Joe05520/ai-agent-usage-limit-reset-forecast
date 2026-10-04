"""Check all explicit app localization keys and format placeholders without networking."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
catalog=json.loads((root/'OpenAIUsageSentinel/Resources/Translations.json').read_text())
languages={'en','zh-Hant','zh-Hans','ja','ko'}
errors=[]
for key, translations in catalog.items():
 if set(translations)!=languages or any(not text for text in translations.values()):errors.append(f'Incomplete translation: {key}')
 reference=re.findall(r'%(?:@|d)',key)
 for language,text in translations.items():
  if re.findall(r'%(?:@|d)',text)!=reference:errors.append(f'Format parameters differ: {language} {key}')
for path in (root/'OpenAIUsageSentinel').rglob('*.swift'):
 for match in re.finditer(r'L10n\.(?:t|f)\(("(?:[^"\\]|\\.)*")',path.read_text()):
  key=json.loads(match.group(1))
  if key not in catalog:errors.append(f'Missing key: {path.name}: {key}')
if errors:raise SystemExit('\n'.join(errors))
print(f'{len(catalog)} keys in {len(languages)} languages; all explicit keys and format parameters passed.')
