# Phase 1 (Option B key-injection study): capture WHERE AnythingLLM Desktop stores
# provider API keys without capturing the keys themselves. Read-only - only its own
# report file is written (next to this script, keystorage-captures\).
#
# NOTE: AnythingLLM holds a lock on the db while running. The seeder/capture tools
# should only run with the app closed; this script detects that and exits early.
#
# Usage (test workstation only, see AGENTS.md):
#   .\capture-key-storage.ps1 -Label before    # before entering the key in the app UI
#   .\capture-key-storage.ps1 -Label after     # after entering it, with the app closed
param(
  [string]$Label = $(Get-Date -Format 'yyyyMMdd-HHmmss'),
  [string]$OutputDir = $(Join-Path $PSScriptRoot 'keystorage-captures')
)

$ErrorActionPreference = 'Stop'

# --- locate storage + fail fast on lock --------------------------------------
$StorageDir = Join-Path $Env:APPDATA 'anythingllm-desktop\storage'
if (-not (Test-Path $StorageDir)) { Write-Host "FAIL: storage dir not found at $StorageDir"; exit 1 }
$EnvFile = Join-Path $StorageDir '.env'

# --- locate node -------------------------------------------------------------
$RepoRoot = Split-Path -Parent $PSScriptRoot
$candidates = @()
foreach ($d in @("$env:LOCALAPPDATA\SMS-Toolkit\node\node.exe", "$RepoRoot\bin\node.exe", (Join-Path $PSScriptRoot 'node.exe'))) {
  if (Test-Path $d) { $candidates += $d }
}
if (-not $candidates.Count) {
  $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($cmd) { $candidates = @($cmd.Source) }
}
if (-not $candidates.Count) { Write-Host 'FAIL: node.exe not found near script or on PATH.'; exit 1 }
$Node = $candidates[0]

# --- prep output dir ---------------------------------------------------------
if (-not (Test-Path $OutputDir)) {
  try { New-Item -ItemType Directory -Path $OutputDir -ErrorAction Stop | Out-Null }
  catch { Write-Host "FAIL: cannot create '$OutputDir'. Pass your own with -OutputDir."; exit 1 }
}

# --- run the node reporter ---
$outPath = Join-Path $OutputDir "keystorage-$Label.json"
Write-Host "[1/3] Scanning (db, .env, files - all redacted)..."
$raw = (& $Node --experimental-sqlite (Join-Path $PSScriptRoot 'capture-key-storage.js') `
  --storage-dir $StorageDir --env-file $EnvFile --label $Label 2>&1 | Out-String)
[System.IO.File]::WriteAllText($outPath, $raw, (New-Object System.Text.UTF8Encoding($false)))

# --- verify (parse in node; PS5.1 has no JSON deep-check) --------------------
Write-Host "[2/3] Verifying output..."
$verifyJs = 'const r = JSON.parse(require("fs").readFileSync(process.argv[2],"utf8")); if(!r.ok) throw new Error(r.error||"reporter failed"); if(!r.database) throw new Error("no database section");'
$tmpVerify = Join-Path $env:TEMP 'sms-verify-capture.js'
[System.IO.File]::WriteAllText($tmpVerify, $verifyJs)
& $Node $tmpVerify $outPath 2>&1 | ForEach-Object { $_ }
Remove-Item $tmpVerify -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) {
  Write-Host "FAIL: see $outPath"
  exit 1
}

Write-Host "[3/3] Captured: $outPath"
Write-Host "Next: enter the key in the app UI, close the app, rerun with -Label after."
exit 0
