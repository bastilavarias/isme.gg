; Optional developer installer. Compile only after the portable bundle passes testing.
; No public release, signing, elevation, updater or dependency installation.
#define AppName "isme.gg Desktop"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#define Bundle "..\build\windows\x64\runner\Release"
[Setup]
AppId=isme.gg.desktop
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\isme.gg Desktop
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=output
OutputBaseFilename=ismegg-desktop-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
[Files]
Source: "{#Bundle}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\ismegg_desktop.exe"
[Run]
Filename: "{app}\ismegg_desktop.exe"; Description: "Launch isme.gg Desktop"; Flags: nowait postinstall skipifsilent
