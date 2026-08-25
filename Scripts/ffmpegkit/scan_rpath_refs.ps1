# scan_rpath_refs.ps1
# Brute-force scan every Vendor/*.framework binary for @rpath/... references —
# quick cross-check of inter-framework dependencies.
#
# Usage: powershell -File Scripts\scan_rpath_refs.ps1   (from repo root)
Get-ChildItem "Vendor" -Directory | ForEach-Object {
  $name = $_.Name.Replace('.framework', '')
  $bin = Join-Path $_.FullName $name
  if (-not (Test-Path $bin)) { return }
  $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($bin))
  $refs = [regex]::Matches($text, '@rpath/[A-Za-z0-9_+.-]+\.framework/[A-Za-z0-9_+.-]+') |
          ForEach-Object { $_.Value } | Sort-Object -Unique
  Write-Output "== $name =="
  if ($refs) { $refs | ForEach-Object { Write-Output "   $_" } } else { Write-Output "   (none)" }
}
