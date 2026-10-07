"""Pure, deterministic usage and signal logic. No credentials or network access."""
import hashlib
import json
import math
import re
import time
import uuid
from datetime import datetime, timezone


def epoch(value):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def thresholds(values):
    return sorted(set(round(v) for v in values if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and 0 <= v <= 99), reverse=True)[:5]


def parse_export(root, agent, now=None):
    now = time.time() if now is None else now
    if root.get("schemaVersion") != 1:
        raise ValueError("Expected schemaVersion 1")
    stamp = epoch(root["timestamp"])
    if stamp > now + 60:
        raise ValueError("Future usage timestamp")
    rows, seen = [], set()
    for row in root["buckets"]:
        value, ident = row["remainingPercent"], row["id"]
        if not ident or ident in seen or isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 100:
            raise ValueError("Invalid or duplicate quota bucket")
        seen.add(ident)
        duration = row.get("windowDurationMins")
        if duration is not None and (isinstance(duration, bool) or not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0):
            raise ValueError("Invalid window duration")
        reset = epoch(row["resetAt"]) if row.get("resetAt") is not None else None
        rows.append(dict(id=f"{agent.lower()}.{ident}", name=row["name"], product=agent, remaining=value, reset=reset, duration=duration, source=f"Local {agent} · {root.get('origin', 'user-provided export')}", updated=stamp))
    if not rows:
        raise ValueError("No quota windows; missing limits are not zero")
    profile = hashlib.sha256(root["profile"].encode()).hexdigest() if root.get("profile") else None
    return dict(timestamp=stamp, buckets=rows, source=rows[0]["source"], account=profile, plan=root.get("plan"), credits=None)


def parse_codex(root, now=None):
    now = time.time() if now is None else now
    limits = root.get("rateLimitsByLimitId") or {"codex": root.get("rateLimits") or {}}
    rows = []
    for lid, limit in sorted(limits.items()):
        for key in ("primary", "secondary"):
            window = limit.get(key) or {}
            used = window.get("usedPercent")
            if isinstance(used, bool) or not isinstance(used, (int, float)) or not math.isfinite(used) or used < 0:
                continue
            mins = window.get("windowDurationMins")
            name = "5-hour" if mins == 300 else "Weekly" if mins == 10080 else f"{mins}-minute" if mins else key.title()
            rows.append(dict(id=f"{lid}.{key}", product="Codex" if lid == "codex" else limit.get("limitName", lid), name=name, remaining=max(0, 100-used), reset=window.get("resetsAt"), duration=mins, source="Codex CLI · account/rateLimits/read", updated=now))
    if not rows:
        raise ValueError("Codex returned no usable quota windows")
    return dict(timestamp=now, buckets=rows, source="Codex CLI app-server", account=hashlib.sha256(root["accountId"].encode()).hexdigest() if root.get("accountId") else None, plan=(root.get("rateLimits") or {}).get("planType"), credits=(root.get("rateLimitResetCredits") or {}).get("availableCount"))


def context(state, row):
    return json.dumps([state["source"], state.get("account"), state.get("plan"), row["id"], row["duration"]])


class ReminderEngine:
    def __init__(self, cycles=None):
        self.cycles = cycles or {}

    def observe(self, state):
        for row in state["buckets"]:
            old = self.cycles.get(row["id"])
            if old and state["timestamp"] <= old["observed"]:
                continue
            same = old and old["context"] == context(state, row)
            moved = same and old.get("reset") is not None and row.get("reset") is not None and abs(old["reset"]-row["reset"]) > 60
            recovery = same and row["remaining"] >= 95 and old["remaining"] <= 75 and row["remaining"]-old["remaining"] >= 20
            cycle = old if same and not moved and not recovery else dict(id=str(uuid.uuid4()), context=context(state, row), delivered=[])
            cycle.update(reset=row["reset"], remaining=row["remaining"], observed=state["timestamp"])
            self.cycles[row["id"]] = cycle

    def pending(self, state, settings, now=None):
        now = time.time() if now is None else now
        if not settings.get("reminders_enabled", True) or settings.get("snooze", 0) > now or not -60 <= now-state["timestamp"] <= 600:
            return []
        values = sorted(thresholds(settings.get("stages", [20, 5])))
        result = []
        for row in state["buckets"]:
            cycle = self.cycles.get(row["id"])
            if not cycle or cycle["context"] != context(state, row) or cycle["observed"] != state["timestamp"] or row["id"] in settings.get("excluded", []):
                continue
            if row["reset"] is not None and row["reset"] <= now:
                continue
            crossed = [v for v in values if row["remaining"] <= v and v not in cycle["delivered"]]
            if crossed:
                result.append(dict(row=row, cycle=cycle["id"], threshold=crossed[0], covered=crossed, critical=len(values)>1 and crossed[0] == values[0], observed=state["timestamp"]))
        return result

    def delivered(self, alert):
        cycle = self.cycles.get(alert["row"]["id"])
        if cycle and cycle["id"] == alert["cycle"]:
            cycle["delivered"] = sorted(set(cycle["delivered"]+alert["covered"]))


def personal_resets(before, after, intent=None):
    if not before or before["source"] != after["source"] or before.get("account") != after.get("account") or before.get("plan") != after.get("plan") or not 0 < after["timestamp"]-before["timestamp"] < 86400:
        return []
    events = []
    for row in after["buckets"]:
        old = next((b for b in before["buckets"] if b["id"] == row["id"] and b["duration"] == row["duration"]), None)
        if not old:
            continue
        jump = row["remaining"]-old["remaining"]
        if jump < 10 and not (jump >= 3 and row["remaining"] >= 99):
            continue
        when = after["timestamp"]
        if old["reset"] is not None and when >= old["reset"]-120:
            kind = "scheduled"
        elif intent and 0 <= when-intent["at"] <= 1800:
            kind = intent["type"]
        elif before.get("credits") is not None and after.get("credits") is not None and after["credits"] < before["credits"]:
            kind = "unknown"
        elif old["reset"] is None:
            kind = "unknown"
        else:
            kind = "accountUnexpected"
        url = "https://code.claude.com/docs/en/statusline" if row["product"] == "Claude" else "https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/commands.md" if row["product"] == "Gemini" else "https://docs.x.ai/developers/rate-limits" if row["product"] == "Grok" else "https://chatgpt.com/codex/settings/usage"
        uncertain = "user-provided" in after["source"] or after["source"].startswith("Local ") and not after.get("account")
        score = (.3 if uncertain else .6) if kind == "accountUnexpected" else .25 if kind == "unknown" else 1
        events.append(dict(id=str(uuid.uuid4()), type=kind, product=row["product"], model=None, at=when, updated=when, confidence=score, own=kind == "accountUnexpected", before=old["remaining"], after=row["remaining"], notified=-1, notified_own=False, own_confidence=score,
            explanation="Observed quota increase; not proof of a global reset. Banked/purchased resets outside Sentinel may be unobservable.", sources=[dict(title=f"{row['name']}: {old['remaining']:g}% → {row['remaining']:g}%", url=url, platform=f"Local {row['product']}", publishedAt=when, fetchedAt=when, author=None, snippet=row["source"], official=False)], timeline=[dict(at=when, score=score)]))
    return events


def level(score):
    return 3 if score >= .9 else 2 if score >= .6 else 1 if score >= .3 else 0


def classify(source):
    from .reset_watch import classify_watch
    watched = classify_watch(source)
    if watched: return watched
    text = (source["title"]+" "+source["snippet"]).lower()
    if any(v in text for v in ("password reset", "factory reset", "not reset", "didn't reset", "when will", "how to reset", "doesn't reset", "no reset", "never reset")):
        return None
    if not any(v in text for v in ("codex", "openai", "chatgpt", "claude", "gemini", "grok", "quota", "usage", "weekly", "allowance")):
        return None
    if not any(v in text for v in ("global reset", "automatic reset", "complimentary reset", "banked reset", "purchased reset", "quota reset", "weekly limit reset", "got reset", "back to 100", "quota refreshed", "usage refreshed", "limits restored", "one-time reset", "free reset", "suddenly 100", "allowance restored")):
        return None
    product = next((v for v in ("Claude", "Gemini", "Grok", "Codex", "ChatGPT") if v.lower() in text), "OpenAI (unspecified)")
    kind = "banked" if "banked reset" in text else "purchased" if "purchased reset" in text else "complimentary" if any(v in text for v in ("complimentary", "one-time", "free reset")) else "automaticGlobal" if source["official"] else "suspectedGlobal"
    return dict(source=source, product=product, model=next((v for v in ("astra", "terra", "sol") if re.search(r"\b"+v+r"\b", text)), None), type=kind)


def dedup(sources):
    result, urls, texts, authors = [], set(), set(), set()
    from .reset_watch import weight
    for s in sorted(sources, key=lambda row: (row.get("official",False),weight(row) or 0), reverse=True):
        normalized = re.sub(r"[^a-z0-9]+", " ", re.sub(r"https?://\S+", "", (s["title"]+" "+s["snippet"]).lower())).strip()
        author = (s["platform"], s.get("author")) if s.get("author") else None
        if s["url"] in urls or normalized in texts or (author and author in authors):
            continue
        urls.add(s["url"]); texts.add(normalized)
        if author: authors.add(author)
        result.append(s)
    return result


def confidence(sources, own, now, own_confidence=.6):
    sources = dedup(sources)
    official = [s for s in sources if s["official"]]
    if official:
        return .95
    reports = [s for s in sources if not s["platform"].startswith("Local ") and not s["official"]]
    from .reset_watch import weight
    watched = [s for s in reports if weight(s) is not None]
    watch_score = max(((weight(s) or 0) * (1 if now-(s.get("publishedAt") or 0) <= 3600 else .9 if now-(s.get("publishedAt") or 0) <= 10800 else .7 if now-(s.get("publishedAt") or 0) <= 43200 else .5 if now-(s.get("publishedAt") or 0) <= 86400 else .25) for s in watched if s.get("expiresAt",float("inf")) > now), default=0)
    reports = [s for s in reports if weight(s) is None]
    score = (own_confidence if own else 0)+watch_score
    for s in reports:
        age = max(0, now-(s.get("publishedAt") or s["fetchedAt"])) / 3600
        decay = 1 if age <= 1 else .9 if age <= 3 else .7 if age <= 12 else .5 if age <= 24 else .25
        score += {"GitHub": .20, "Reddit": .12, "Hacker News": .10}.get(s["platform"], .08)*decay
    authors = {(s["platform"], s["author"]) for s in reports if s.get("author")}
    if len(authors) >= 3: score += .15
    elif len(authors) >= 2: score += .04
    if len(authors) >= 10: score += .20
    return min(.89, score)


def merge(events, signals, personal, now):
    events = json.loads(json.dumps(events))
    from .reset_watch import weight
    completions = [sig["source"]["publishedAt"] for sig in signals if sig["type"] == "suspectedGlobal" and weight(sig["source"]) is not None and sig["source"].get("publishedAt")]
    latest = max(completions,default=0)
    for event in events:
        if event["type"] in ("forecast","poll") and event["product"] == "Codex":
            for source in event["sources"]:
                if (source.get("publishedAt") or float("inf")) < latest: source["expiresAt"] = latest
    for entry in personal:
        match = next((e for e in events if e["product"] == entry["product"] and e["type"] in ("suspectedGlobal", "accountUnexpected") and abs(now-e["updated"]) < 21600), None) if entry["own"] else None
        if match:
            match.update(own=True, own_confidence=entry.get("own_confidence",.6), before=entry["before"], after=entry["after"], updated=now)
            match["sources"] = dedup(match["sources"]+entry["sources"])
            match["confidence"] = max(match["confidence"], confidence(match["sources"], True, now, match.get("own_confidence",.6)))
            match["timeline"].append(dict(at=now, score=match["confidence"]))
        else: events.append(entry)
    from .reset_watch import weight
    for signal in sorted(signals,key=lambda sig: weight(sig["source"]) or 0,reverse=True):
        s = signal["source"]
        when = s.get("publishedAt")
        if signal["type"] in ("forecast","poll") and when is not None and when < latest: continue
        if when is None or now-when > 86400 or when > now+300 or s.get("expiresAt",float("inf")) <= now:
            continue
        prior_event = next((e for e in events if any(v["url"] == s["url"] for v in e["sources"])),None)
        if prior_event:
            prior = next(v for v in prior_event["sources"] if v["url"] == s["url"])
            if (weight(s) or 0) >= (weight(prior) or 0):
                prior_event["sources"] = [s if v["url"] == s["url"] else v for v in prior_event["sources"]]
                if prior_event["type"] in ("forecast","poll") and signal["type"] not in ("forecast","poll"):
                    prior_event.update(type=signal["type"],notified=-1,updated=now)
                prior_event["confidence"] = confidence(prior_event["sources"],prior_event["own"],now,prior_event.get("own_confidence",.6))
            continue
        family = ("suspectedGlobal", "automaticGlobal", "accountUnexpected")
        match = next((e for e in events if e["product"] == signal["product"] and e.get("model") == signal["model"] and (e["type"] == signal["type"] or e["type"] in family and signal["type"] in family) and abs(when-e["at"]) < 21600), None)
        if not match:
            match = dict(id=str(uuid.uuid4()), type=signal["type"], product=signal["product"], model=signal["model"], at=when, updated=when, confidence=0, sources=[], own=False, notified=-1, notified_own=False, timeline=[], explanation="Public evidence. No prediction of a future irregular reset date.")
            events.append(match)
        previous = match["confidence"]
        match["sources"] = dedup(match["sources"]+[s]); match["updated"] = max(match["updated"], when)
        match["confidence"] = confidence(match["sources"], match["own"], now, match.get("own_confidence",.6))
        if s["official"]: match["type"] = signal["type"]
        if match["confidence"] != previous: match["timeline"].append(dict(at=now, score=match["confidence"]))
    return [e for e in events if now-e["at"] < 365*86400]


def should_notify(event, settings, now):
    from .reset_watch import weight
    if not event["own"] and event["sources"] and all(weight(s) is not None for s in event["sources"]) and not any(name in settings.get("sources",["Codex Resets · 75%","Tibo radar · 85%"]) for name in ("Codex Resets · 75%","Tibo radar · 85%")): return False
    if event["type"] in ("forecast","poll") and all(s.get("expiresAt",float("inf")) <= now for s in event["sources"]): return False
    if event["type"] in ("scheduled", "banked", "purchased") or now-event["updated"] > 86400:
        return False
    if event["own"] and not event["notified_own"] and settings.get("notify_personal", True):
        return True
    reliable = settings.get("reliable_alerts", False)
    if (not reliable and not settings.get("notify_signals", True)) or event["confidence"] < (.50 if reliable else settings.get("confidence", .25)):
        return False
    return (reliable and not event["own"] and not event.get("notified_reliable", False)) or level(event["confidence"]) > event["notified"]
