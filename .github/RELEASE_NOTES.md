Usage Sentinel 1.5.0 adds consent-based analytics, a private administrator dashboard, and signed update downloads.

- Optional analytics is OFF by default; coarse quota bands need separate consent. Monthly rotating IDs live in OS credential storage. No vendor account ID, token, cookie, prompt, exact quota or reset time is collected.
- Country statistics describe consenting download clicks. GitHub asset download counts are a separate metric. Public categories require 10 anonymous contributors and expose no individual rows.
- Check for updates daily or manually. Both stable and preview channels require an Ed25519 signature. Downloads must match signed SHA-256, size, and the exact repository asset URL. Installation is manual: quit the existing app, replace its bundle/folder, reopen. Existing account history remains in the OS application-data directory.
- Security hardening: bounded HTTP reads, HTTPS redirects restricted to trusted hosts, external-link scheme checks, hardened macOS runtime, repaired numeric parser edge cases, pinned CI actions, trusted main-branch release artifacts and dependency vulnerability checks.

macOS is a SwiftUI/MenuBarExtra universal build for macOS 14+. Windows/Linux are Qt beta ports; their desktop notifications and login behavior still need broader real-device validation. macOS is ad-hoc signed and not Apple-notarized; Windows is unsigned. No paid certificate or service has been purchased.

SHA256SUMS.txt identifies the exact CI-built packages. Signing seeds and administrator credentials are excluded from source. See docs/ANALYTICS.md, docs/UPDATES.md and docs/SECURITY_REVIEW.md.
