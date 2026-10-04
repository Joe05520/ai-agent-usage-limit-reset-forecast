# Windows and Linux client

Native Qt Widgets tray client, without Electron or a hosted backend. The macOS download uses the separate native SwiftUI/MenuBarExtra app.

## Download and run

Get a release from [GitHub Releases](https://github.com/Joe05520/usage-sentinel/releases). Windows: extract the entire `UsageSentinel` folder and launch `UsageSentinel.exe`. Linux: extract and run `./UsageSentinel/UsageSentinel`; do not move just the executable out of its directory. Packages include their Python/Qt runtime, so Python is not needed to launch the app. The optional Claude bridge needs Python.

Windows 10/11 x64 and Linux x64 with glibc 2.28+ and Qt-compatible graphics libraries are the target environments. CI packages on Windows and Ubuntu 22.04. Linux may need `libegl1`, `libxkbcommon-x11-0`, `libxcb-cursor0`, `libxcb-icccm4`, `libxcb-keysyms1`, `libxcb-shape0` and `libxrender1`. GNOME may need a tray/AppIndicator extension. If no tray exists, Sentinel keeps a normal window available. Desktop notification support, Do Not Disturb, Wayland behavior and login launch vary with the desktop. Offscreen CI is not proof of real desktop notification delivery; these ports are marked **beta**.

## Run from source

```sh
python3 -m venv .venv
# Linux/macOS: source .venv/bin/activate
# Windows: .venv\Scripts\activate
python -m pip install -r Portable/requirements.txt
python Portable/main.py --show
```

`--mock --show` uses a separate `portable-mock.sqlite` and no live usage/news requests. Its settings button runs personal unexpected reset and a consolidated five-stage quota scenario. `--smoke-test` creates the Qt window, runs fixture checks, and exits.

```sh
PYTHONPATH=Portable python3 -m unittest discover -s Portable/tests -v
QT_QPA_PLATFORM=offscreen python3 Portable/main.py --smoke-test
python3 Scripts/package_portable.py
```

On PowerShell use `$env:PYTHONPATH='Portable'` and `$env:QT_QPA_PLATFORM='offscreen'` before the equivalent Python commands. Build on the target OS; PyInstaller does not cross-compile.

## Feature coverage

Implemented: official Codex provider, agent-specific local exports, regular reset time, local SQLite history storage, five-stage reminders, unexpected personal increases, public GitHub/Reddit/official RSS/HN sources, confidence scoring, clustering, deduplication, threshold upgrades, native tray notifications, event source links, five interface languages, login launch, per-source backoff/cache and diagnostics.

The macOS app currently has richer history charts, confidence timelines, five menu-text styles, per-bucket reminder switches and additional Help Center/release-note adapters. The portable interface has two tray icon styles (brand or percentage); detailed quota text appears in the tooltip/menu because Windows/Linux trays do not provide macOS-style status-item text. Portable history is stored and event sources are viewable; there is no history chart yet. Some technical status strings remain English. X and undocumented authenticated usage APIs are not implemented.
