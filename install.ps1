# gpilot installer for Windows. Usage: irm get.graphpilot.io/install.ps1 | iex
$ErrorActionPreference = "Stop"
$repo = "GraphPilot/gpilot"
$installDir = if ($env:GPILOT_INSTALL_DIR) { $env:GPILOT_INSTALL_DIR } else { "$env:LOCALAPPDATA\gpilot\bin" }

$version = $env:GPILOT_VERSION
if (-not $version) {
  $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
  $version = $rel.tag_name -replace '^v',''
}
$asset = "gpilot-cli-$version-x86_64-pc-windows-msvc.zip"
$base  = "https://github.com/$repo/releases/download/v$version"
$tmp   = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([guid]::NewGuid()))

Write-Host "Downloading $asset"
Invoke-WebRequest "$base/$asset" -OutFile "$tmp\$asset"
Invoke-WebRequest "$base/SHA256SUMS.txt" -OutFile "$tmp\SHA256SUMS.txt"

$expected = (Select-String -Path "$tmp\SHA256SUMS.txt" -Pattern ([regex]::Escape($asset))).Line.Split(" ")[0]
$actual = (Get-FileHash "$tmp\$asset" -Algorithm SHA256).Hash.ToLower()
if ($expected -ne $actual) { throw "checksum mismatch for $asset" }

Expand-Archive "$tmp\$asset" -DestinationPath $installDir -Force
Write-Host "Installed gpilot $version to $installDir\gpilot.exe"
if (($env:Path -split ';') -notcontains $installDir) {
  Write-Host "note: $installDir is not on your PATH. Add it to use 'gpilot' directly."
}
