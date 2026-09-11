# Step: seed the SMS baseline model router into AnythingLLM Desktop.
# Called from Inno [Run] (also rerunnable standalone). Quiet, exit 0 always.
param(
  [string]$ApiKeysPath,        # suite-provided path (recorded only, never read here)
  [int]$WaitSeconds = 120     # first-launch wait when db missing
)

$ErrorActionPreference = 'SilentlyContinue'
$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent
$SeedFile = Join-Path $AppDir 'seed\model-router-seed.json'
$StatusFile = Join-Path $AppDir 'install-status.json'
$StorageDir = Join-Path $Env:APPDATA 'anythingllm-desktop\storage'
$Node = Join-Path $AppDir 'bin\node.exe'

function Get-Node {
  if (Test-Path $Node) { return $Node }
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
  # exit code intentionally ignored: seeder records via install-status.json
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

# If launched interactively (not from installer), wait briefly and reseed once db appears.
if ($WaitSeconds -gt 0 -and -not ($MyInvocation.Line -match 'installer')) {
  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if (Test-Path (Join-Path $StorageDir 'anythingllm.db')) {
      Invoke-Seed
      break
    }
  }
}
exit 0
