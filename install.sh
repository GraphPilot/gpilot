#!/bin/sh
# gpilot installer. Usage: curl -fsSL get.graphpilot.io | sh
set -eu

REPO="GraphPilot/gpilot"
BIN="gpilot"
INSTALL_DIR="${GPILOT_INSTALL_DIR:-$HOME/.local/bin}"

err() { echo "error: $*" >&2; exit 1; }

os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Darwin) case "$arch" in
      arm64|aarch64) target="aarch64-apple-darwin" ;;
      x86_64) target="x86_64-apple-darwin" ;;
      *) err "unsupported macOS arch: $arch" ;;
    esac ;;
  Linux) case "$arch" in
      aarch64|arm64) target="aarch64-unknown-linux-musl" ;;
      x86_64) target="x86_64-unknown-linux-musl" ;;
      *) err "unsupported Linux arch: $arch" ;;
    esac ;;
  *) err "unsupported OS: $os (use install.ps1 on Windows, or Scoop)" ;;
esac

# Resolve latest version tag from the public repo. Accept an explicit override
# with or without a leading "v" (tags/releases are published as v<version>).
version="${GPILOT_VERSION:-}"
version="${version#v}"
if [ -z "$version" ]; then
  version=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$version" ] || err "could not resolve latest version"
fi

asset="gpilot-cli-${version}-${target}.tar.gz"
base="https://github.com/${REPO}/releases/download/v${version}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading ${asset}"
curl -fsSL "${base}/${asset}" -o "${tmp}/${asset}"
curl -fsSL "${base}/SHA256SUMS.txt" -o "${tmp}/SHA256SUMS.txt"

# Verify checksum (sha256sum on Linux, shasum on macOS).
expected=$(awk -v a="$asset" '$2==a {print $1}' "${tmp}/SHA256SUMS.txt")
[ -n "$expected" ] || err "checksum for ${asset} not found"
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "${tmp}/${asset}" | awk '{print $1}')
else
  actual=$(shasum -a 256 "${tmp}/${asset}" | awk '{print $1}')
fi
[ "$expected" = "$actual" ] || err "checksum mismatch for ${asset}"

tar -xzf "${tmp}/${asset}" -C "$tmp"
mkdir -p "$INSTALL_DIR"
install -m 0755 "${tmp}/${BIN}" "${INSTALL_DIR}/${BIN}"
echo "Installed ${BIN} ${version} to ${INSTALL_DIR}/${BIN}"

case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) echo "note: ${INSTALL_DIR} is not on your PATH. Add it, e.g.: export PATH=\"${INSTALL_DIR}:\$PATH\"" ;;
esac
