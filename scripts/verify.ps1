# Readonly verification: confirm SMS baseline seed landed in AnythingLLM db.
# No writes to the db. Exit 0 = pass, 1 = fail. Test workstation only — never
# point this at a live db off the dedicated workstation (AGENTS.md).
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$AppDir = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
$StorageDir = Join-Path $Env:APPDATA 'anythingllm-desktop\storage'
$Db = Join-Path $StorageDir 'anythingllm.db'
$Node = Join-Path $AppDir 'bin\node.exe'
if (-not (Test-Path $Node)) { $Node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source }

$fail = @()
if (-not (Test-Path $Db)) { $fail += 'db-missing' }
if ($fail) { Write-Host "FAIL: $($fail -join ', ')"; exit 1 }

$js = @'
const { DatabaseSync } = require("node:sqlite");
const db = new DatabaseSync(process.argv[2], { readOnly: true });
const router = db.prepare("SELECT * FROM model_routers WHERE name=?").get("Baseline Routing");
const rules = router ? db.prepare("SELECT * FROM model_router_rules WHERE router_id=?").all(String(router.id || router.ID)) : [];
const marker = db.prepare("SELECT value FROM system_settings WHERE key='_seeded_by_sms_toolkit'").get();
const onboarding = db.prepare("SELECT value FROM system_settings WHERE key='onboarding_complete'").get();
console.log(JSON.stringify({
  router: { found: !!router, fallback: router ? String(router.fallback_provider) + "/" + String(router.fallback_model) : null, cooldown: router ? router.cooldown_seconds : null },
  ruleCount: rules.length,
  rules: rules.map(r => ({ priority: r.priority, enabled: r.enabled, route: String(r.route_provider) + " " + r.route_model, conditions: r.conditions })),
  marker: marker ? marker.value : null,
  onboarding: onboarding ? onboarding.value : null,
  env: (() => {
    const fs = require("fs"), path = require("path");
    const envPath = path.join(path.dirname(process.argv[2]), ".env");
    let text = ""; try { text = fs.readFileSync(envPath, "utf8"); } catch (_) { return { exists: false }; }
    const has = (k) => new RegExp("^" + k + "=(.+)$", "m").test(text) || new RegExp("^" + k + "=.*$", "m").test(text);
    const present = {};
    for (const k of ["LLM_PROVIDER", "GENERIC_OPEN_AI_BASE_PATH", "OPENROUTER_API_KEY", "OPENROUTER_MODEL_PREF"]) {
      const m = new RegExp("^" + k + "=(.*)$", "m").exec(text);
      present[k] = m ? (k === "OPENROUTER_API_KEY" ? "present(len " + m[1].length + ")" : m[1]) : "missing";
    }
    return { exists: true, vars: present };
  })(),
}));
'@
$tmp = Join-Path $env:TEMP 'sms-verify-seed.js'
[System.IO.File]::WriteAllText($tmp, $js)

$nodeArgs = @('--experimental-sqlite', $tmp, $Db)
$out = & $Node $nodeArgs 2>$null
$result = $null
try { $result = $out | ConvertFrom-Json } catch {}

$errors = @()
if ($result) {
  if (-not $result.router.found) { $errors += 'router-row-missing' }
  elseif ($result.router.fallback -ne 'generic-openai/z-ai/glm-5.3-flash') { $errors += 'router-fallback-mismatch' }
  elseif ($result.ruleCount -ne 2) { $errors += "rule-count=$($result.ruleCount)" }
  if (-not $result.marker) { $errors += 'seed-marker-missing' }
  elseif ("$($result.onboarding)" -ne 'true') { $errors += 'onboarding-not-complete' }
  if ($result.env) {
    if (-not $result.env.exists) { $errors += 'env-file-missing' }
    else {
      $v = $result.env.vars
      if ($v.LLM_PROVIDER -ne 'openrouter') { $errors += "llm-provider=$($v.LLM_PROVIDER)" }
      if ($v.'GENERIC_OPEN_AI_BASE_PATH' -ne 'https://openrouter.ai/api/v1') { $errors += "base-path=$($v.'GENERIC_OPEN_AI_BASE_PATH')" }
      if ($v.'OPENROUTER_API_KEY' -eq 'missing') { $errors += 'openrouter-key-missing' }
      elseif ($v.'OPENROUTER_MODEL_PREF' -eq 'missing') { $errors += 'openrouter-model-pref-missing' }
    }
  }
  if (-not $Quiet) {
    $result | ConvertTo-Json -Depth 5
    Write-Host "conditions check:"
    $result.rules | ForEach-Object { Write-Host " - p$($_.priority) $($_.route) :: $($_.conditions)" }
  }
} else {
  $errors += 'query-failed (node/sqlite output empty; check node version / --experimental-sqlite)'
}
Remove-Item $tmp -ErrorAction SilentlyContinue

# Extra: no personal/Mistral routers leaked in from capture.
if (-not $Quiet) { Write-Host "marker=$($result.marker) onboarding=$($result.onboarding) rules=$($result.ruleCount)" }

if ($errors.Count -gt 0) { Write-Host "FAIL: $($errors -join ', ')"; exit 1 }
Write-Host 'OK: seed verified.'
exit 0
