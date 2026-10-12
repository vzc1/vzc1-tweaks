; Installer for vzc1's optimizations (built by GitHub Actions with Inno Setup)
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

[Setup]
AppId={{8A3C2E51-6F1D-4B7A-9C2E-1D5F0B7A9E44}
AppName=vzc1's optimizations
AppVersion={#MyAppVersion}
AppVerName=vzc1's optimizations {#MyAppVersion}
AppPublisher=vzc1
AppPublisherURL=https://github.com/vzc1/vzc1-tweaks
AppSupportURL=https://github.com/vzc1/vzc1-tweaks/issues
DefaultDirName={autopf}\vzc1's optimizations
DefaultGroupName=vzc1's optimizations
DisableProgramGroupPage=yes
OutputDir=..
OutputBaseFilename=vzc1-optimizations-setup
SetupIconFile=icon.ico
UninstallDisplayIcon={app}\vzc1-optimizations.exe
UninstallDisplayName=vzc1's optimizations
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE
CloseApplications=force
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany=vzc1
VersionInfoDescription=vzc1's optimizations setup

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "..\vzc1-optimizations.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\vzc1's optimizations"; Filename: "{app}\vzc1-optimizations.exe"
Name: "{group}\Uninstall vzc1's optimizations"; Filename: "{uninstallexe}"
Name: "{autodesktop}\vzc1's optimizations"; Filename: "{app}\vzc1-optimizations.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vzc1-optimizations.exe"; Description: "Open vzc1's optimizations now"; Flags: nowait postinstall skipifsilent shellexec

[UninstallDelete]
Type: files; Name: "{app}\vzc1-optimizations.exe.old"
Type: files; Name: "{app}\vzc1-optimizations.exe.new"
Type: dirifempty; Name: "{app}"

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  DataDir: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    if SuppressibleMsgBox('Undo every tweak and NVIDIA setting this app made before removing it?' + #13#10 + #13#10 + 'Choose No to keep them.', mbConfirmation, MB_YESNO, IDYES) = IDYES then
      Exec(ExpandConstant('{app}\vzc1-optimizations.exe'), '--undo-all', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{localappdata}\vzc1-optimizations');
    if DirExists(DataDir) then
      if SuppressibleMsgBox('Also delete the app''s saved data (log, presets and settings)?', mbConfirmation, MB_YESNO, IDNO) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;
