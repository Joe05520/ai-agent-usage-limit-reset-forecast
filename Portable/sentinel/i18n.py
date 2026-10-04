import json
from pathlib import Path
import re

LANGUAGES = {"en": "English", "zh-Hant": "繁體中文", "zh-Hans": "简体中文", "ja": "日本語", "ko": "한국어"}


class Translator:
    def __init__(self, language="en"):
        self.language = language
        self.catalog = json.loads((Path(__file__).parent/"Translations.json").read_text(encoding="utf-8"))

    def __call__(self, key, *args):
        value = self.catalog.get(key, {}).get(self.language, key)
        # Swift's %@ placeholder corresponds to Python's %s; ignore locale-specific C format lengths.
        value = value.replace("%@", "%s")
        return value % args if args else value
