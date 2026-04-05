; Inno Setup script for Stellar Download Manager
; Build with: iscc installer.iss  (from the packaging/windows/ directory)

#define AppName      "Stellar Download Manager"
#define AppVersion   "0.1.0"
#define AppPublisher "Ninka-Rex"
#define AppURL       "https://stellar.moe/"
#define AppExeName   "Stellar.exe"
#define BuildDir     "..\..\build\windows-release"

[Setup]
AppId={{B3F2A1D0-4E7C-4F2A-9B1D-1234567890AB}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\Stellar
DefaultGroupName=Stellar
OutputBaseFilename=StellarSetup-{#AppVersion}
SetupIconFile=stellar.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "chromeext";   Description: "Register Chrome Native Messaging host"; GroupDescription: "Browser integration:"
Name: "firefoxext";  Description: "Register Firefox Native Messaging host"; GroupDescription: "Browser integration:"

[Files]
Source: "{#BuildDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll";         DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "{#BuildDir}\plugins\*";     DestDir: "{app}\plugins"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Stellar";             Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall Stellar";   Filename: "{uninstallexe}"
Name: "{commondesktop}\Stellar";     Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; Chrome Native Messaging host registration
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\com.stellar.downloadmanager"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\native-host-manifest.json"; \
  Tasks: chromeext; Flags: uninsdeletekey

; Firefox Native Messaging host registration
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.stellar.downloadmanager"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\native-host-manifest.json"; \
  Tasks: firefoxext; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch Stellar"; Flags: nowait postinstall skipifsilent
