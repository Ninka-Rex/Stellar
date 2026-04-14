# Stellar Version Manager
# Bumps the project version in CMakeLists.txt and optionally creates a git tag.
#
# Usage:
#   .\version.ps1 patch          # 0.1.0 → 0.1.1
#   .\version.ps1 minor          # 0.1.1 → 0.2.0
#   .\version.ps1 major          # 0.2.0 → 1.0.0
#   .\version.ps1 set 1.2.3      # set exact version
#   .\version.ps1 show           # print current version
#   .\version.ps1 patch -Tag     # bump + create git tag v0.1.1
#   .\version.ps1 patch -NoBuild # bump only, skip cmake reconfigure

param(
    [Parameter(Position=0)] [string] $Command = "show",
    [Parameter(Position=1)] [string] $SetVersion = "",
    [switch] $Tag,
    [switch] $NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$cmake = Join-Path $PSScriptRoot "CMakeLists.txt"
$content = Get-Content $cmake -Raw

# Extract current version
if ($content -notmatch 'project\(Stellar VERSION (\d+)\.(\d+)\.(\d+)') {
    Write-Error "Could not find project version in CMakeLists.txt"
    exit 1
}
$major = [int]$Matches[1]
$minor = [int]$Matches[2]
$patch = [int]$Matches[3]
$current = "$major.$minor.$patch"

if ($Command -eq "show") {
    Write-Host "Current version: $current" -ForegroundColor Cyan
    exit 0
}

# Calculate new version
switch ($Command) {
    "patch" { $patch++; $minor = $minor; $major = $major }
    "minor" { $minor++; $patch = 0 }
    "major" { $major++; $minor = 0; $patch = 0 }
    "set"   {
        if ($SetVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
            Write-Error "Invalid version format. Use: .\version.ps1 set X.Y.Z"
            exit 1
        }
        $major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]
    }
    default { Write-Error "Unknown command '$Command'. Use: patch | minor | major | set | show"; exit 1 }
}

$newVersion = "$major.$minor.$patch"

if ($newVersion -eq $current) {
    Write-Host "Version unchanged: $current" -ForegroundColor Yellow
    exit 0
}

# Update CMakeLists.txt
$updated = $content -replace "project\(Stellar VERSION $([regex]::Escape($current))", "project(Stellar VERSION $newVersion"
Set-Content $cmake $updated -NoNewline

# Update Flatpak metainfo.xml - prepend a new <release> at the top of <releases>
# so Flathub and appstreamcli always see the latest version first.
$metainfo = Join-Path $PSScriptRoot "packaging/flatpak/io.github.stellar.Stellar.metainfo.xml"
if (Test-Path $metainfo) {
    $today = Get-Date -Format "yyyy-MM-dd"
    $xml = Get-Content $metainfo -Raw
    $newRelease = "    <release version=`"$newVersion`" date=`"$today`">`n      <description><p>Release $newVersion.</p></description>`n    </release>`n    "
    $xml = $xml -replace "(<releases>\s*\n\s*)", "`$1$newRelease"
    Set-Content $metainfo $xml -NoNewline
    Write-Host "Updated metainfo.xml -> $newVersion ($today)" -ForegroundColor Green
} else {
    Write-Warning "metainfo.xml not found at $metainfo - skipped"
}

Write-Host "$current -> $newVersion" -ForegroundColor Green

# Re-run cmake configure so AppVersion.h is regenerated with new version + fresh timestamp
if (-not $NoBuild) {
    Write-Host "Reconfiguring..." -ForegroundColor DarkGray
    Push-Location $PSScriptRoot
    # $ErrorActionPreference = "Stop" re-throws ErrorRecord objects that cmake
    # writes to stderr even when 2>&1 is used. Relax it for this call only.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $cmakeOut = & cmake --preset windows-debug 2>&1
    $cmakeExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    $cmakeOut | Where-Object { $_ -match "(Configuring|Warning|Error|error)" } | ForEach-Object { Write-Host $_ }
    if ($cmakeExit -ne 0) {
        Write-Warning "cmake configure exited with code $cmakeExit - check output above"
    }
    Pop-Location
}

# Git tag
if ($Tag) {
    $tagName = "v$newVersion"
    Write-Host "Creating git tag $tagName..." -ForegroundColor Cyan
    Push-Location $PSScriptRoot
    try {
        & git add CMakeLists.txt
        & git add packaging/flatpak/io.github.stellar.Stellar.metainfo.xml
        & git commit -m "chore: bump version to $newVersion"
        & git tag -a $tagName -m "Release $newVersion"
        Write-Host "Tagged $tagName" -ForegroundColor Green
    } catch {
        Write-Warning "Git operations failed (repo may not be initialised): $_"
    }
    Pop-Location
}

Write-Host ""
Write-Host "Done. Rebuild to pick up version $newVersion in the app." -ForegroundColor Cyan
Write-Host "  cmake --build --preset windows-debug"
