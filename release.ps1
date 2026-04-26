# Stellar Download Manager — Windows release script
# Usage:  .\release.ps1 [-Version "0.2.0"] [-QtDir "C:\Qt\6.8.x\msvc2022_64"] [-SkipBuild] [-SkipInstaller] [-SkipArchive] [-SkipBinaries]
#
# Prerequisites (must be on PATH or provided via -QtDir):
#   - CMake + Ninja
#   - Qt 6.8 MSVC build (windeployqt)
#   - Inno Setup 6  (iscc.exe)
#   - 7-Zip          (7z.exe)
#
# Third-party binaries (auto-downloaded unless -SkipBinaries):
#   - yt-dlp.exe   — from github.com/yt-dlp/yt-dlp/releases/latest
#   - ffmpeg.exe   — from github.com/BtbN/FFmpeg-Builds (GPL shared, latest)
#   - ffprobe.exe  — bundled in the same ffmpeg archive
#
# Output:
#   dist\windows\StellarSetup-<Version>.exe
#   dist\Stellar-<Version>-windows-installer.7z
#   dist\Stellar-<Version>-source.7z

param(
    [string]$Version       = "",
    [string]$QtDir         = "",          # e.g. C:\Qt\6.8.3\msvc2022_64
    [switch]$SkipBuild,
    [switch]$SkipInstaller,
    [switch]$SkipArchive,
    [switch]$SkipBinaries                 # skip downloading yt-dlp/ffmpeg/ffprobe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root       = $PSScriptRoot
$BuildDir   = "$Root\build\windows-release"
$DistDir    = "$Root\dist"
$WinDistDir = "$DistDir\windows"
$CMakeLists = Join-Path $Root "CMakeLists.txt"

function Get-ProjectVersion([string]$cmakeFile) {
    if (-not (Test-Path $cmakeFile)) {
        Write-Error "CMakeLists.txt not found at $cmakeFile"
    }
    $cmakeText = Get-Content $cmakeFile -Raw
    if ($cmakeText -notmatch 'project\(Stellar VERSION (\d+\.\d+\.\d+)') {
        Write-Error "Could not determine Stellar version from $cmakeFile"
    }
    return $Matches[1]
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-ProjectVersion $CMakeLists
}
Write-Host "[release] Version: $Version" -ForegroundColor Cyan

# ── Resolve Qt ──────────────────────────────────────────────────────────────
if ($QtDir -eq "") {
    # Try QTDIR env var, then common install locations
    if ($env:QTDIR -ne $null -and (Test-Path "$env:QTDIR\bin\windeployqt.exe")) {
        $QtDir = $env:QTDIR
    } else {
        $candidates = @(
            "C:\Qt\msvc2022_64",
            "C:\Qt\6.8.3\msvc2022_64",
            "C:\Qt\6.8.2\msvc2022_64",
            "C:\Qt\6.8.1\msvc2022_64",
            "C:\Qt\6.8.0\msvc2022_64"
        )
        foreach ($c in $candidates) {
            if (Test-Path "$c\bin\windeployqt.exe") { $QtDir = $c; break }
        }
    }
}
if ($QtDir -eq "" -or -not (Test-Path "$QtDir\bin\windeployqt.exe")) {
    Write-Error "Qt not found. Pass -QtDir 'C:\Qt\6.x.y\msvc2022_64' or set QTDIR."
}
$env:QTDIR = $QtDir
$env:Path  = "$QtDir\bin;$env:Path"
Write-Host "[release] Using Qt: $QtDir" -ForegroundColor Cyan

# ── Find tools ───────────────────────────────────────────────────────────────
function Find-Tool([string]$name, [string[]]$extra) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in $extra) {
        if (Test-Path $p) { return $p }
    }
    Write-Error "'$name' not found. Install it and ensure it is on PATH."
}

$ISCC = Find-Tool "iscc" @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)
$7Z   = Find-Tool "7z" @(
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe"
)
Write-Host "[release] ISCC : $ISCC" -ForegroundColor Cyan
Write-Host "[release] 7-Zip: $7Z"   -ForegroundColor Cyan

# ── Build ────────────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "`n[release] Configuring (windows-release)..." -ForegroundColor Yellow
    Push-Location $Root
    cmake --preset windows-release
    if ($LASTEXITCODE -ne 0) { Write-Error "cmake configure failed" }

    Write-Host "[release] Building..." -ForegroundColor Yellow
    cmake --build --preset windows-release --config Release
    if ($LASTEXITCODE -ne 0) { Write-Error "cmake build failed" }
    Pop-Location
    Write-Host "[release] Build complete." -ForegroundColor Green
} else {
    Write-Host "[release] Skipping build." -ForegroundColor DarkGray
}

# ── Third-party binaries (yt-dlp, ffmpeg, ffprobe) ───────────────────────────
if (-not $SkipBinaries) {
    Write-Host "`n[release] Fetching third-party binaries..." -ForegroundColor Yellow

    # yt-dlp.exe — single-file release from GitHub
    $YtdlpDest = "$BuildDir\yt-dlp.exe"
    if (Test-Path $YtdlpDest) {
        Write-Host "[release]   yt-dlp.exe already present, skipping download." -ForegroundColor DarkGray
    } else {
        Write-Host "[release]   Downloading yt-dlp.exe..."
        $YtdlpUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        Invoke-WebRequest -Uri $YtdlpUrl -OutFile $YtdlpDest -UseBasicParsing
        Write-Host "[release]   yt-dlp.exe downloaded." -ForegroundColor Green
    }

    # ffmpeg.exe + ffprobe.exe — from BtbN's GPL shared Windows build on GitHub.
    # This release ships the full FFmpeg suite (ffmpeg, ffprobe, ffplay) as a ZIP.
    # We use the "essentials" build (GPL, shared libs stripped in, ~70 MB) so the
    # installer stays self-contained without separate DLLs.
    $FfmpegDest  = "$BuildDir\ffmpeg.exe"
    $FfprobeDest = "$BuildDir\ffprobe.exe"
    if ((Test-Path $FfmpegDest) -and (Test-Path $FfprobeDest)) {
        Write-Host "[release]   ffmpeg.exe + ffprobe.exe already present, skipping download." -ForegroundColor DarkGray
    } else {
        Write-Host "[release]   Resolving latest FFmpeg release from BtbN/FFmpeg-Builds..."
        # Fetch the latest release JSON to get the actual asset URL (avoids hardcoding a version).
        $FfmpegApiUrl = "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest"
        $headers = @{ "User-Agent" = "StellarReleaseScript/1.0" }
        $release = Invoke-RestMethod -Uri $FfmpegApiUrl -Headers $headers
        # Pick the win64 GPL-shared essentials ZIP (no separate DLLs needed).
        $asset = $release.assets | Where-Object {
            $_.name -match "ffmpeg-master-latest-win64-gpl\.zip$"
        } | Select-Object -First 1
        if (-not $asset) {
            Write-Error "Could not find ffmpeg-master-latest-win64-gpl.zip in BtbN release assets."
        }
        $FfmpegZipUrl = $asset.browser_download_url
        Write-Host "[release]   Downloading $($asset.name) (~$('{0:N0}' -f ($asset.size/1MB)) MB)..."
        $FfmpegZip = "$env:TEMP\stellar-ffmpeg-release.zip"
        Invoke-WebRequest -Uri $FfmpegZipUrl -OutFile $FfmpegZip -UseBasicParsing

        Write-Host "[release]   Extracting ffmpeg.exe and ffprobe.exe..."
        $FfmpegExtract = "$env:TEMP\stellar-ffmpeg-extract"
        if (Test-Path $FfmpegExtract) { Remove-Item $FfmpegExtract -Recurse -Force }
        Expand-Archive -LiteralPath $FfmpegZip -DestinationPath $FfmpegExtract -Force

        # BtbN archives contain a single top-level directory with a bin\ subdirectory.
        $FfmpegBin  = Get-ChildItem $FfmpegExtract -Recurse -Filter "ffmpeg.exe"  | Select-Object -First 1
        $FfprobeBin = Get-ChildItem $FfmpegExtract -Recurse -Filter "ffprobe.exe" | Select-Object -First 1

        if (-not $FfmpegBin)  { Write-Error "ffmpeg.exe not found in downloaded archive." }
        if (-not $FfprobeBin) { Write-Error "ffprobe.exe not found in downloaded archive." }

        Copy-Item $FfmpegBin.FullName  $FfmpegDest  -Force
        Copy-Item $FfprobeBin.FullName $FfprobeDest -Force

        Remove-Item $FfmpegZip     -Force
        Remove-Item $FfmpegExtract -Recurse -Force
        Write-Host "[release]   ffmpeg.exe + ffprobe.exe installed." -ForegroundColor Green
    }
} else {
    Write-Host "[release] Skipping third-party binary download." -ForegroundColor DarkGray
}

# ── windeployqt ──────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "`n[release] Running windeployqt..." -ForegroundColor Yellow
    & "$QtDir\bin\windeployqt.exe" `
        --release `
        --qmldir "$Root\app\qml" `
        --no-translations `
        "$BuildDir\Stellar.exe"
    if ($LASTEXITCODE -ne 0) { Write-Error "windeployqt failed" }

    # QtQuick.Dialogs workaround (same as CMakeLists auto-copy)
    $dialogsSrc = "$QtDir\qml\QtQuick\Dialogs"
    $dialogsDst = "$BuildDir\qml\QtQuick\Dialogs"
    if (Test-Path $dialogsSrc) {
        Write-Host "[release] Copying QtQuick/Dialogs..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $dialogsDst | Out-Null
        Copy-Item "$dialogsSrc\*" $dialogsDst -Recurse -Force
    }
    Write-Host "[release] windeployqt done." -ForegroundColor Green
}

# ── Inno Setup ───────────────────────────────────────────────────────────────
$InstallerDir = "$Root\packaging\windows"
$InstallerOut = "$InstallerDir\output"
$InstallerExe = "$InstallerOut\StellarSetup-$Version.exe"

if (-not $SkipInstaller) {
    Write-Host "`n[release] Building installer..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $InstallerOut | Out-Null
    $InstallerStageRoot = Join-Path $env:TEMP ("stellar-iscc-" + [guid]::NewGuid().ToString("N"))
    $InstallerStageBase = "StellarSetup-$Version-staged"
    $InstallerStageExe  = Join-Path $InstallerStageRoot ($InstallerStageBase + ".exe")
    New-Item -ItemType Directory -Force -Path $InstallerStageRoot | Out-Null

    if (Test-Path $InstallerExe) {
        try {
            Remove-Item -LiteralPath $InstallerExe -Force -ErrorAction Stop
        } catch {
            $backupName = "StellarSetup-$Version.preexisting-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".exe"
            $backupPath = Join-Path $InstallerOut $backupName
            Move-Item -LiteralPath $InstallerExe -Destination $backupPath -Force
        }
    }

    & $ISCC `
        "/DAppVersion=$Version" `
        "/DOutputDirOverride=$InstallerStageRoot" `
        "/DOutputBaseFilenameOverride=$InstallerStageBase" `
        "$InstallerDir\installer.iss"
    if ($LASTEXITCODE -ne 0) { Write-Error "Inno Setup build failed" }

    if (-not (Test-Path $InstallerStageExe)) {
        Write-Error "Inno Setup reported success, but no installer was produced at $InstallerStageExe"
    }
    Copy-Item -LiteralPath $InstallerStageExe -Destination $InstallerExe -Force
    Remove-Item -LiteralPath $InstallerStageRoot -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "[release] Installer: $InstallerExe" -ForegroundColor Green
} else {
    Write-Host "[release] Skipping installer." -ForegroundColor DarkGray
}

Write-Host "`n[release] === Windows release complete ===" -ForegroundColor Green
Write-Host "  Installer : $InstallerExe"
Write-Host "  dist/     : $DistDir"
