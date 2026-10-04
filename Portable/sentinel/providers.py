import json
from pathlib import Path
import queue
import shutil
import subprocess
import threading
import time
from .core import parse_codex, parse_export


def codex_usage(custom=""):
    exe = custom or shutil.which("codex")
    if not exe:
        raise RuntimeError("Install and sign in to the official Codex CLI, or choose its executable in Settings.")
    command = [exe]
    if Path(exe).suffix.lower() in (".cmd", ".bat"):
        script = Path(exe).parent/"node_modules/@openai/codex/bin/codex.js"
        node = shutil.which("node")
        if not script.is_file() or not node:
            raise RuntimeError("Choose the native Codex executable or install the official npm CLI with Node.js.")
        command = [node, str(script)]
    proc = subprocess.Popen(command+["app-server", "-c", "analytics.enabled=false"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=Path.home(), creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    lines = queue.Queue(maxsize=1000)
    def read():
        total = 0
        try:
            while True:
                line = proc.stdout.readline(2_000_001)
                total += len(line)
                if not line or total > 2_000_000:
                    lines.put_nowait(None); break
                lines.put_nowait(line)
        except (OSError, ValueError, queue.Full):
            pass
    threading.Thread(target=read, daemon=True).start()
    deadline = time.monotonic()+25
    def send(obj):
        proc.stdin.write(json.dumps(obj).encode()+b"\n"); proc.stdin.flush()
    def response(ident):
        while True:
            try: line = lines.get(timeout=max(.01, deadline-time.monotonic()))
            except queue.Empty: raise TimeoutError("Codex read timed out after 25 seconds") from None
            if line is None: raise RuntimeError("Codex connection closed or exceeded 2 MB")
            try: obj = json.loads(line)
            except ValueError: continue
            if obj.get("id") != ident: continue
            if "error" in obj: raise RuntimeError("Codex rejected the read; check official sign-in. Sentinel does not read credentials.")
            return obj["result"]
    try:
        send(dict(id=1, method="initialize", params=dict(clientInfo=dict(name="usage_sentinel", title="Usage Sentinel", version="1.4.0"))))
        response(1); send(dict(method="initialized", params={}))
        send(dict(id=2, method="account/rateLimits/read"))
        return parse_codex(response(2))
    finally:
        if proc.poll() is None: proc.terminate()
        try: proc.wait(timeout=3)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=3)
        proc.stdin.close(); proc.stdout.close()


def export_usage(path, agent):
    if not path: raise RuntimeError("Choose a local usage JSON export; no subscription API is assumed.")
    file = Path(path).expanduser()
    if file.stat().st_size > 1_000_000: raise RuntimeError("Export exceeds 1 MB")
    return parse_export(json.loads(file.read_text(encoding="utf-8")), agent)
