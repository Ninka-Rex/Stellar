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
#ifndef OutputDirOverride
  #define OutputDirOverride "output"
#endif
#ifndef OutputBaseFilenameOverride
  #define OutputBaseFilenameOverride "StellarSetup-{#AppVersion}"
#endif

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
; Output goes to packaging/windows/output/ by default, but release.ps1 can
; override this to stage the build in a fresh temp directory first.
OutputDir={#OutputDirOverride}
OutputBaseFilename={#OutputBaseFilenameOverride}
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExeName}
; The release payload is large (~1+ GB with Qt, yt-dlp, and FFmpeg), and
; ultra64 + fully solid compression can push ISCC into multi-GB RAM usage.
; Use a still-strong but safer profile so release.ps1 can build reliably.
Compression=lzma2/max
SolidCompression=no
LZMANumBlockThreads=2
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

; App content files
Source: "{#BuildDir}\tips.txt";                  DestDir: "{app}";                      Flags: ignoreversion skipifsourcedoesntexist

; Third-party license notices (required for LGPL/GPL compliance — FFmpeg, Qt, SQLite)
Source: "..\..\THIRD-PARTY-NOTICES.txt";         DestDir: "{app}";                      Flags: ignoreversion

; Visual C++ Redistributable (windeployqt copies this)
Source: "{#BuildDir}\vc_redist.x64.exe";        DestDir: "{tmp}";                       Flags: deleteafterinstall skipifsourcedoesntexist

; yt-dlp binary — bundled by release.ps1 (downloaded from github.com/yt-dlp/yt-dlp).
; skipifsourcedoesntexist allows the installer to build without it; the app will
; prompt the user to download it on first run.
Source: "{#BuildDir}\yt-dlp.exe";              DestDir: "{app}";          Flags: ignoreversion skipifsourcedoesntexist

; ffmpeg + ffprobe — bundled by release.ps1 (downloaded from BtbN/FFmpeg-Builds).
; Both are required for HD video merging and post-processing (thumbnail embedding,
; chapter modification via SponsorBlock, etc.).
Source: "{#BuildDir}\ffmpeg.exe";              DestDir: "{app}";          Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BuildDir}\ffprobe.exe";             DestDir: "{app}";          Flags: ignoreversion skipifsourcedoesntexist

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
function ShouldAutoRestartStellar(): Boolean;
var
  I: Integer;
  Arg: String;
begin
  // Auto-updates run the installer with /VERYSILENT, which suppresses the
  // normal postinstall [Run] entry above. Use an explicit custom switch so
  // only the in-app updater restarts Stellar after installation.
  Result := False;
  for I := 1 to ParamCount do begin
    Arg := Uppercase(ParamStr(I));
    if (Arg = '/RESTARTSTELLAR') or (Arg = '-RESTARTSTELLAR') then begin
      Result := True;
      Exit;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im {#AppExeName}', '', SW_HIDE,
    ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if (CurStep = ssPostInstall) and ShouldAutoRestartStellar() then begin
    Exec(ExpandConstant('{app}\{#AppExeName}'), '', ExpandConstant('{app}'),
      SW_SHOWNORMAL, ewNoWait, ResultCode);
  end;
end;
