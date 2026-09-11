# SMS-AnythingLLM-defaults

Self-contained seeder utility for AnythingLLM Desktop (1.16.1): installs the office
baseline **Model Router** ("Baseline Routing") plus provider defaults into the AnythingLLM
`anythingllm.db` SQLite store. Part of the SMS Toolkit suite of per-user, non-admin,
no-prompt installers for an architecture practice.

## What it does
1. Staged by its Inno installer (`Setup-SMS-AnythingLLM-Defaults-vX.Y.Z.exe`, `main` branch).
2. Locates `%APPDATA%\anythingllm-desktop\storage\anythingllm.db`.
3. If the db exists: applies `seed/model-router-seed.json` (router + 2 literal rules,
   non-secret `.env` defaults, skips onboarding) and writes idempotency marker
   `system_settings._seeded_by_sms_toolkit`.
4. If the db doesn't exist yet: writes `{app}\pending-seed.json` and repoints the
   start-menu icon to `shims\run-anythingllm.cmd`, which seeds on first launch
   (waits up to 120s for the db).
5. Never fails the install or blocks the app: table drift / missing db / missing tables
   are recorded in `install-status.json`; the step still exits 0 and stays quiet under
   `/VERYSILENT`.
6. API keys flow at runtime via a suite-provided `apikeys.json` path; key values are
   never logged or committed.

## Layout
- `seed/model-router-seed.json` — literal seed data (no secrets), editable without code changes. Rows captured from a live AnythingLLM 1.16.1 install; swappable in future releases.
- `installer/sms-anythingllm-defaults.iss` — Inno Setup script (per-user, ARP entry, silent-safe).
- `scripts/build.ps1` — compiles the installer into `dist/`.
- `scripts/seed-model-router.ps1` — installer [Run] step. Composes payload from seed JSON + `apikeys.json`, invokes `seed-registry.js`.
- `scripts/seed-registry.js` — upsert logic on bundled/suite-provided portable Node v22 (`node --experimental-sqlite`, no npm deps).
- `scripts/verify.ps1` — readonly SQLite checks for the test workstation.
- `shims/run-anythingllm.cmd` — first-launch seed shim.
- `QUICKSTART.md` — test-station procedure + in-app key backstop.

## Integration (suite contract)
Suite does not import this code: it stages the built installer binary from GitHub
Releases, verified by SHA-256, and at runtime supplies the `apikeys.json` path (same
single passthrough file the omnibus suite installer already writes). Everything here is
flat, self-contained, Node-only, and rerunable.

## Versioning / releases
- Conventional releases: `vX.Y.Z`, artifact `Setup-SMS-AnythingLLM-Defaults-vX.Y.Z.exe` published to GitHub Releases with SHA-256 digest in the release notes.
- First cut: `v0.1.0`.
