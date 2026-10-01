# Step: seed the SMS baseline model router into AnythingLLM Desktop.
# Called from Inno [Run] (also rerunnable standalone). Quiet, exit 0 always.
param(
  [string]$ApiKeysPath,        # suite-provided path (recorded only, never read here)
  [string]$NodePath,           # suite-provided node.exe path (takes priority; staff machines have no PATH node)
  [int]$WaitSeconds = 120     # first-launch wait when db missing
)

$ErrorActionPreference = 'SilentlyContinue'
$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$SeedFile = Join-Path $AppDir 'seed\model-router-seed.json'
$StatusFile = Join-Path $AppDir 'sms-anythingllm-defaults-status.json'
$StorageDir = Join-Path $Env:APPDATA 'anythingllm-desktop\storage'
$Node = Join-Path $AppDir 'bin\node.exe'

# Suite-provided NodePath is the primary source; persist it so the first-launch
# shim path (which re-invokes this script without params) resolves the same node.
$NodePathFile = Join-Path $AppDir 'node-path.txt'
$ApiKeysPathFile = Join-Path $AppDir 'apikeys-path.txt'
if ($NodePath -and (Test-Path $NodePath)) {
  try { Set-Content -LiteralPath $NodePathFile -Value $NodePath -Encoding ascii } catch { }
}
# Persist the suite-provided apikeys.json path so the first-launch shim path
# (which re-invokes this script without params) still injects the key.
if ($ApiKeysPath) {
  try { Set-Content -LiteralPath $ApiKeysPathFile -Value $ApiKeysPath -Encoding ascii } catch { }
}
if (-not $ApiKeysPath -and (Test-Path $ApiKeysPathFile)) {
  $saved = Get-Content -LiteralPath $ApiKeysPathFile -Raw -ErrorAction SilentlyContinue
  if ($saved) { $ApiKeysPath = $saved.Trim() }
}

function Get-Node {
  if ($NodePath -and (Test-Path $NodePath)) { return $NodePath }
  if (Test-Path $Node) { return $Node }
  if (Test-Path $NodePathFile) {
    $saved = (Get-Content -LiteralPath $NodePathFile -Raw -ErrorAction SilentlyContinue)
    if ($saved) { $saved = $saved.Trim() }
    if ($saved -and (Test-Path $saved)) { return $saved }
  }
  $suite = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($suite) { return $suite.Source }
  return $null
}

function Invoke-Seed {
  $node = Get-Node
  if (-not $node) {
    @{ ok = $false } | Set-Content -LiteralPath $StatusFile
    return
  }
  & $node --experimental-sqlite (Join-Path $AppDir 'scripts\seed-registry.js') `
    --storage-dir $StorageDir --seed-file $SeedFile --app-dir $AppDir `
    --status-file $StatusFile --apikeys-path $ApiKeysPath 2>$null | Out-Null
  # exit code intentionally ignored: seeder records via sms-anythingllm-defaults-status.json
}

if (-not (Test-Path $SeedFile)) {
  @{ steps = @(, @{ name = 'seed-model-router'; ok = $false; action = 'missing-seed-file'; message = (Get-Date -Format o) }) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StatusFile
  exit 0
}

Invoke-Seed

if (Test-Path (Join-Path $StorageDir 'anythingllm.db')) { exit 0 }

# db missing: seed deferred to first app launch via shim.
$Pending = Join-Path $AppDir 'pending-seed.json'
if (-not (Test-Path $Pending)) { exit 0 }

# Shim path (WaitSeconds > 0): the shim launched the app; poll for the db, then
# close the app (Phase 1 evidence: provider keys live in storage\.env and the app
# must not rewrite it after our merge), seed, and relaunch.
if ($WaitSeconds -gt 0) {
  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if (Test-Path (Join-Path $StorageDir 'anythingllm.db')) { break }
  }
  if (Test-Path (Join-Path $StorageDir 'anythingllm.db')) {
    # Close the app so it cannot re-dump .env over our injected vars.
    taskkill /IM AnythingLLM.exe /F 2>$null | Out-Null
    $killDeadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $killDeadline) {
      Start-Sleep -Seconds 1
      $stillRunning = Get-Process -Name 'AnythingLLM' -ErrorAction SilentlyContinue
      if (-not $stillRunning) { break }
    }
    Invoke-Seed
    # Relaunch the app for the user.
    $launcher = Join-Path $Env:LOCALAPPDATA 'Programs\AnythingLLM\AnythingLLM.exe'
    if (Test-Path $launcher) { Start-Process -FilePath $launcher | Out-Null }
    Remove-Item -LiteralPath $Pending -Force -ErrorAction SilentlyContinue
  }
}
exit 0
