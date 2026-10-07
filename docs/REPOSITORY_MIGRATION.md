# Repository rename and update migration

The main repository is now `Joe05520/ai-agent-usage-limit-reset-forecast`. The main Pages site is `https://joe05520.github.io/ai-agent-usage-limit-reset-forecast/`.

GitHub redirects the old repository alias, preserving clone, release and issue links. We do not reuse `usage-sentinel` as a repository name. GitHub project Pages URLs do not receive this repository redirect.

A separate static owner Pages site, `Joe05520/Joe05520.github.io`, therefore serves the former `/usage-sentinel/` paths. Website pages link to the new site, while `/usage-sentinel/updates/preview.json` and its detached signature contain the 1.8.1 migration update. The bridge is frozen at that version. Preview releases stay on the preview channel; no preview is silently promoted to stable.

The legacy manifest uses the original exact GitHub URL spelling expected by old binaries; GitHub redirects downloads to the renamed repository. It has the same existing Ed25519 signing key and verified package hashes. Version 1.8.1 uses the new Pages update endpoint and strictly validates the new repository asset URLs.

The rename does not change app bundle IDs, local databases, login registration, Keychain services, analytics consent or the analytics Worker/D1 identity. The compatibility site is static and contains no vendor credentials or private account data.
