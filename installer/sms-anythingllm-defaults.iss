; SMS-AnythingLLM-defaults — per-user, non-admin, silent-safe installer
; DefaultDirName={userpf}\SMS\AnythingLLM-Defaults  (per-user, no admin)

#define AppName "SMS AnythingLLM Defaults"
#define AppVersion "0.1.0"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
DefaultDirName={userpf}\SMS\AnythingLLM-Defaults
DefaultGroupName=SMS Toolkit
OutputDir=dist
OutputBaseFilename=Setup-SMS-AnythingLLM-Defaults-v{#AppVersion}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
DisableWelcomePage=False
Uninstallable=yes
UninstallDisplayName={#AppName}

[Files]
Source: "seed\model-router-seed.json"; DestDir: "{app}\seed"; Flags: recursesubdirs
Source: "scripts\seed-model-router.ps1"; DestDir: "{app}\scripts"
Source: "scripts\seed-registry.js"; DestDir: "{app}\scripts"
Source: "shims\run-anythingllm.cmd"; DestDir: "{app}"

[Icons]
; Default icon runs the real AnythingLLM; when a pending seed exists the shim
; takes over. The shim dispatches (launches app after seeding or immediately).
Name: "{group}\AnythingLLM"; Filename: "{app}\shims\run-anythingllm.cmd"; Description: "AnythingLLM (SMS managed)"
Name: "{userdesktop}\AnythingLLM"; Filename: "{app}\shims\run-anythingllm.cmd"; Description: "AnythingLLM (SMS managed)"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
; Seed step: exit 0 always; reports into {app}\install-status.json.
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\seed-model-router.ps1"" -ApiKeysPath ""{param:ApiKeysPath|}"""; WorkingDir: "{app}"; Flags: runhidden; Description: "Seed SMS baseline model router into AnythingLLM Desktop"

[Code]
procedure InitializeWizard;
begin
  // The suite supplies the apikeys.json path at runtime; no manual key entry here.
  // (In silence mode: pass /ApiKeysPath="<path>" to Setup.)
end;

function GetDefaultApiKeysPath(Param: String) : String;
begin
  Result := ExpandConstant('{param:ApiKeysPath|}');
end;
