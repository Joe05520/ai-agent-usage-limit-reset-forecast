import json
import os
from pathlib import Path
import sqlite3
import sys
import time


def data_dir():
    if sys.platform == "win32":
        return Path(os.environ.get("LOCALAPPDATA", Path.home())) / "UsageSentinel"
    if sys.platform == "darwin":
        return Path.home()/"Library/Application Support/OpenAIUsageSentinel"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home()/".local/share"))/"usage-sentinel"


class Database:
    def __init__(self, path):
        path = Path(path); path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = path
        self.db = sqlite3.connect(path)
        self.db.execute("CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, payload TEXT NOT NULL)")
        self.db.execute("CREATE TABLE IF NOT EXISTS snapshots (timestamp REAL NOT NULL, payload TEXT NOT NULL)")
        self.db.commit()
        if os.name != "nt": os.chmod(path, 0o600)

    def load(self, key, default=None):
        row = self.db.execute("SELECT payload FROM state WHERE key=?", (key,)).fetchone()
        return json.loads(row[0]) if row else default

    def save(self, key, value):
        self.db.execute("INSERT OR REPLACE INTO state VALUES (?, ?)", (key, json.dumps(value)))
        self.db.commit()

    def append(self, snapshot):
        self.db.execute("INSERT INTO snapshots VALUES (?, ?)", (snapshot["timestamp"], json.dumps(snapshot)))
        self.db.execute("DELETE FROM snapshots WHERE timestamp < ?", (time.time()-35*86400,))
        self.db.commit()

    def latest(self, source):
        # Provider history is independent; switching the visible agent is not a reset.
        for row in self.db.execute("SELECT payload FROM snapshots ORDER BY timestamp DESC LIMIT 10000"):
            state = json.loads(row[0])
            if state["source"] == source: return state
        return None
