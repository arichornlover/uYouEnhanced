# generate_framework_plists.ps1
# Generate a minimal Info.plist (CFBundleExecutable/PackageType=FMWK) for any
# Vendor/*.framework missing one — signing tools expect it to exist.
#
# Usage: powershell -File Scripts\generate_framework_plists.ps1   (from repo root)
$ErrorActionPreference = 'Stop'

Get-ChildItem "Vendor" -Directory | Where-Object {
  -not (Test-Path (Join-Path $_.FullName "Info.plist"))
} | ForEach-Object {
  $name = $_.Name.Replace('.framework', '')
  $lines = @(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    '<plist version="1.0">'
    '<dict>'
    "	<key>CFBundleIdentifier</key>"
    "	<string>org.ffmpegkit.$name</string>"
    "	<key>CFBundleName</key>"
    "	<string>$name</string>"
    "	<key>CFBundleExecutable</key>"
    "	<string>$name</string>"
    "	<key>CFBundlePackageType</key>"
    "	<string>FMWK</string>"
    "	<key>CFBundleShortVersionString</key>"
    "	<string>9.0.0</string>"
    "	<key>CFBundleVersion</key>"
    "	<string>9.0.0</string>"
    "	<key>MinimumOSVersion</key>"
    "	<string>12.1</string>"
    '</dict>'
    '</plist>'
  )
  Set-Content -Path (Join-Path $_.FullName "Info.plist") -Value $lines -Encoding Ascii
  Write-Output "plist created: $name"
}

$files = Get-ChildItem "Vendor" -Recurse -File
Write-Output ("FINAL: {0} files, {1:N1} MB" -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB))
