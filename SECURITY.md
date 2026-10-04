# Security and privacy

Usage Sentinel never uploads raw account history or credentials. Account snapshots, history, settings and notification bookkeeping stay on the device. Optional daily aggregate analytics is disabled by default and requires explicit consent; coarse quota bands require separate consent. Public-source requests carry no account history or credentials. Sentinel invokes the official Codex executable, which manages its own authentication. It does not read browser cookies or vendor authentication files.

Local JSON exports must contain quota fields only. Never put tokens, cookies or session credentials in an export or GitHub issue. The Claude bridge reads the official status-line payload from stdin and writes only quota percentages, reset times, timestamp and an optional non-secret profile label. It does not persist conversation/session/transcript fields.

For a suspected vulnerability, use this repository's private vulnerability reporting if available. Otherwise contact the repository owner through their GitHub profile without including secrets or exploit details in a public issue. Routine source outages or missing vendor usage APIs belong in normal issues.

Downloads currently have no paid platform code-signing certificate or Apple notarization. Check the release hashes, review the source and follow your operating system's explicit approval flow. Never disable Gatekeeper, SmartScreen or system-wide security settings.

1.5 introduces explicit-consent aggregate analytics and signature-verified updates. See [reviewed controls and limits](docs/SECURITY_REVIEW.md), [data schema](docs/ANALYTICS.md), and [update trust model](docs/UPDATES.md). This is a source review and test record, not an independent penetration-test certification. Never enable a paid service without owner approval.
