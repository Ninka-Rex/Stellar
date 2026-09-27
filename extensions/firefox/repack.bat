@echo off
cd /d "%~dp0"
rem extensions\shared is the source of truth; refresh this package's copy first.
python ..\sync_shared.py || exit /b 1
if exist firefox.zip del firefox.zip
powershell -NoProfile -Command ^
    "Add-Type -AssemblyName System.IO.Compression.FileSystem;" ^
    "$zip = [System.IO.Compression.ZipFile]::Open('firefox.zip', 'Create');" ^
    "foreach ($f in @('service-worker.js','manifest.json')) { [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f, $f) | Out-Null };" ^
    "foreach ($dir in @('icons','shared')) { Get-ChildItem $dir -Recurse -File | ForEach-Object { $rel = $dir + '/' + $_.FullName.Substring((Resolve-Path $dir).Path.Length + 1).Replace('\','/'); [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel) | Out-Null } };" ^
    "$zip.Dispose()"
echo Done: firefox.zip created.
