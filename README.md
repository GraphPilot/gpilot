# GraphPilot CLI (`gpilot`)

## Install

### Homebrew (macOS, Linux)

    brew install graphpilot/tap/gpilot

### Scoop (Windows)

    scoop bucket add graphpilot https://github.com/GraphPilot/gpilot
    scoop install gpilot

### Shell one-liner (macOS, Linux)

    curl -fsSL get.graphpilot.io | sh

### PowerShell (Windows)

    irm get.graphpilot.io/install.ps1 | iex

### Manual download

Grab a tarball/zip from [Releases](https://github.com/GraphPilot/gpilot/releases).
On macOS, a browser download is quarantined; clear it once with:

    xattr -dr com.apple.quarantine ./gpilot

(Not needed when installing via Homebrew or the shell one-liner.)

## Verify a download

Every release from v1.0.1 on ships `SHA256SUMS.txt.sigstore.json`, a keyless
[Sigstore](https://www.sigstore.dev/) signature of `SHA256SUMS.txt` made by GraphPilot's
release workflow at the release tag. Check the signature with
[cosign](https://docs.sigstore.dev/cosign/system_config/installation/) v2.5.0 or later, then
the archive against the checksums:

    VERSION=1.0.2
    cosign verify-blob --bundle SHA256SUMS.txt.sigstore.json \
      --certificate-identity "https://github.com/GraphPilot/graphpilot-proxy/.github/workflows/release-cli.yml@refs/tags/gpilot-cli-v${VERSION}" \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      SHA256SUMS.txt
    sha256sum --check --ignore-missing SHA256SUMS.txt

The install scripts do the same: with cosign v2.5.0 or later on the PATH they verify the
signature and refuse to install on a mismatch; without it they print a warning and rely on
the checksum alone. To make the signature mandatory:

    curl -fsSL get.graphpilot.io | sh -s -- --require-signature
    $env:GPILOT_REQUIRE_SIGNATURE = "1"; irm get.graphpilot.io/install.ps1 | iex

Then check the installed binary:

    gpilot --version
