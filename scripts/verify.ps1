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
const router = db.prepare("SELECT * FROM model_routers WHERE name=?").get("SMS Default Routing");
const rules = router ? db.prepare("SELECT * FROM model_router_rules WHERE router_id=?").all(String(router.id || router.ID)) : [];
const sCols = db.prepare(`PRAGMA table_info("system_settings")`).all().map(c => c.name);
const keyCol = sCols.includes("key") ? "key" : "label";
const getSetting = (k) => {
  const row = db.prepare(`SELECT value FROM system_settings WHERE "${keyCol}"=?`).get(k);
  return row ? row.value : null;
};
const titleRe = /^[a-z0-9_]+$/;
let badRules = [];
try {
  for (const r of rules) {
    const conds = JSON.parse(r.conditions);
    if (!Array.isArray(conds)) badRules.push(r.title + ":conditions-not-array");
    if (!titleRe.test(String(r.title || ""))) badRules.push(String(r.title) + ":title-format");
    if (r.created_by !== null && r.created_by !== undefined) badRules.push(String(r.title) + ":created-by-set");
  }
} catch (e) { badRules.push("conditions-parse:" + (e.message || e)); }
console.log(JSON.stringify({
  router: { found: !!router, fallback: router ? String(router.fallback_provider) + "/" + String(router.fallback_model) : null, cooldown: router ? router.cooldown_seconds : null, createdByNull: router ? (router.created_by === null || router.created_by === undefined) : null },
  ruleCount: rules.length,
  rules: rules.map(r => ({ priority: r.priority, enabled: r.enabled, route: String(r.route_provider) + " " + r.route_model, conditions: r.conditions })),
  badRules,
  marker: getSetting("_seeded_by_sms_toolkit"),
  onboarding: getSetting("onboarding_complete"),
  env: (() => {
    const fs = require("fs"), path = require("path");
    const envPath = path.join(path.dirname(process.argv[2]), ".env");
    let text = ""; try { text = fs.readFileSync(envPath, "utf8"); } catch (_) { return { exists: false }; }
    const has = (k) => new RegExp("^" + k + "=(.+)$", "m").test(text) || new RegExp("^" + k + "=.*$", "m").test(text);
    const present = {};
    for (const k of ["LLM_PROVIDER", "GENERIC_OPEN_AI_BASE_PATH", "OPENROUTER_API_KEY", "OPENROUTER_MODEL_PREF"]) {
      const m = new RegExp("^" + k + "=(.*)$", "m").exec(text);
      const unq = (s) => s ? s.replace(/^['"]|['"]$/g, "") : s;
      present[k] = m ? (k === "OPENROUTER_API_KEY" ? "present(len " + m[1].length + ")" : unq(m[1])) : "missing";
    }
    return { exists: true, vars: present };
  })(),
}));
'@
$tmp = Join-Path $env:TEMP 'sms-verify-seed.js'
[System.IO.File]::WriteAllText($tmp, $js, (New-Object System.Text.UTF8Encoding($false)))

# Start-Process so node stderr (e.g. ExperimentalWarning) cannot abort the PS
# pipeline under $ErrorActionPreference=Stop (PS 5.1 NativeCommandError class).
$outFile = Join-Path $env:TEMP 'sms-verify-seed.out.json'
$errFile = Join-Path $env:TEMP 'sms-verify-seed.err.txt'
$proc = Start-Process -FilePath $Node -ArgumentList ('--experimental-sqlite', "`"$tmp`"", "`"$Db`"") -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$out = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
$result = $null
try { $result = $out | ConvertFrom-Json } catch {}

$errors = @()
if ($result) {
  if (-not $result.router.found) { $errors += 'router-row-missing' }
  elseif ($result.router.fallback -ne 'openrouter/z-ai/glm-5.3-flash') { $errors += 'router-fallback-mismatch' }
  elseif ($result.ruleCount -ne 2) { $errors += "rule-count=$($result.ruleCount)" }
  elseif ($result.router.createdByNull -ne $true) { $errors += 'router-created-by-not-null' }
  elseif ($result.badRules.Count -gt 0) { $errors += "bad-rules: $($result.badRules -join '; ')" }
  if ($result.marker -ne 'v2') { $errors += "seed-marker=$($result.marker)" }
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

if ($errors.Count -gt 0) { Write-Host "FAIL: $($errors -join ', ')"; if (Test-Path $errFile) { Write-Host "stderr:"; Get-Content $errFile | Select-Object -First 5 }; Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue; exit 1 }
Write-Host 'OK: seed verified.'
Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
exit 0
