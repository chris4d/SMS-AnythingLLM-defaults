# Build: compile the Inno installer into dist\. Local only — never executes seeding.
# Usage: .\scripts\build.ps1 [-Version 0.1.0]
param([string]$Version = '0.1.0')

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Iss = Join-Path $Root 'installer\sms-anythingllm-defaults.iss'
$Dist = Join-Path $Root 'dist'

if (-not (Test-Path $Dist)) { New-Item -ItemType Directory -Path $Dist | Out-Null }

# Locate Inno Setup compiler
$ISCC = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ISCC) { throw 'ISCC.exe not found. Install Inno Setup 6.' }

# Stamp version into the .iss
$content = [System.IO.File]::ReadAllText($Iss)
$content = $content -replace '#define AppVersion "[^"]+"', "#define AppVersion `"$Version`""
[System.IO.File]::WriteAllText($Iss, $content)

& $ISCC "/Qp" $Iss | Out-Null
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$Exe = Join-Path $Dist "Setup-SMS-AnythingLLM-Defaults-v$Version.exe"
if (Test-Path $Exe) {
  $Hash = (Get-FileHash $Exe -Algorithm SHA256).Hash
  Write-Host "Built: $Exe"
  Write-Host "SHA-256: $Hash"
} else {
  throw "Build finished but exe not found."
}
