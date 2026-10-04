#!/usr/bin/env python3
"""Official Claude Code statusLine stdin → quota-only local export. No credentials."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import tempfile
import math


def default_path():
    if sys.platform == "darwin": return Path.home()/"Library/Application Support/OpenAIUsageSentinel/claude-usage.json"
    if sys.platform == "win32": return Path(os.environ.get("LOCALAPPDATA", Path.home()))/"UsageSentinel/claude-usage.json"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home()/".local/share"))/"usage-sentinel/claude-usage.json"


def convert(root, profile=None, now=None):
    now = now or datetime.now(timezone.utc)
    buckets = []
    for key, name, mins in (("five_hour", "5-hour", 300), ("seven_day", "Weekly", 10080), ("spend_limit", "Spend limit", None)):
        row = (root.get("rate_limits") or {}).get(key) or {}; used = row.get("used_percentage")
        if isinstance(used, bool) or not isinstance(used, (int, float)) or not math.isfinite(used) or used < 0:
            continue
        reset = row.get("resets_at")
        if isinstance(reset, bool) or not isinstance(reset, (int, float)) or not math.isfinite(reset) or reset <= now.timestamp():
            continue
        buckets.append(dict(id=key, name=name, remainingPercent=max(0, 100-used), windowDurationMins=mins, resetAt=datetime.fromtimestamp(reset, timezone.utc).isoformat()))
    return dict(schemaVersion=1, product="Claude", origin="official Claude Code status line", timestamp=now.isoformat(), profile=profile, buckets=buckets)


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--output", type=Path, default=default_path()); parser.add_argument("--profile", help="Non-secret label to distinguish your account; do not use a token")
    args = parser.parse_args()
    try:
        raw = sys.stdin.buffer.read(2_000_001)
        if len(raw) > 2_000_000: raise ValueError("Input too large")
        export = convert(json.loads(raw), args.profile)
        path = args.output.expanduser(); path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Write even an empty export: it invalidates prior windows that disappeared.
        fd, temporary = tempfile.mkstemp(prefix=".usage-", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as file: json.dump(export, file, ensure_ascii=False)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary): os.unlink(temporary)
        print("Claude · "+(" · ".join(f"{b['name']} {b['remainingPercent']:g}% left" for b in export["buckets"]) or "quota unavailable"))
    except (ValueError, OSError, TypeError) as error:
        # Never print the input, full payload, transcript path, or credential data.
        print("Claude · quota unavailable", flush=True)
        return 1
    return 0

if __name__ == "__main__": sys.exit(main())
