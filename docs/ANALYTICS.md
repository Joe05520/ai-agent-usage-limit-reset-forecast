# Consent-based community analytics

This changes the 1.4 privacy model: account history remains local by default, but 1.5 can send a minimized daily report **only after explicit opt-in**. Coarse quota reporting requires a separate toggle. The website never enables download-country reporting automatically. Core monitoring, reminders and downloads work without analytics.

## Metrics and interpretation

- GitHub asset download counts are queried from the official public releases API hourly. They are neither unique people nor verified completed installations. No geography is available for these counts. The first 100 releases are included; older releases beyond that API page are excluded.
- Country/platform statistics describe the first consented website download click per anonymous identity/day, not all downloads. Country is derived by Cloudflare from the connection IP; VPN/GeoIP errors apply.
- App activity is the daily count **band** of quota-decrease observations between comparable fresh snapshots at most 15 minutes apart. This is a lower bound, not API calls, tokens, prompts, money or total AI usage. Missed observations, percent rounding and long gaps are excluded.
- Optional quota band is the lowest observed remaining allowance across the selected agent's returned windows that UTC day: `0-4`, `5-19`, `20-49`, `50-100`. Unknown/stale observations and non-consenting quota data remain `unknown`. Different providers' quota units are not comparable.
- Reports are sent after the UTC day closes and the app next successfully observes usage. The previous day remains eligible; older queued summaries are dropped, not backfilled. No continuous monitoring or heartbeat server is required.
- Switching between different agents within one UTC day labels that day's mixed activity `custom`.
- Self-selection, self-reported evidence and possible malicious submissions limit representativeness. These statistics must not be presented as worldwide adoption or billing evidence.

## Exact network schema

`POST /v1/report` accepts only:

| Field | Accepted data |
|---|---|
| schema / consent | `1` / `true` |
| client | Random UUIDv4; regenerated monthly; unrelated to vendor account |
| day | UTC date; today or yesterday only |
| kind | `app` or `download` |
| platform / version | macOS/Windows/Linux; three-part app version |
| agent | codex/claude/gemini/grok/custom (app only) |
| quotaBand | unknown/0-4/5-19/20-49/50-100 (app only) |
| activityBand | 0/1-5/6-20/21+ (app only) |
| reminders | Integer stage count 0–5 (app only) |

Unknown fields, account identifiers, exact percentages, IP supplied in the body, tokens and cookies are rejected. Download reports cannot carry app usage fields. The server computes country from trusted `request.cf.country`, HMACs the random identifier with a Worker secret, and stores parameterized SQL. Reports are idempotent per day/identity/kind.

Client identities are stored in macOS Keychain / Windows Credential Vault / Linux Secret Service. No plaintext credential fallback exists. Linux without a working Secret Service cannot opt in. Website identifiers are browser-local and unrelated to App identifiers. Monthly rotation limits longitudinal tracking, but these records are pseudonymous: "anonymous" in the UI does not mean mathematically irreversible anonymization. Cloudflare processes IP and connection information as the hosting provider, and GitHub receives normal download/update connections. No account data is sent to OpenAI by this analytics service.

## Public vs private views

- Public `/public/stats` exposes grouped categories with at least **10 distinct monthly identities** each, never report rows or IDs. There is no residual other/parent total for suppressed app/country cells. A rotating identity is not a verified person; statistical attacks cannot be completely ruled out.
- Public results cache at most one hour. Deletion removes rows immediately; cached aggregates may persist up to one hour. Provider backup/restore retention is controlled by Cloudflare, not an instant physical-erasure guarantee.
- Private `/admin` shows aggregate counts including small groups. It uses a high-entropy password stored in the owner's Keychain and Workers secrets, five attempts/minute, HMAC-signed 30-minute sessions, Secure/HttpOnly/SameSite=Strict cookies, same-origin login/logout and a nonce CSP. It exposes no individual report endpoint.
- Optional Cloudflare Access requires `ACCESS_TEAM` and `ACCESS_AUD`; JWT issuer, audience, algorithm, expiration and RSA signature are verified. A forwarded header alone never authenticates.
- Ingestion is limited to 30 requests/minute per ephemeral hashed IP key at an edge location. This is abuse mitigation, not proof of distinct humans or a globally exact quota.
- D1 reports expire after 35 days, with hourly scheduled cleanup. Worker request logs/traces are intentionally disabled to avoid retaining request metadata; availability is checked via `/health`. Cloudflare's own operational processing remains governed by its policies.

## Owner access and deployment

The deployed service is `https://usage-sentinel-analytics.usage-sentinel-backend.workers.dev`.

Open `/admin` and use the password in macOS Keychain service `UsageSentinel.AnalyticsAdmin`, account `admin-password`. To copy it intentionally:

```sh
swift Scripts/configure_backend_secrets.swift --copy-admin-password
```

Paste into **your own HTTPS admin page only** and clear the clipboard afterward. The key is never committed or printed. To redeploy existing configuration:

```sh
npm ci --prefix Backend --ignore-scripts
npm test --prefix Backend
npm run migrate:remote --prefix Backend
npm run deploy --prefix Backend
```

D1 identifiers and public URL are configuration, not credentials. A contributor must substitute their own account/database before deploying; do not deploy into the owner's account. For local development, `npm run migrate:local --prefix Backend`, `npm run dev --prefix Backend` with local development secret bindings. Production secrets are set through `Scripts/configure_backend_secrets.swift` stdin; no token belongs in `.dev.vars` committed to Git.

**Billing rule:** this deployment uses Workers/D1 Free, no paid plan or domain was enabled. If free capacity is exhausted, fail visibly or pause collection. Do not upgrade or incur charges without the owner's explicit approval. This backend's minimal counters do not constitute consent-management or legal-compliance certification.
