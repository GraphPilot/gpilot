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

## Verify

    gpilot --version
