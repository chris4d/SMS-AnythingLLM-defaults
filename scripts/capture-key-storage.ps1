# Phase 1 (Option B key-injection study): capture WHERE AnythingLLM Desktop stores
# provider API keys without capturing the keys themselves. Read-only — this script
# writes nothing into the db or AnythingLLM storage; it reads the db, .env, and
# lists file metadata, and emits a structure report.
#
# Usage (test workstation only, see AGENTS.md):
#   RUN 1 (BEFORE entering key in app UI):  .\capture-key-storage.ps1 -Label before
#   Step 2: enter OpenRouter key in AnythingLLM UI (LLM Provider), then app can
#           be closed — or capture while running for both states.
#   RUN 2 (AFTER):                          .\capture-key-storage.ps1 -Label after
# Output: .\logs\keystorage-<label>.json  (gitignored; no key material inside)
param(
  [string]$Label = $(Get-Date -Format 'yyyyMMdd-HHmmss'),
  [string]$OutputDir = $(Join-Path $PSScriptRoot 'keystorage-captures')   # alongside the script, not an assumed repo root
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $OutputDir)) {
  try { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
  catch { throw "Cannot create output dir '$OutputDir'. Pass your own with -OutputDir." }
}

$StorageDir = Join-Path $Env:APPDATA 'anythingllm-desktop\storage'
$Db         = Join-Path $StorageDir 'anythingllm.db'

if (-not (Test-Path $Db)) { Write-Host "FAIL: db not found at $Db"; exit 1 }

# Find node
$RepoBins = Get-ChildItem $RepoRoot -Filter node.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$Node = if ($RepoBins) { $RepoBins.FullName } else { (Get-Command node.exe -ErrorAction SilentlyContinue).Source }
if (-not $Node) { Write-Host 'FAIL: node.exe not found in repo/bin or on PATH.'; exit 1 }

# --- db structure + redacted row dump ---------------------------------------
$dbJs = @'
const { DatabaseSync } = require("node:sqlite");
const path = require("path");
const crypto = require("crypto");
const DB = process.env.SMS_DB;

function looksKeyLike(s) {
  if (typeof s !== "string" || s.length < 16) return false;
  return /^(sk-|or-|ey-|AIza|glpat|ghp_|sk-or-v1)/i.test(s.trim()) ||
         /^[A-Za-z0-9_-]{32,64}$/.test(s.trim());
}
function redact(raw) {
  // Distinguish "looks like a key" (record length + sha256 prefix for diff match,
  // never record the value) from normal values (record verbatim, they are not secrets).
  const s = String(raw);
  if (!looksKeyLike(s)) return raw;
  return { __redacted: "key", len: s.trim().length, sha256: crypto.createHash("sha256").update(s.trim()).digest("hex").slice(0, 12) };
}

const db = new DatabaseSync(DB, { readOnly: true });
try {
  const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r => r.name);
  const report = {};
  for (const t of tables) {
    const cols = db.prepare(`PRAGMA table_info(${t})`).all().map(c => c.name);
    let rows = db.prepare(`SELECT * FROM ${t}`).all();
    // cap big tables; cap row contents
    if (rows.length > 400) rows = rows.slice(0, 400);
    report[t] = { columns: cols, rows: rows.map(r => {
      const out = {};
      for (const [k, v] of Object.entries(r)) out[k] = v === null ? null : redact(v);
      return out;
    }) };
  }
  console.log(JSON.stringify(report));
} finally { try { db.close(); } catch (_) {} }
'@

# --- .env shape: names + redaction of values (anythingllm regenerates it; report names) ---
$envFile = Join-Path $StorageDir '.env'
$envReport = @()
if (Test-Path $envFile) {
  $envReport = Get-Content $envFile -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_ -match '^\s*([^#=]+)=(.*)$') {
      $name = $Matches[1].Trim(); $val = $Matches[2].Trim()
      $looksKey = $val.Length -ge 20 -and ($val -match '^(sk-|or-|ey-|AIza|glpat|ghp_)' -or ($val -notmatch '\s' -and $val.Length -ge 40 -and $val -match '^[A-Za-z0-9_-]+$' -and $val -notmatch ':'))
      $valueOut = $val
      if ($looksKey) { $valueOut = @{ __redacted = 'key'; len = $val.Length } }
      @($name, $valueOut)
    } else { @('raw-line', $_) }
  }
}

# --- storage dir metadata: which files change when a key is added ------------
$files = Get-ChildItem $StorageDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  @{ name = $_.Name; length = $_.Length; lastWrite = $_.LastWriteTimeUtc.ToString('o') }
}

# --- run the db dump --------------------------------------------------------
$tmpJs = Join-Path $env:TEMP 'sms-capture-keys.js'
[System.IO.File]::WriteAllText($tmpJs, $dbJs)
$env:SMS_DB = $Db
$raw = & $Node --experimental-sqlite $tmpJs 2>$null
Remove-Item $tmpJs -ErrorAction SilentlyContinue

$dbReport = $null
try { $dbReport = $raw | ConvertFrom-Json } catch { Write-Host "FAIL: could not parse db dump (node exit=$LASTEXITCODE)"; exit 1 }

$report = [ordered]@{
  label        = $Label
  capturedAt   = (Get-Date).ToUniversalTime().ToString('o')
  dbPath       = $Db
  database     = $dbReport
  envFile      = $envReport
  storageFiles = $files
}

$outPath = Join-Path $OutputDir "keystorage-$Label.json"
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Host "Captured: $outPath"
Write-Host "Next: `"step: enter the key in the app UI, then rerun with a new -Label (e.g. 'after')`""
exit 0
