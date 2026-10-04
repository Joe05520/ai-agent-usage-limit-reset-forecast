#!/usr/bin/env python3
"""Build on the target OS. PyInstaller intentionally does not cross-compile."""
from pathlib import Path
import importlib.metadata
import platform
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parents[1]; portable=root/'Portable'; output=root/'build/portable-package'; output.mkdir(parents=True,exist_ok=True)
shutil.copy2(root/'OpenAIUsageSentinel/Resources/Translations.json',portable/'sentinel/Translations.json')
subprocess.run([sys.executable,'-m','PyInstaller','--noconfirm','--clean','--onedir','--windowed','--name','UsageSentinel','--distpath',str(output/'dist'),'--workpath',str(output/'work'),'--specpath',str(output), '--add-data',str(portable/'sentinel/Translations.json')+':sentinel',str(portable/'main.py')],check=True,cwd=portable)
app=output/'dist/UsageSentinel'; shutil.copy2(root/'LICENSE',app/'LICENSE'); shutil.copy2(root/'THIRD_PARTY_NOTICES.md',app/'THIRD_PARTY_NOTICES.md'); shutil.copy2(root/'Scripts/claude_statusline_bridge.py',app/'claude_statusline_bridge.py')
licenses=app/'ThirdPartyLicenses'; licenses.mkdir(exist_ok=True)
for name in ('PySide6','PySide6-Essentials','shiboken6','pyinstaller'):
    dist=importlib.metadata.distribution(name)
    for file in dist.files or []:
        if 'license' in str(file).lower() and dist.locate_file(file).is_file():
            dest=licenses/name/str(file).replace('../',''); dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(dist.locate_file(file),dest)
base=root/'build'/('UsageSentinel-1.4.0-'+('Windows-x64' if sys.platform=='win32' else 'Linux-x64' if sys.platform=='linux' else 'Qt-macOS-dev'))
archive=shutil.make_archive(str(base),'zip' if sys.platform=='win32' else 'gztar',app.parent,app.name)
print(archive)
