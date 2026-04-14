@echo off
cd /d "%~dp0"
if exist firefox.zip del firefox.zip
powershell -Command ^
    "Add-Type -AssemblyName System.IO.Compression.FileSystem;" ^
    "$zip = [System.IO.Compression.ZipFile]::Open('firefox.zip', 'Create');" ^
    "$files = @('content.js','service-worker.js','manifest.json','popup.html','popup.js');" ^
    "foreach ($f in $files) { [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f, $f) | Out-Null };" ^
    "Get-ChildItem icons | ForEach-Object { [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, 'icons/' + $_.Name) | Out-Null };" ^
    "$zip.Dispose()"
echo Done: firefox.zip created.
