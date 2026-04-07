# Stellar Download Manager — Windows release script
# Usage:  .\release.ps1 [-Version "0.2.0"] [-QtDir "C:\Qt\6.8.x\msvc2022_64"] [-SkipBuild] [-SkipInstaller] [-SkipArchive]
#
# Prerequisites (must be on PATH or provided via -QtDir):
#   - CMake + Ninja
#   - Qt 6.8 MSVC build (windeployqt)
#   - Inno Setup 6  (iscc.exe)
#   - 7-Zip          (7z.exe)
#
# Output:
#   dist\windows\StellarSetup-<Version>.exe
#   releases\Stellar-<Version>-windows-installer.7z
#   releases\Stellar-<Version>-source.7z

param(
    [string]$Version    = "",           # auto-detected from CMakeLists.txt if omitted
    [string]$QtDir      = "",           # e.g. C:\Qt\6.8.3\msvc2022_64
    [switch]$SkipBuild,
    [switch]$SkipInstaller,
    [switch]$SkipArchive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root       = $PSScriptRoot
$BuildDir   = "$Root\build\windows-release"
$DistDir    = "$Root\dist"
$WinDistDir = "$DistDir\windows"
$ReleasesDir = "$Root\releases"

# ── Auto-detect version from CMakeLists.txt ──────────────────────────────────
if ($Version -eq "") {
    $cmakeFile = Get-Content "$Root\CMakeLists.txt" -Raw
    if ($cmakeFile -match 'project\s*\(\s*\w+\s+VERSION\s+([\d]+\.[\d]+\.[\d]+(?:\.[\d]+)?)') {
        $Version = $Matches[1]
        Write-Host "[release] Detected version: $Version" -ForegroundColor Cyan
    } else {
        Write-Error "Could not detect version from CMakeLists.txt. Pass -Version explicitly."
    }
}

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

    & $ISCC `
        "/DAppVersion=$Version" `
        "$InstallerDir\installer.iss"
    if ($LASTEXITCODE -ne 0) { Write-Error "Inno Setup build failed" }

    Write-Host "[release] Installer: $InstallerExe" -ForegroundColor Green
} else {
    Write-Host "[release] Skipping installer." -ForegroundColor DarkGray
}

# ── 7-Zip archives (all build steps done — archive everything now) ─────────────
if (-not $SkipArchive) {
    New-Item -ItemType Directory -Force -Path $DistDir     | Out-Null
    New-Item -ItemType Directory -Force -Path $WinDistDir  | Out-Null
    New-Item -ItemType Directory -Force -Path $ReleasesDir | Out-Null

    # Archive 1: installer
    if (Test-Path $InstallerExe) {
        Copy-Item $InstallerExe $WinDistDir -Force
        $InstallerArchive = "$ReleasesDir\Stellar-$Version-windows-installer.7z"
        Write-Host "`n[release] Archiving installer -> $InstallerArchive" -ForegroundColor Yellow
        & $7Z a -t7z -mx=9 -mmt=on $InstallerArchive "$WinDistDir\StellarSetup-$Version.exe"
        if ($LASTEXITCODE -ne 0) { Write-Error "7-Zip archive (installer) failed" }
    } else {
        Write-Host "[release] No installer at $InstallerExe - skipping installer archive." -ForegroundColor DarkGray
    }

    # Archive 2: source code
    $SourceArchive = "$ReleasesDir\Stellar-$Version-source.7z"
    Write-Host "[release] Archiving source -> $SourceArchive" -ForegroundColor Yellow
    & $7Z a -t7z -mx=9 -mmt=on `
        -xr"!build" `
        -xr"!dist" `
        -xr"!releases" `
        -xr"!backups" `
        -xr"!.git\objects" `
        -xr"!*.stellar-part-*" `
        -xr"!*.stellar-meta" `
        $SourceArchive "$Root\*"
    if ($LASTEXITCODE -ne 0) { Write-Error "7-Zip archive (source) failed" }

    Write-Host "[release] Archives done." -ForegroundColor Green
} else {
    Write-Host "[release] Skipping archives." -ForegroundColor DarkGray
}

Write-Host "`n[release] === Windows release $Version complete ===" -ForegroundColor Green
Write-Host "  Installer : $InstallerExe"
Write-Host "  releases/ : $ReleasesDir"
