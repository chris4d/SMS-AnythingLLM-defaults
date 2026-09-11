# Transcript / Handoff — AnythingLLM Model Router seed (SMS Toolkit suite)

> Handoff note: created 2026-09-11 in workdir `C:\dev\SMS-AI-toolkit` so this session can be
> restarted in the NEW dedicated repo that will host this utility. Nothing else was modified.

## Context
- Repo in that session (`C:\dev\SMS-AI-toolkit`): suite/repackage installer for AnythingLLM Desktop
  (NSIS `/S`) + mcp-servers-for-revit plugin (fork, ajv-patched, pinned by tag) + bundled portable
  node + local MCP server for an architecture practice. See its AGENTS.md for hard constraints
  (non-technical users, idempotent, quiet on /SILENT, no admin/registries, keys never committed).
- Decision made: each utility gets its own GitHub repo; the suite will merge utilities via
  `apps.json` + [Components]/[Run] entries. The model-router seeder is the utility designed below.

## User-confirmed decisions
1. API keys: per-user, distributed out-of-band via email; installer queries user
   (installer already has API-key wizard page writing `{app}\apikeys.json` — extend it).
2. Seed router = the live "Baseline Routing" router + its 2 rules from my machine (swappable later).
3. Seed during installer run (one user per machine in this office).
4. Future omnibus "SMS Toolkit" installer will query the user and supply API keys — keep a
   single passthrough surface (`apikeys.json`) so the seeder only consumes data, never UI/code.
5. This utility must move to its own repo; the suite repo is only the parent for planning.

## Plan-mode note
Session was in plan mode; user then allowed only this transcript to be written before moving
this work to the new dedicated repo.

## Design (approved, pending implementation in the new repo)

### Key research facts (verified on live install, AnythingLLM Desktop 1.16.1)
- AnythingLLM install: `%LOCALAPPDATA%\Programs\AnythingLLM\AnythingLLM.exe` (NSIS installer).
- Storage/settings: `%APPDATA%\anythingllm-desktop\storage\anythingllm.db` (SQLite).
  `storage\.env` is regenerated each boot ("Auto-dump ENV" header) — db is canonical authority.
- Model Router is a FIRST-CLASS feature in 1.16.1, plain SQLite tables:
  - `model_routers`: id, name, description, fallback_provider, fallback_model,
    cooldown_seconds, created_by, timestamps
  - `model_router_rules`: id, router_id (FK, cascade), enabled, priority, type ('calculated'),
    title, description, condition_logic (AND/OR), conditions (JSON text: array of
    `{property, comparator, value}` where property = `promptContent`), route_provider, route_model
- Live "Baseline Routing" rows captured from this machine (seed source):
  - Router: fallback_provider=`generic-openai`, fallback_model=`zai-org/GLM-5.3-Flash`,
    cooldown 300s
  - Rule 1 (priority 1): promptContent contains "confidential, private, secret" →
    route_provider `anythingllm_ollama`, route_model `qwen3-vl:4b-instruct`
  - Rule 2 (priority 2): promptContent contains "code" → generic-openai,
    model `deepseek-ai/DeepSeek-V4-Flash`
- Provider baselines + API keys live in `.env`: LLM_PROVIDER, GENERIC_OPEN_AI_BASE_PATH,
  GENERIC_OPEN_AI_MODEL_PREF, GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT, GENERIC_OPEN_AI_API_KEY,
  GENERIC_OPEN_AI_MAX_TOKENS, MISTRAL_API_KEY, EMBEDDING_ENGINE, VECTOR_DB, etc.
- No built-in settings export/import in the desktop app; db is created on FIRST app launch.
  Hence: seed at installer run; on fresh machines where no db exists yet, seed on first launch.
- Also useful: `system_settings` table (list of entries): telemetry_id, onboarding_complete,
  agent skills whitelists, etc. Setting `onboarding_complete=true` skips the first-run wizard.
- Notes on existing machine rows: there was a second personal router ("Personal", Mistral) —
  do NOT seed that; the suite seed only "Baseline Routing".

### Implementation plan
A. **Seed data file** — `installer/staged/seed/model-router-seed.json` (no secrets):
   router + rules (as above), `envDefaults` (GENERIC_OPEN_AI_* non-secret, LLM_PROVIDER),
   `settings` (onboarding_complete). Editable w/o code changes; swappable later.
B. **Key collection** — extend the existing Inno wizard page "LLM Provider API Keys"
   (currently fields Gemini + DeepInfra, writes `{app}\apikeys.json`) with a third field:
   office router API key (generic-openai). Extend `apikeys.json` with `routerBaseUrl`,
   `genericOpenAiKey`. Omnibus installer later supplies this same file.
C. **New step** `step-seed-model-router.ps1` + `seed-registry.js` (runs on portable node v22 —
   `node --experimental-sqlite` for node:sqlite; avoid new deps):
   1) locate `%APPDATA%\anythingllm-desktop\storage`
   2) compose payload from staged JSON + apikeys.json
   3) if `anythingllm.db` exists → write `.env` defaults + upsert db rows now
   4) if not → write `{app}\pending-seed.json` and swap the start-menu launcher target to
      `{app}\run-anythingllm.cmd`, which on first launch waits (≤120s) for the db to appear,
      then runs the same seed, then flips a done marker.
   5) Idempotency marker: `system_settings` row `_seeded_by_sms_toolkit` → skip if present.
   6) Never log key values; exit 0; report via install-status.json-style file.
D. **Wiring** in `installer/sms-ai-toolkit.iss`: [Files] stage seed + shims; [Run] new step
   after step 3 (`step-anythingllm-mcp.ps1`); [Icons] points at the cmd shim when pending.
E. **Verification**: build (`.\scripts\build.ps1 -ForkPath C:\dev\mcp-servers-for-revit`),
   install on a clean profile, launch once via shim, seed applies; verify rows via readonly
   SQLite AND in app UI; re-run installer → seed skipped; add checks to `step-verify.ps1`;
   document in-app key entry backstop in QUICKSTART.md.

### Risks to verify during implementation
- Does a hand-crafted `.env` survive the app's first boot / re-dump? If not, provider settings
  (incl keys) must be seeded in db or entered in-app; QUICKSTART documents the backstop.
- Table-name drift in future AnythingLLM versions: seeder should detect missing tables and
   report in install-status.json, never block install. `/SILENT` must remain quiet.
- Key page is skipped in silence mode — keys flow via `apikeys.json` or later in-app entry.
