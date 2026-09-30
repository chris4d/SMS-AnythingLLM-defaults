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
_(fill in after the workstation run)_

### Where the key materializes
- [ ] db table: `?` (which table/row/key)
- [ ] env file: `?` (which var)
- [ ] neither → key lives outside storage (keychain/os credential store)

### Does it survive app restart?
- [ ] yes / [ ] no — evidence: `?`

### Notable snapshots
- `before`: files present `?`
- `after`: new files `?`, mtimes changed `?`

## Disposition
<!-- After findings: which channel the seeder should write to for v0.2.0,
     or "backstop-only" if no injection channel is reliable. -->
