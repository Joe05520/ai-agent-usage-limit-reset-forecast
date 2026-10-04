# Security review — 2026-10-04

This is a repository review, dependency scan and adversarial test record. It is **not** a guarantee of zero vulnerabilities or an independent penetration-test report.

## Reviewed and repaired

| Surface | Controls / changes |
|---|---|
| Local Codex process | No shell interpolation, prompt or auth-file parsing. Known paths or explicit user-selected executable, fixed app-server messages, 25-second deadline and 2 MB bound. A user-selected executable is still executable code; select the official binary only. |
| Usage exports | Explicit local file selection, regular-file check, bounded size, unique bucket IDs, finite percentages, boolean numeric rejection, valid timestamps and bounded positive durations. Missing windows remain unavailable. |
| Native HTTP | HTTPS and credential-free URLs; streamed byte cap before full allocation; cookie/credential storage off; bounded resource time; redirects restricted to trusted source/CDN hosts. |
| Event source links | SwiftUI and Qt refuse file/javascript/plain-HTTP links. Public post text stays escaped/plain; website charts use textContent, never remote HTML. |
| Local storage | macOS/Unix SQLite owner-only permissions and application directory. Login scope is per user. Quota history remains local by default. SQLite is not separately encrypted; OS/FileVault protection and local account permissions apply. |
| Analytics ingestion | Strict field allowlist, explicit consent flag, coarse bands only, UUIDv4, today/yesterday, 2 KB stream cap, trusted edge country, HMAC IDs, SQL parameters, per-day idempotence, rate limits, 35-day retention. No vendor credentials or account identifier accepted. |
| Administrator | High-entropy password in Keychain/Workers secrets; constant-time comparison, rate limit, signed short-lived Secure/HttpOnly/SameSite cookies, same-origin login/logout, no-store responses and nonce CSP. Optional Access RSA JWT verification also supported. No public individual-row endpoint. |
| Public analytics | At least 10 distinct anonymous monthly identities per category; no suppressed residual totals; short cache; clear measurement/selection limits. This is disclosure reduction, not formal differential privacy or proof of distinct humans. |
| Updates | Embedded Ed25519 public key; exact signed data; fixed repository/asset paths; valid versions/channel/platforms; declared size cap; SHA-256+length verification; non-overwriting writes; no downloaded-code execution or silent replacement. |
| Release workflow | Commit-pinned actions, trusted main workflow/event/repository/source checks, exact CI artifacts; signature seed only in designated signing step; public manifests contain no secret. |
| macOS signing | Hardened runtime enabled; ad-hoc codesign verified. App sandbox remains disabled because the official CLI must run externally. Not Developer ID/notarized. |
| Dependencies | Initial cryptography 46.0.3 scan found advisories; replaced with 50.0.2. Final pip-audit of pinned requirements and npm audit of Backend found no known advisories at review time. Scanners do not prove the absence of embedded Qt or future vulnerabilities. |

## Verification

- Native signed-manifest tests reject modified bytes, wrong channel, foreign assets, malformed/non-ASCII versions and unsafe URL schemes.
- Consent/payload tests prove disabled analytics produces no report and exact account information is excluded; quota requires separate consent.
- Portable tests cover signature tampering, same-repository assets, redirects, versions and disabled analytics network calls.
- Backend tests cover invalid/extra/private fields, oversize streams, distinct-contributor suppression, forged JWT/header, issuer/audience/expiry, password comparison, signed cookie tampering and CSRF origin checks.
- Real local Worker+D1 smoke checks insert/dedup, private-field rejection, public suppression, authenticated admin and deletion. Test fixtures are local and removed; production statistics contain no manufactured reports.
- CI repeats native/portable tests, packaged portable startup and the local Worker/D1 integration.

## Remaining trust boundaries

Publisher GitHub/signing-key compromise, a malicious selected CLI, OS credential-store compromise or another process with the same local user access can still defeat these protections. Report ingestion cannot prove authentic AI account usage; malicious clients can fabricate data. Cloudflare edge rate limits are local/eventually consistent, not an exact worldwide cap. Free quotas can be exhausted; collection must fail or pause rather than silently upgrade. Request logging is disabled intentionally, while platform operational metadata may still exist under Cloudflare's policies. Core quota monitoring is independent of backend availability.

No paid plan, domain, signing certificate or security add-on was enabled. Paid changes require the owner's approval.
