# QUICKSTART — SMS-AnythingLLM-defaults

## Build (dev machine)
```powershell
.\scripts\build.ps1 -Version 0.1.0
```
Produces `dist\Setup-SMS-AnythingLLM-Defaults-v0.1.0.exe`. No install/seed runs on the
dev machine — see AGENTS.md.

## Test (dedicated workstation only, clean user profile)
1. Ensure AnythingLLM Desktop is **not** running.
2. Run installer interactively (or with `/VERYSILENT` for the quiet path; push
   `apikeys.json` path the way the suite does — see `scripts/seed-model-router.ps1 -ApiKeysPath`).
3. Launch AnythingLLM once via the start-menu icon.
   - If db already existed at install time, seed already applied.
   - Else the `run-anythingllm.cmd` shim waits for the db, seeds, sets a done marker.
4. Verify:
   - `scripts\verify.ps1` (readonly SQLite): expect 1 "Baseline Routing" router row with
     2 enabled rules, `onboarding_complete=true`, `_seeded_by_sms_toolkit=true`,
     no core/personal/Mistral routers created beyond the baseline.
   - In the app UI: Model Router page shows "Baseline Routing" with both rules.
5. Rerun installer → seed must be skipped (marker present), `install-status.json` shows `skipped`.
6. Confirm `.env` was rewritten by AnythingLLM's next boot and check whether the
   provider/key entries survived — if not, keys must instead be entered in-app (backstop
   documented below).

## In-app key backstop
If keys didn't make it into `.env` (or the model router shows missing provider config),
the user can paste the provider key once in AnythingLLM under **LLM Provider → Generic
OpenAI** keys page. Nothing else in the seed depends on this; document any change to
key flow here when it's resolved during MVP testing.
