# slim_vendor.ps1
# Strip Vendor/*.framework down to runtime essentials: removes nested duplicate
# frameworks, Headers/, Modules/, PrivateHeaders/, and stray files. Keeps the
# binary, Info.plist, and LICENSE per framework.
#
# Usage: powershell -File Scripts\slim_vendor.ps1   (from repo root)
$ErrorActionPreference = 'Stop'
$before = Get-ChildItem "Vendor" -Recurse -File
$beforeCount = $before.Count
$beforeSize = ($before | Measure-Object Length -Sum).Sum

Get-ChildItem "Vendor" -Directory | ForEach-Object {
  $fw = $_
  $binName = $fw.Name.Replace('.framework', '')

  # 1. Remove nested duplicated .framework folders (double-copy artifacts)
  Get-ChildItem $fw.FullName -Recurse -Directory -Filter "*.framework" |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

  # 2. Remove compile-time-only directories
  foreach ($dir in @("Headers", "Modules", "PrivateHeaders")) {
    $p = Join-Path $fw.FullName $dir
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
  }

  # 3. Remove everything that is NOT: the root binary, Info.plist, or a LICENSE
  Get-ChildItem $fw.FullName -File |
    Where-Object { $_.Name -ne $binName -and $_.Name -ne "Info.plist" -and $_.Name -notlike "LICENSE*" } |
    Remove-Item -Force

  # 4. Remove now-empty subdirectories
  Get-ChildItem $fw.FullName -Directory -Recurse |
    Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { (Get-ChildItem $_.FullName -Force).Count -eq 0 } |
    Remove-Item -Force

  $bin = Join-Path $fw.FullName $binName
  $ok = Test-Path $bin
  "{0,-28} binary:{1}  files:{2}" -f $fw.Name, $ok, (Get-ChildItem $fw.FullName -Recurse -File).Count
}

$after = Get-ChildItem "Vendor" -Recurse -File
"{0}`nBEFORE: {1} files, {2:N1} MB`nAFTER:  {3} files, {4:N1} MB" -f `
  ("-" * 40), $beforeCount, ($beforeSize / 1MB), $after.Count, (($after | Measure-Object Length -Sum).Sum / 1MB)
