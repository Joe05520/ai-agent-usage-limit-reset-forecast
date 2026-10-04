# Verified update mechanism

1.5 checks once per 24 hours while the app is awake, or immediately with **Check for Updates**. Users can disable checks or choose whether preview releases are included. Checks go to this project's GitHub Pages; no account identifier is sent.

`updates/stable.json` and `updates/preview.json` have detached Ed25519 signatures. The app contains only the public key in `Resources/ServiceConfig.json`. The publisher's seed stays in macOS Keychain and GitHub Actions Secrets. A changed manifest, invalid signature, wrong channel, malformed version, foreign release/asset URL, missing platform, oversized package, hash mismatch or wrong byte count is rejected. SemVer comparisons prevent advertising an older/equal version as an update.

**Download Verified Update** follows HTTPS redirects only to known GitHub asset hosts, checks the signed SHA-256 and length, then writes a file in Downloads without overwriting an existing file. The app does not execute downloaded code or silently replace its running bundle. On macOS it reveals the verified package in Finder; portable clients show its path.

## Install safely

- Quit Usage Sentinel. Extract the verified package.
- macOS: replace the existing `.app` in the same Applications location and reopen. The bundle identifier is unchanged. History/settings remain in `~/Library/Application Support/OpenAIUsageSentinel`.
- Windows/Linux: replace the **whole extracted application folder**, retaining its runtime/shared libraries; reopen. Data stays in LocalAppData / XDG application-data directories.
- Keep the old application bundle/folder until the new version launches if you want a simple rollback. Never delete the application-data directory as part of an update.

The current macOS release is ad-hoc signed, with hardened runtime, and is not Apple-notarized. Windows has no publisher Authenticode certificate. The detached update signature authenticates the project's publisher key; it does not replace Apple notarization or OS trust prompts. No paid signing service has been purchased.

## Publisher workflow

Build and test must pass on trusted `main`; release publication rejects PR/fork build artifacts and validates the workflow path, branch, event, repository, source SHA and exact package names. Actions are pinned to commits. Manual **Publish verified release** takes a passing run ID, matching version and stable/preview channel. It hashes the three actual CI artifacts, signs the channel manifest, publishes the Release and deploys the channel through Pages.

`Scripts/configure_update_signing.swift` initializes/reuses the signing seed in Keychain and sends it to GitHub Actions Secrets through stdin; never export it as a source file. Key rotation requires shipping a new trusted public key (or an explicitly designed transition); do not silently regenerate the key for existing users. Maintain publisher account security: a compromised signing secret or repository can still publish malicious updates. Disable distribution, rotate credentials and document recovery if that happens.

**1.4 migration:** existing 1.4 apps have no built-in updater; users install 1.5 once from the Release page. Future 1.5+ versions can use this verified download mechanism. A missing stable channel means no stable release yet, not an invented release date.
