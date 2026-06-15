; Stellar Download Manager — Inno Setup installer script
; Build with: iscc installer.iss  (from packaging/windows/ OR via release.ps1)

#define AppName      "Stellar Download Manager"
; AppVersion is passed from the command line: iscc /DAppVersion=x.y.z
; Fall back to a placeholder if built directly without release.ps1
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppPublisher "Ninka_"
#define AppURL       "https://stellardownloadmanager.org/"
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
; NOTE: Chrome/Firefox native messaging hosts are registered by the app itself on
; first launch (AppController::registerNativeHost), pointing each browser at its own
; manifest in {app}. No installer task is needed; the [Registry] section below only
; tags those app-written keys for removal at uninstall.

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

; Bundled IP-to-city database (free DB-IP lite, updated periodically).
; The filename is month-stamped (dbip-city-lite-YYYY-MM.mmdb), so a newer
; bundle never overwrites the old file — it lands beside it. The
; [InstallDelete] entry below wipes any prior copy first so they don't pile up.
Source: "{#BuildDir}\data\dbip-city-lite-*.mmdb"; DestDir: "{app}\data"; Flags: ignoreversion skipifsourcedoesntexist

; Third-party license notices (required for LGPL/GPL compliance — FFmpeg, Qt, SQLite)
Source: "..\..\THIRD-PARTY-NOTICES.txt";         DestDir: "{app}";                      Flags: ignoreversion

; NOTE: No vc_redist.x64.exe — the MSVC runtime DLLs (vcruntime140.dll,
; vcruntime140_1.dll, msvcp140.dll) are shipped loose via the *.dll glob above,
; copied by `windeployqt --compiler-runtime`. The app is fully self-contained and
; never installs a system-wide VC++ redistributable.

; yt-dlp binary — bundled by release.ps1 (downloaded from github.com/yt-dlp/yt-dlp).
; skipifsourcedoesntexist allows the installer to build without it; the app will
; prompt the user to download it on first run.
Source: "{#BuildDir}\yt-dlp.exe";              DestDir: "{app}";          Flags: ignoreversion skipifsourcedoesntexist

; ffmpeg + ffprobe — bundled by release.ps1 (downloaded from BtbN/FFmpeg-Builds).
; Both are required for HD video merging and post-processing (thumbnail embedding,
; chapter modification via SponsorBlock, etc.).
Source: "{#BuildDir}\ffmpeg.exe";              DestDir: "{app}";          Flags: ignoreversion skipifsourcedoesntexist
Source: "{#BuildDir}\ffprobe.exe";             DestDir: "{app}";          Flags: ignoreversion skipifsourcedoesntexist

[InstallDelete]
; Month-stamped geo DB: a new bundle has a different filename and won't
; overwrite the old one, so remove every prior copy before [Files] copies the
; fresh DB in. The new file is copied afterwards, so this never deletes it.
Type: files; Name: "{app}\data\dbip-city-lite-*.mmdb"

[Icons]
Name: "{group}\Stellar Download Manager"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall Stellar";        Filename: "{uninstallexe}"
Name: "{userdesktop}\Stellar Download Manager"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; The app registers these native messaging host keys itself on first launch
; (pointing each browser at its own manifest in {app}). dontcreatekey means the
; installer never writes them; uninsdeletekey makes the uninstaller remove the
; app-written keys so nothing is left behind.
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\com.stellar.downloadmanager"; \
  Flags: dontcreatekey uninsdeletekey
Root: HKCU; Subkey: "Software\Mozilla\NativeMessagingHosts\com.stellar.downloadmanager"; \
  Flags: dontcreatekey uninsdeletekey

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

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

// True while a Stellar.exe process exists. Uses taskkill's query-only behaviour:
// "/im Stellar.exe" with no "/f" returns 0 when at least one matching process was
// found (and signalled) and 128 ("not found") once they are all gone. We only read
// the exit code here — the WM_CLOSE it sends is harmless (the app hides to tray on
// it, it does not kill), so this doubles as a poll without force-killing anything.
function StellarIsRunning(): Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  if Exec(ExpandConstant('{sys}\taskkill.exe'), '/im {#AppExeName}', '', SW_HIDE,
          ewWaitUntilTerminated, ResultCode) then
    Result := (ResultCode = 0);
end;

// Ask any running Stellar to shut down gracefully (flushing its download DB and
// torrent resume data), then wait for the process to actually disappear before
// touching its files. Force-kill is a last resort only after the grace window.
procedure ShutDownStellar();
var
  ResultCode: Integer;
  ExePath: String;
  Waited: Integer;
begin
  ExePath := ExpandConstant('{app}\{#AppExeName}');
  // On a first install the exe isn't present yet (this runs before [Files]); there
  // is nothing to shut down. The graceful path only applies to upgrades/uninstall.
  if not FileExists(ExePath) then
    Exit;

  // Newer builds understand --quit: it signals the running instance to close
  // gracefully and returns. Older builds (<= 0.10.3) don't have the switch and
  // simply no-op, so we never depend on it — the wait loop below is what actually
  // gates progress, and a stubborn old instance just falls through to force-kill.
  Exec(ExePath, '--quit', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);

  // Wait for the process to be gone. Only proceed once it actually exits, so we
  // never replace files out from under a still-running instance.
  Waited := 0;
  while StellarIsRunning() and (Waited < 30000) do begin
    Sleep(300);
    Waited := Waited + 300;
  end;

  // Last resort: an instance that never exited (no --quit support, or hung) gets
  // force-killed so the install/uninstall isn't blocked by a locked exe.
  if StellarIsRunning() then
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im {#AppExeName}', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  ShutDownStellar();
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

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Gracefully stop Stellar before removing its files (was a hard taskkill).
  if CurUninstallStep = usUninstall then
    ShutDownStellar();
end;
