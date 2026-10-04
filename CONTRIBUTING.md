# Contributing to Usage Sentinel

Thanks for helping people understand their AI usage. Useful contributions include documented provider adapters, reproducible bug reports, translations, accessibility improvements and platform validation.

1. Open an issue explaining the behavior or official source you want to support.
2. Fork the repository and create a branch.
3. Keep usage parsing, event classification and UI changes separate. Never include real account snapshots or credentials in fixtures.
4. Run `python3 Scripts/check_localization.py` and `swift test` for Swift changes. Run `PYTHONPATH=Portable python3 -m unittest discover -s Portable/tests -v` for portable changes.
5. Include evidence for meaningful behavior changes, particularly reset detection, notification deduplication and backwards-compatible settings.
6. Open a pull request explaining the problem, behavior and validation.

All five app languages must contain any new interface keys. Public-source title/snippet text stays in the source's original language. Use semantic UI colors. False positives must remain distinguishable from official confirmation.

Do not introduce cookie scraping, undocumented authenticated endpoints, credential exports, inference calls merely to probe quota, telemetry, or a hosted account-data backend. Public signal monitoring may fail independently and must not disable account usage.

The default notification confidence is 25%. Community evidence must never produce an official-confirmation label. Scheduled resets are quiet; unexplained personal increases are account evidence, not proof of a global reset.
