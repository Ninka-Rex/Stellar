; Stellar Download Manager — Inno Setup installer script
; Build with: iscc installer.iss  (from packaging/windows/ OR via release.ps1)

#define AppName      "Stellar Download Manager"
; AppVersion is passed from the command line: iscc /DAppVersion=x.y.z
; Fall back to a placeholder if built directly without release.ps1
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppPublisher "Ninka_"
#define AppURL       "https://stellar.moe/"
#define AppExeName   "Stellar.exe"
; Path relative to this .iss file (packaging/windows/)
#define BuildDir     "..\..\build\windows-release"
#define IconFile     "..\..\app\qml\icons\milky-way.ico"

[Setup]
AppId={{B3F2A1D0-4E7C-4F2A-9B1D-1234567890AB}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
; Install to %LOCALAPPDATA%\StellarDownloadManager — no UAC, no admin required
DefaultDirName={localappdata}\StellarDownloadManager
DefaultGroupName=StellarDownloadManager
; Output goes to packaging/windows/output/
OutputDir=output
OutputBaseFilename=StellarSetup-{#AppVersion}
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
LZMANumBlockThreads=4
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
; No admin required — installs to %LOCALAPPDATA%
PrivilegesRequired=lowest
; Restart-free uninstall of previous version
CloseApplications=yes
RestartApplications=yes
CloseApplicationsFilter=Stellar.exe
; Version info shown in Add/Remove Programs
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "quicklaunch";  Description: "Pin to &taskbar"; GroupDescription: "Additional icons:"; Flags: unchecked
Name: "chromeext";    Description: "Register &Chrome native messaging host"; GroupDescription: "Browser integration:"
Name: "firefoxext";   Description: "Register &Firefox native messaging host"; GroupDescription: "Browser integration:"

[Files]
; Main executable
Source: "{#BuildDir}\{#AppExeName}";            DestDir: "{app}";          Flags: ignoreversion

; Qt runtime DLLs (windeployqt output)
Source: "{#BuildDir}\*.dll";                    DestDir: "{app}";          Flags: ignoreversion

; Qt plugins — windeployqt places these as top-level subdirectories
Source: "{#BuildDir}\generic\*";                DestDir: "{app}\generic";              Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#BuildDir}\iconengines\*";            DestDir: "{app}\iconengines";          Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#BuildDir}\imageformats\*";           DestDir: "{app}\imageformats";         Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#BuildDir}\networkinformation\*";     DestDir: "{app}\networkinformation";   Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#BuildDir}\platforms\*";              DestDir: "{app}\platforms";            Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#BuildDir}\styles\*";                 DestDir: "{app}\styles";               Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#BuildDir}\tls\*";                    DestDir: "{app}\tls";                  Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
; QML imports (windeployqt copies these)
Source: "{#BuildDir}\qml\*";                    DestDir: "{app}\qml";                  Flags: ignoreversion recursesubdirs createallsubdirs

; Firefox extension package
Source: "{#BuildDir}\extensions\firefox\stellar-firefox.xpi"; DestDir: "{app}\extensions\firefox"; Flags: ignoreversion skipifsourcedoesntexist

; App content files
Source: "{#BuildDir}\tips.txt";                  DestDir: "{app}";                      Flags: ignoreversion skipifsourcedoesntexist

; Third-party license notices (required for LGPL/GPL compliance — FFmpeg, Qt, SQLite)
Source: "..\..\THIRD-PARTY-NOTICES.txt";         DestDir: "{app}";                      Flags: ignoreversion

; Visual C++ Redistributable (windeployqt copies this)
Source: "{#BuildDir}\vc_redist.x64.exe";        DestDir: "{tmp}";                       Flags: deleteafterinstall skipifsourcedoesntexist

; yt-dlp binary (optional — the app can also download it on first run)
; Place yt-dlp.exe next to the installer script or in the build output directory
; before packaging.  skipifsourcedoesntexist allows the installer to build
; without the binary present; the app will prompt the user to download it.
Source: "{#BuildDir}\yt-dlp.exe";              DestDir: "{app}";          Flags: ignoreversion skipifsourcedoesntexist

; Native messaging manifest (path placeholder filled by [Registry])
Source: "native-host-manifest-installed.json";  DestDir: "{app}";          DestName: "native-host-manifest.json"; Flags: ignoreversion

[Icons]
Name: "{group}\Stellar Download Manager"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall Stellar";        Filename: "{uninstallexe}"
Name: "{userdesktop}\Stellar";            Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; Chrome native messaging host
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\com.stellar.downloadmanager"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\native-host-manifest.json"; \
  Tasks: chromeext; Flags: uninsdeletekey

; Firefox native messaging host
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.stellar.downloadmanager"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\native-host-manifest.json"; \
  Tasks: firefoxext; Flags: uninsdeletekey

[Run]
; Install VC++ Redistributable silently if present
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
  Flags: skipifdoesntexist runhidden waituntilterminated; \
  StatusMsg: "Installing Visual C++ Redistributable..."
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Kill any running instance before uninstall
Filename: "taskkill.exe"; Parameters: "/f /im {#AppExeName}"; Flags: runhidden; RunOnceId: "KillStellar"

[UninstallDelete]
; Clean up user data only if the user explicitly opts in — we don't wipe downloads.json silently.
; Log/temp files that are safe to remove:
Type: filesandordirs; Name: "{localappdata}\Stellar\logs"

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im {#AppExeName}', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode);
  Result := '';
end;
