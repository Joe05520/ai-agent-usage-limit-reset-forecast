"""Opt-in login launch; no shell scripts, credentials, or background services."""
from pathlib import Path
import os
import subprocess
import sys


def argv():
    return [sys.executable] if getattr(sys, "frozen", False) else [sys.executable, str(Path(__file__).resolve().parents[1]/"main.py")]


def enabled():
    if sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run") as key:
                return winreg.QueryValueEx(key, "UsageSentinel")[0] == subprocess.list2cmdline(argv())
        except OSError: return False
    return (Path(os.environ.get("XDG_CONFIG_HOME", Path.home()/".config"))/"autostart/usage-sentinel.desktop").exists() if sys.platform == "linux" else False


def set_enabled(value):
    if sys.platform == "win32":
        import winreg
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run") as key:
            if value: winreg.SetValueEx(key, "UsageSentinel", 0, winreg.REG_SZ, subprocess.list2cmdline(argv()))
            else:
                try: winreg.DeleteValue(key, "UsageSentinel")
                except FileNotFoundError: pass
    elif sys.platform == "linux":
        path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home()/".config"))/"autostart/usage-sentinel.desktop"
        if value:
            def quote(arg):
                return '"'+arg.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')+'"'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("[Desktop Entry]\nType=Application\nName=Usage Sentinel\nExec="+" ".join(quote(v) for v in argv())+"\nX-GNOME-Autostart-enabled=true\n", encoding="utf-8")
        else: path.unlink(missing_ok=True)
    else:
        raise RuntimeError("Use the native Swift macOS app for Launch at Login")
