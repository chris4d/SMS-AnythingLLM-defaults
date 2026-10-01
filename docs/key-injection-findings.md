# Key-injection findings (Option B study)

Purpose: determine where AnythingLLM Desktop 1.16.1 *actually* persists a provider
API key entered via the app UI, before implementing injection in the seeder.
Background (see AGENTS.md root transcript): `storage\.env` is regenerated each boot;
"db is canonical authority" per research on the live install — which channel is
responsible for keys is the open question.

## Data collection procedure (test workstation only)
1. Ensure AnythingLLM is not running. Run:
   ```powershell
   .\scripts\capture-key-storage.ps1 -Label before
   ```
2. Launch AnythingLLM, enter OpenRouter key via UI (**LLM Provider → OpenAI-compatible → paste key**; first-run wizard also works), then close the app cleanly.
3. Run again:
   ```powershell
   .\scripts\capture-key-storage.ps1 -Label after
   ```
4. Diff `logs\keystorage-before.json` vs `logs\keystorage-after.json` (files are
   gitignored; no key material inside — values that look key-like are redacted to
   `{len, sha256-prefix}` for matching).

## Findings
_(partial — from a dev machine run on 2026-09-30 against a live install (AnythingLLM Desktop 1.16.1) that already had an OpenRouter key entered; a fresh pre/post capture still required on the test workstation)_

### What we can already see (dev machine, `capture-key-storage` snapshot)
- `storage\.env` currently holds `OPENROUTER_API_KEY=sk-or-v1-...` and `OPENROUTER_MODEL_PREF=z-ai/glm-5.3-flash`, alongside legacy `GENERIC_OPEN_AI_API_KEY` (deepinfra), `MISTRAL_API_KEY`, `SIG_KEY`, `SIG_SALT` in the *same file*.
- `system_settings` db rows contain **no provider API keys** (the lone flagged value was `telemetry_id` — a UUID false-positive from the shape heuristic; all provider keys absent from that table).
- db tables: none of the 41 tables contain a recognizable provider-key value beloning to an OpenRouter/DeepInfra/Mistral key (the redaction hits in `_prisma_migrations`/`workspace_*`/`meeting_*` tables are id/record-shape false-positives, not key material).
- So: at boot, the app appears to **serialize `.env` from somewhere other than the db**, yet the OPENROUTER_API_KEY is present in `.env` today and the app has been restarted multiple times — suggesting either (a) `.env` actually *is* sticky across boots (overwriting only select vars via the auto-dump), or (b) the app lifts provider keys back into `.env` from some other persistence (e.g., its own electron app store / secure storage).

### Still unresolved (test-station capture required)
- Does `.env` survive a fresh AnythingLLM restart untouched? (need `before`/`after` snapshots on a workstation whose key was just entered in-app)
- If `.env` is regenerated, what intermediate/binary/auth-store file changed? (storage-file mtime diff on the two captures)
- if neither: desktop may store provider keys in a node.js os-level key ring / Chrome profile (`comkey\ipc-priv.pem` seen in the DB listing is suspicious but is MolChat Electron IPC key material, so likely irrelevant)

### Notable snapshots
- `before` (needed from test station) - `after` (same)

## Disposition (final, Phase 1 complete)
Injection channel = `storage\.env` (merge-only, keys survive boots; the app preserved
pre-existing `OPENROUTER_*` vars across both a settings-change rewrite and a full
restart). Implemented in `seed-registry.js` for v0.2.0. In the pending-first-launch
flow the seeder closes the app before merging `.env` and relaunches it after, so the
app cannot rewrite the file over the injected key. The db is never used for key
material. Status messages report presence/length only.