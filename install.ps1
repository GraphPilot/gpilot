# gpilot installer for Windows. Usage: irm https://get.graphpilot.io/install.ps1 | iex
#
# Integrity: the archive is checked against SHA256SUMS.txt, and SHA256SUMS.txt against its
# keyless Sigstore signature (SHA256SUMS.txt.sigstore.json) when cosign v2.5.0 or later is
# on the PATH. The signature proves the checksums came out of GraphPilot's release workflow
# at the tag of this version. Without cosign the script warns and relies on the checksum
# alone; it never downloads cosign itself.
#
# Make the signature mandatory (fail without cosign):
#   $env:GPILOT_REQUIRE_SIGNATURE = "1"; irm https://get.graphpilot.io/install.ps1 | iex
$ErrorActionPreference = "Stop"
$repo = "GraphPilot/gpilot"
$installDir = if ($env:GPILOT_INSTALL_DIR) { $env:GPILOT_INSTALL_DIR } else { "$env:LOCALAPPDATA\gpilot\bin" }
# The certificate of every signed release names this workflow at the release's own tag.
$signer = "https://github.com/GraphPilot/graphpilot-proxy/.github/workflows/release-cli.yml"
$issuer = "https://token.actions.githubusercontent.com"
$signedSince = [version]"1.0.1" # releases before this one carry no signature
$cosignMin = [version]"2.5.0"   # older cosign cannot read the Sigstore bundle v0.3 format
$cosignDocs = "https://docs.sigstore.dev/cosign/system_config/installation/"

# Dotted numeric version, suffixes ignored; $null when it is not one (e.g. "main").
function ConvertTo-Version([string]$v) {
  $core = ($v -replace '^v', '') -replace '[-+].*$', ''
  if ($core -notmatch '^\d+(\.\d+){1,3}$') { return $null }
  return [version]$core
}

$requireSig = switch ("$env:GPILOT_REQUIRE_SIGNATURE") {
  { $_ -in "1", "true", "yes" } { $true; break }
  { $_ -in "", "0", "false", "no" } { $false; break }
  default { throw "GPILOT_REQUIRE_SIGNATURE must be 1 or 0, got: $env:GPILOT_REQUIRE_SIGNATURE" }
}

$version = $env:GPILOT_VERSION -replace '^v',''
if (-not $version) {
  $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
  $version = $rel.tag_name -replace '^v',''
}
$asset = "gpilot-cli-$version-x86_64-pc-windows-msvc.zip"
$base  = "https://github.com/$repo/releases/download/v$version"
$bundle = "SHA256SUMS.txt.sigstore.json"
$tmp   = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([guid]::NewGuid()))

Write-Host "Downloading $asset"
Invoke-WebRequest "$base/$asset" -OutFile "$tmp\$asset"
Invoke-WebRequest "$base/SHA256SUMS.txt" -OutFile "$tmp\SHA256SUMS.txt"

# Verify the signature of SHA256SUMS.txt before trusting any checksum in it.
$parsed = ConvertTo-Version $version
if ($version -eq "main" -or ($parsed -and $parsed -lt $signedSince)) {
  # The main channel (GPILOT_VERSION=main) and releases before v1.0.1 are not signed.
  $why = if ($version -eq "main") { "the main channel is never signed" } else { "signed releases start at v$signedSince" }
  if ($requireSig) { throw "gpilot $version is not signed ($why)" }
  Write-Warning "gpilot $version is not signed ($why); relying on SHA256SUMS.txt alone"
} else {
  # A signed release without its bundle is treated as tampered, with or without cosign.
  try { Invoke-WebRequest "$base/$bundle" -OutFile "$tmp\$bundle" }
  catch { throw "$bundle is missing from release v${version}; refusing to install" }
  $identity = "$signer@refs/tags/gpilot-cli-v$version"
  $cosignMissing = $null
  if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) {
    $cosignMissing = "cosign is not on the PATH"
  } else {
    # cosign writes to stderr; under "Stop", Windows PowerShell 5.1 would turn that into a
    # terminating error, so native calls run under "Continue" and are judged by exit code.
    $ErrorActionPreference = "Continue"
    $cosignVersion = (& cosign version 2>&1 | Out-String) -replace '(?s).*GitVersion:\s*v?([0-9][0-9.]*).*', '$1'
    $ErrorActionPreference = "Stop"
    $cv = ConvertTo-Version $cosignVersion
    if ($cv -and $cv -lt $cosignMin) { $cosignMissing = "cosign $cosignVersion is older than $cosignMin" }
  }
  if (-not $cosignMissing) {
    Write-Host "Verifying the signature of SHA256SUMS.txt"
    $ErrorActionPreference = "Continue"
    $log = & cosign verify-blob --bundle (Join-Path $tmp $bundle) `
      --certificate-identity $identity `
      --certificate-oidc-issuer $issuer `
      (Join-Path $tmp "SHA256SUMS.txt") 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($code -ne 0) {
      Write-Host $log
      throw "SHA256SUMS.txt of v$version is not signed by $identity; refusing to install"
    }
  } elseif ($requireSig) {
    throw "a signature is required, but $cosignMissing. Install cosign $cosignMin or later: $cosignDocs"
  } else {
    Write-Warning "$cosignMissing, so the signature of SHA256SUMS.txt was NOT verified; relying on the checksum alone."
    Write-Warning "Install cosign ($cosignDocs) and rerun with GPILOT_REQUIRE_SIGNATURE=1, or verify the release files by hand:"
    Write-Host "  cosign verify-blob --bundle $bundle ``"
    Write-Host "    --certificate-identity $identity ``"
    Write-Host "    --certificate-oidc-issuer $issuer ``"
    Write-Host "    SHA256SUMS.txt"
  }
}

$match = Select-String -Path "$tmp\SHA256SUMS.txt" -Pattern ([regex]::Escape($asset))
if (-not $match) { throw "checksum for $asset not found" }
$expected = $match.Line.Split(" ")[0]
$actual = (Get-FileHash "$tmp\$asset" -Algorithm SHA256).Hash.ToLower()
if ($expected -ne $actual) { throw "checksum mismatch for $asset" }

Expand-Archive "$tmp\$asset" -DestinationPath $installDir -Force
Write-Host "Installed gpilot $version to $installDir\gpilot.exe"
if (($env:Path -split ';') -notcontains $installDir) {
  Write-Host "note: $installDir is not on your PATH. Add it to use 'gpilot' directly."
}
