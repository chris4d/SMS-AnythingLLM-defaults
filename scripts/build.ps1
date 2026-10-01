# Build: compile the Inno installer into dist\. Local only — never executes seeding.
# Usage: .\scripts\build.ps1 [-Version 0.2.0] [-CertThumbprint <thumbprint>]
#        [-PfxPath <file.pfx> -PfxPassword <pass>] [-TimestampUrl <url>]
# Signing is optional: with no cert args the exe is built unsigned (SmartScreen
# will warn on fresh machines). With cert args, signtool signs after compile and
# the reported SHA-256 is of the signed binary (what the suite stages).
param(
  [string]$Version = '0.2.0',
  [string]$CertThumbprint = '',    # cert in the user/machine store (token/HSM-backed)
  [string]$PfxPath = '',           # alternative: PFX file on disk
  [string]$PfxPassword = '',
  [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Iss = Join-Path $Root 'installer\sms-anythingllm-defaults.iss'
$Dist = Join-Path $Root 'installer\dist'

if (-not (Test-Path $Dist)) { New-Item -ItemType Directory -Path $Dist | Out-Null }

# Locate Inno Setup compiler
$ISCC = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ISCC) { throw 'ISCC.exe not found. Install Inno Setup 6.' }

# Locate signtool (Windows SDK / SDK BuildTools nuget cache / PATH)
$Signtool = $null
$signtoolCandidates = @()
foreach ($base in @("${env:ProgramFiles(x86)}\Windows Kits\10\bin", "$env:ProgramFiles\Windows Kits\10\bin")) {
  if (Test-Path $base) {
    $signtoolCandidates += Get-ChildItem $base -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match 'x64' } | Select-Object -ExpandProperty FullName
  }
}
$nugetCache = "$env:USERPROFILE\.nuget\packages\microsoft.windows.sdk.buildtools"
if (Test-Path $nugetCache) {
  $signtoolCandidates += Get-ChildItem $nugetCache -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'x64' } | Select-Object -ExpandProperty FullName
}
$cmdSigntool = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($cmdSigntool) { $signtoolCandidates += $cmdSigntool.Source }
$Signtool = $signtoolCandidates | Select-Object -First 1

# Stamp version into the .iss
$content = [System.IO.File]::ReadAllText($Iss)
$content = $content -replace '#define AppVersion "[^"]+"', "#define AppVersion `"$Version`""
[System.IO.File]::WriteAllText($Iss, $content)

& $ISCC "/Qp" $Iss | Out-Null
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$Exe = Join-Path $Dist "Setup-SMS-AnythingLLM-Defaults-v$Version.exe"
if (-not (Test-Path $Exe)) { throw "Build finished but exe not found: $Exe" }

# --- optional code signing ---------------------------------------------------
$signed = $false
if ($CertThumbprint -or $PfxPath) {
  if (-not $Signtool) { throw 'Signing requested but signtool.exe not found. Install the Windows SDK signing tools.' }
  $sigArgs = @('sign', '/fd', 'SHA256', '/td', 'SHA256', '/tr', $TimestampUrl)
  if ($CertThumbprint) { $sigArgs += @('/sha1', $CertThumbprint) }
  elseif ($PfxPath) { $sigArgs += @('/f', $PfxPath, '/p', $PfxPassword) }
  $sigArgs += $Exe
  Write-Host "Signing with: $Signtool"
  & $Signtool @sigArgs
  if ($LASTEXITCODE -ne 0) { throw "signtool failed with exit code $LASTEXITCODE" }
  $signed = $true
}

$Hash = (Get-FileHash $Exe -Algorithm SHA256).Hash
Write-Host "Built: $Exe"
Write-Host "Signed: $signed"
Write-Host "SHA-256: $Hash"
if ($signed) {
  & $Signtool verify /pa "$Exe"
  if ($LASTEXITCODE -ne 0) { Write-Host 'WARNING: signature verification failed.' }
}
