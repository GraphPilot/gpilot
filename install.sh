#!/bin/sh
# gpilot installer. Usage: curl --proto '=https' --tlsv1.2 -fsSL https://get.graphpilot.io | sh
#
# Integrity: the archive is checked against SHA256SUMS.txt, and SHA256SUMS.txt against its
# keyless Sigstore signature (SHA256SUMS.txt.sigstore.json) when cosign v2.5.0 or later is
# on the PATH. The signature proves the checksums came out of GraphPilot's release workflow
# at the tag of this version. Without cosign the script warns and relies on the checksum
# alone; it never downloads cosign itself.
#
# Make the signature mandatory (fail without cosign) with either of:
#   curl --proto '=https' --tlsv1.2 -fsSL https://get.graphpilot.io | sh -s -- --require-signature
#   curl --proto '=https' --tlsv1.2 -fsSL https://get.graphpilot.io | GPILOT_REQUIRE_SIGNATURE=1 sh
set -eu

REPO="GraphPilot/gpilot"
BIN="gpilot"
INSTALL_DIR="${GPILOT_INSTALL_DIR:-$HOME/.local/bin}"
# The certificate of every signed release names this workflow at the release's own tag.
SIGNER="https://github.com/GraphPilot/graphpilot-proxy/.github/workflows/release-cli.yml"
ISSUER="https://token.actions.githubusercontent.com"
SIGNED_SINCE="1.0.1" # releases before this one carry no signature
COSIGN_MIN="2.5.0"   # older cosign cannot read the Sigstore bundle v0.3 format
COSIGN_DOCS="https://docs.sigstore.dev/cosign/system_config/installation/"

err() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }

# version_lt A B: true when dotted version A sorts before B (numeric fields, suffixes ignored).
version_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, "."); n = (na > nb) ? na : nb
    for (i = 1; i <= n; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }
    exit 1 }'
}

require_sig="${GPILOT_REQUIRE_SIGNATURE:-0}"
for arg in "$@"; do
  case "$arg" in
    --require-signature) require_sig=1 ;;
    *) err "unknown option: $arg (supported: --require-signature)" ;;
  esac
done
case "$require_sig" in
  1|true|yes) require_sig=1 ;;
  0|false|no|"") require_sig=0 ;;
  *) err "GPILOT_REQUIRE_SIGNATURE must be 1 or 0, got: $require_sig" ;;
esac

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
bundle="SHA256SUMS.txt.sigstore.json"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading ${asset}"
curl -fsSL "${base}/${asset}" -o "${tmp}/${asset}"
curl -fsSL "${base}/SHA256SUMS.txt" -o "${tmp}/SHA256SUMS.txt"

# Verify the signature of SHA256SUMS.txt before trusting any checksum in it.
if [ "$version" = "main" ] || version_lt "$version" "$SIGNED_SINCE"; then
  # The main channel (GPILOT_VERSION=main) and releases before v1.0.1 are not signed.
  if [ "$version" = "main" ]; then why="the main channel is never signed"; else why="signed releases start at v${SIGNED_SINCE}"; fi
  [ "$require_sig" = 0 ] || err "gpilot ${version} is not signed (${why})"
  warn "gpilot ${version} is not signed (${why}); relying on SHA256SUMS.txt alone"
else
  # A signed release without its bundle is treated as tampered, with or without cosign.
  curl -fsSL "${base}/${bundle}" -o "${tmp}/${bundle}" \
    || err "${bundle} is missing from release v${version}; refusing to install"
  identity="${SIGNER}@refs/tags/gpilot-cli-v${version}"
  cosign_missing=""
  if ! command -v cosign >/dev/null 2>&1; then
    cosign_missing="cosign is not on the PATH"
  else
    cosign_version=$(cosign version 2>&1 | sed -n 's/^GitVersion: *v\{0,1\}\([0-9][0-9.]*\).*/\1/p' | head -n1)
    if [ -n "$cosign_version" ] && version_lt "$cosign_version" "$COSIGN_MIN"; then
      cosign_missing="cosign ${cosign_version} is older than ${COSIGN_MIN}"
    fi
  fi
  if [ -z "$cosign_missing" ]; then
    echo "Verifying the signature of SHA256SUMS.txt"
    if ! cosign verify-blob --bundle "${tmp}/${bundle}" \
        --certificate-identity "$identity" \
        --certificate-oidc-issuer "$ISSUER" \
        "${tmp}/SHA256SUMS.txt" >"${tmp}/cosign.log" 2>&1; then
      cat "${tmp}/cosign.log" >&2
      err "SHA256SUMS.txt of v${version} is not signed by ${identity}; refusing to install"
    fi
  elif [ "$require_sig" = 1 ]; then
    err "a signature is required, but ${cosign_missing}. Install cosign ${COSIGN_MIN} or later: ${COSIGN_DOCS}"
  else
    warn "${cosign_missing}, so the signature of SHA256SUMS.txt was NOT verified; relying on the checksum alone."
    warn "Install cosign (${COSIGN_DOCS}) and rerun with --require-signature, or verify the release files by hand:"
    cat >&2 <<EOF
  cosign verify-blob --bundle ${bundle} \\
    --certificate-identity ${identity} \\
    --certificate-oidc-issuer ${ISSUER} \\
    SHA256SUMS.txt
EOF
  fi
fi

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
