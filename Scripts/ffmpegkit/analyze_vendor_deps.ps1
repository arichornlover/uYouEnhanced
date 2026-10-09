# analyze_vendor_deps.ps1
# Parse the Mach-O load commands of every Vendor/*.framework binary and print
# each one's dylib dependencies, then compute the transitive dependency
# closure starting from ffmpegkit.framework.
#
# Usage: powershell -File Scripts\analyze_vendor_deps.ps1   (from repo root)
$ErrorActionPreference = 'Stop'
  return [uint32]($b[$o] -bor ($b[$o+1] -shl 8) -bor ($b[$o+2] -shl 16) -bor ($b[$o+3] -shl 24))
}

function Get-MachoDeps([byte[]]$b) {
  $deps = New-Object System.Collections.Generic.List[string]
  $magic = ReadU32 $b 0
  $offsets = @()
  if ($magic -eq 0xFEEDFACF) { $offsets = @(32) }
  elseif ($magic -eq 0xBEBAFECA) {
    $nfat = [int](ReadU32 $b 4)
    for ($i = 0; $i -lt $nfat; $i++) {
      $o = 8 + $i * 20
      if ((ReadU32 $b $o) -eq 0x0100000C) { $offsets += @(ReadU32 $b ($o + 8)); break }
    }
  }
  foreach ($off in $offsets) {
    if ($off + 32 -gt $b.Length) { continue }
    $ncmds = [int](ReadU32 $b ($off + 16))
    $p = $off + 32
    for ($c = 0; $c -lt $ncmds; $c++) {
      if ($p + 8 -gt $b.Length) { break }
      $cmd = ReadU32 $b $p
      $cmdsize = [int](ReadU32 $b ($p + 4))
      if ($cmdsize -le 0 -or $p + $cmdsize -gt $b.Length) { break }
      if ($cmd -in 0xC, 0x18, 0x1F) {
        $nameOff = [int](ReadU32 $b ($p + 8))
        $s = $p + $nameOff; $e = $s
        while ($e -lt $b.Length -and $b[$e] -ne 0) { $e++ }
        $deps.Add([System.Text.Encoding]::ASCII.GetString($b, $s, $e - $s))
      }
      $p += $cmdsize
    }
  }
  return $deps
}

$map = @{}
Get-ChildItem "Vendor" -Directory | ForEach-Object {
  $name = $_.Name.Replace('.framework', '')
  $bin = Join-Path $_.FullName $name
  if (Test-Path $bin) { $map[$name] = Get-MachoDeps ([System.IO.File]::ReadAllBytes($bin)) }
}

Write-Output "=== All direct deps ==="
foreach ($k in ($map.Keys | Sort-Object)) {
  Write-Output "${k}:"
  foreach ($d in $map[$k]) { Write-Output "   -> $d" }
}

$keep = New-Object System.Collections.Generic.HashSet[string]
[void]$keep.Add('ffmpegkit')
$queue = New-Object System.Collections.Queue
$queue.Enqueue('ffmpegkit')
while ($queue.Count -gt 0) {
  $cur = $queue.Dequeue()
  foreach ($dep in $map[$cur]) {
    if ($dep -match '@rpath/([^.]+)\.framework') {
      $lib = $Matches[1]
      if (-not $keep.Contains($lib) -and $map.ContainsKey($lib)) {
        [void]$keep.Add($lib)
        $queue.Enqueue($lib)
      }
    }
  }
}
Write-Output "`n=== KEEP ==="
$keep | Sort-Object | ForEach-Object { Write-Output "  $_" }
Write-Output "`n=== DROP ==="
$map.Keys | Where-Object { -not $keep.Contains($_) } | Sort-Object | ForEach-Object { Write-Output "  $_" }
