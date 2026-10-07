"""Isolated public-source requests with bounded reads, retry/backoff and cached metadata."""
from email.utils import parsedate_to_datetime
import json
import re
import time
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from .core import classify, epoch

CATALOG = {
    "OpenAI Status": ("https://status.openai.com/history.rss", "rss", True),
    "OpenAI News": ("https://openai.com/news/rss.xml", "rss", True),
    "Codex Releases": ("https://github.com/openai/codex/releases.atom", "rss", True),
    "GitHub": ("https://api.github.com/repos/openai/codex/issues?state=all&sort=created&direction=desc&per_page=50", "github", False),
    "Reddit": ("https://www.reddit.com/r/codex/new.json?limit=50", "reddit", False),
    "Codex Resets · 75%": ("https://codex-resets.com/api/v1/status", "reset_status", False),
    "Tibo radar · 85%": ("https://codex-reset.com/api/feed", "radar", False),
    "Hacker News": ("https://hn.algolia.com/api/v1/search_by_date?query=codex%20reset&tags=story&hitsPerPage=30", "hn", False),
}


def text(html):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", " ", html or "")).strip()[:1000]


def fetch(name, cache=None):
    now = time.time(); cache = cache or {}
    if cache.get("retry", 0) > now:
        return cache, cache.get("signals", []), "Backoff · cached metadata"
    url, kind, official = CATALOG[name]
    headers = {"User-Agent": "UsageSentinel/1.4.0 (+https://github.com/Joe05520/ai-agent-usage-limit-reset-forecast)", "Accept": "application/json, application/xml, text/xml"}
    if cache.get("etag"): headers["If-None-Match"] = cache["etag"]
    if cache.get("modified"): headers["If-Modified-Since"] = cache["modified"]
    started = time.monotonic()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=15) as response:
            body = response.read(2_000_001)
            if len(body) > 2_000_000: raise ValueError("Response exceeds 2 MB")
            etag, modified = response.headers.get("ETag"), response.headers.get("Last-Modified")
        sources = []
        def source(title, link, stamp, snippet, author=None):
            try: published = epoch(stamp) if stamp else None
            except (ValueError, TypeError):
                try: published = parsedate_to_datetime(stamp).timestamp()
                except (ValueError, TypeError): published = None
            if link.startswith("https://"):
                sources.append(dict(title=text(title), url=link, platform=name if official else name, publishedAt=published, fetchedAt=now, author=author, snippet=text(snippet), official=official))
        if kind in ("reset_status", "radar"):
            from .reset_watch import parse_feed
            sources = [s["source"] for s in parse_feed(json.loads(body),kind,now)]
        elif kind == "github":
            for row in json.loads(body):
                if "pull_request" in row: continue
                source(row["title"], row["html_url"], row.get("created_at"), row.get("body"), (row.get("user") or {}).get("login"))
        elif kind == "reddit":
            for child in json.loads(body)["data"]["children"]:
                row = child["data"]; source(row["title"], "https://www.reddit.com"+row["permalink"], row["created_utc"], row.get("selftext"), row.get("author"))
        elif kind == "hn":
            for row in json.loads(body)["hits"]:
                source(row.get("title", ""), "https://news.ycombinator.com/item?id="+row["objectID"], row["created_at"], row.get("story_text"), row.get("author"))
        else:
            root = ET.fromstring(body); atom = "{http://www.w3.org/2005/Atom}"
            for row in root.findall(".//item")+root.findall(atom+"entry"):
                def value(key): return row.findtext(key) or row.findtext(atom+key) or ""
                link = value("link")
                if not link:
                    links = row.findall(atom+"link"); link = next((l.attrib.get("href", "") for l in links if l.attrib.get("rel", "alternate") == "alternate"), "")
                source(value("title"), link, value("pubDate") or value("published") or value("updated"), value("description") or value("content") or value("summary"))
        signals = [s for s in (classify(v) for v in sources) if s]
        result = dict(signals=signals, fetched=now, last_success=now, failures=0, retry=0, etag=etag, modified=modified, latency=round((time.monotonic()-started)*1000))
        return result, signals, "OK"
    except urllib.error.HTTPError as error:
        if error.code == 304:
            cache.update(last_success=now, retry=0); return cache, cache.get("signals", []), "OK · unchanged"
        retry_after = error.headers.get("Retry-After", "")
        try: retry = min(86400, max(60, float(retry_after)))
        except ValueError:
            try: retry = min(86400, max(60, parsedate_to_datetime(retry_after).timestamp()-now))
            except (TypeError, ValueError): retry = None
        label = "Rate limited" if error.code in (403, 429) else f"HTTP {error.code}"
    except Exception as error:
        retry = None; label = type(error).__name__
    failures = cache.get("failures", 0)+1
    cache.update(failures=failures, retry=now+(retry or min(3600, 60*2**min(failures, 6))))
    # Seven-day cache retention; old items cannot create current events.
    signals = cache.get("signals", []) if now-cache.get("fetched", 0) < 7*86400 else []
    return cache, signals, label
