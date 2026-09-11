# AGENTS.md — SMS-AnythingLLM-defaults (Model Router seeder)

Hard constraints for any agent or contributor working in this repo:

- **Audience**: non-technical office users at an architecture practice. Everything must
  "just work" — no prompts beyond what the installer already asks.
- **Idempotent**: installer and seed step must be rerunable safely. Seed is guarded by a
  `system_settings` row `_seeded_by_sms_toolkit`.
- **Quiet in silence mode**: all steps must run clean under Inno `/VERYSILENT` (and
  `/SILENT`) — no message boxes, no stdout dialogs surfaced to users.
- **No elevation**: per-user install only (`{userpf}` / `{localappdata}` targets). Never
  write HKLM/HKCU-write-requiring code, never require admin.
- **Secrets never committed**: API keys flow at runtime via the suite-provided
  `apikeys.json` path. Never log or print key values. `apikeys.json` is gitignored.
- **Never fail the install**: seed problems (missing db, table drift in future
  AnythingLLM versions) are reported via `install-status.json` and the step exits 0.
- **No external deps**: seeder runs on bundled/suite-provided portable Node v22 with
  `node:sqlite` (`--experimental-sqlite`). No npm packages.
- **Self-contained utility**: this repo owns everything it needs. The parent suite
  ("SMS Toolkit") never imports this code — it only stages the built installer binary,
  verified by SHA-256, and supplies `apikeys.json` path at runtime.
- **Testing location**: run builds/tests only on the dedicated test workstation. Never
  execute seeding or AnythingLLM operations on a dev machine against a live db.

Contract (from the suite): publish conventional installer
`Setup-SMS-AnythingLLM-Defaults-vX.Y.Z.exe` to GitHub Releases, silent flags supported
(Inno `/VERYSILENT`), own ARP entry (standard Inno), idempotent, non-admin.
