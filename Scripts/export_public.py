#!/usr/bin/env python3
"""Prepare a public source checkout without private development evidence/history."""
from pathlib import Path
import shutil
import sys
root=Path(__file__).resolve().parents[1]
dest=root/'build/public-repository'; dest.mkdir(parents=True,exist_ok=True)
allowed=['OpenAIUsageSentinel','OpenAIUsageSentinel.xcodeproj','Tests','Scripts','Portable','docs','.github','README.md','Package.swift','LICENSE','SECURITY.md','CONTRIBUTING.md','THIRD_PARTY_NOTICES.md','.gitignore']
for name in allowed:
    source=root/name; target=dest/name
    if source.is_dir():
        if target.exists(): shutil.rmtree(target)
        shutil.copytree(source,target,ignore=shutil.ignore_patterns('__pycache__','*.pyc','xcuserdata','*.xcuserstate','build','dist','*.sqlite*','*.log'))
    else: shutil.copy2(source,target)
for file in dest.rglob('*'):
    if not file.is_file() or '.git' in file.parts: continue
    if file.suffix in ['.sqlite','.log'] or file.name.startswith('.env'): raise SystemExit(f'Private artifact: {file}')
    try: text=file.read_text()
    except UnicodeDecodeError: continue
    for forbidden in [str(Path.home()),'gh'+'o_', 'sk-'+'proj-']:
        if forbidden in text: raise SystemExit(f'Private marker in {file.relative_to(dest)}')
print(dest)
