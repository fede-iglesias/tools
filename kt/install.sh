#!/usr/bin/env bash
# kt install script. Downloads latest kt release from this repo and installs to /usr/local/bin/kt.
# Usage: curl -fsSL https://raw.githubusercontent.com/fede-iglesias/tools/main/kt/install.sh | bash
set -euo pipefail

REPO="fede-iglesias/tools"
BIN_NAME="kt"
INSTALL_DIR="${KT_INSTALL_DIR:-/usr/local/bin}"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

# Filter kt-v* releases, pick latest (most recent published_at)
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=30" \
  | grep -oE '"tag_name":[[:space:]]*"kt-v[^"]+"' \
  | head -1 \
  | sed 's/.*"kt-v\([^"]*\)".*/\1/')

if [ -z "$TAG" ]; then
  echo "no kt release found in $REPO" >&2
  exit 1
fi

echo "installing kt v$TAG for $OS/$ARCH..."

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

ASSET="kt_${TAG}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/$REPO/releases/download/kt-v$TAG/$ASSET"

curl -fsSL -o "$TMP/$ASSET" "$URL"

if command -v cosign >/dev/null 2>&1; then
  echo "verifying cosign signature..."
  curl -fsSL -o "$TMP/$ASSET.bundle" "$URL.bundle"
  cosign verify-blob \
    --certificate-identity-regexp 'https://github\.com/fede-iglesias/kt/.*' \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    --bundle "$TMP/$ASSET.bundle" \
    "$TMP/$ASSET" >/dev/null
  echo "signature verified"
else
  echo "cosign not present, skipping signature verification"
fi

tar -xzf "$TMP/$ASSET" -C "$TMP"

if [ -w "$INSTALL_DIR" ]; then
  install -m 755 "$TMP/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
else
  sudo install -m 755 "$TMP/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
fi

if [ "$OS" = "darwin" ]; then
  xattr -d com.apple.quarantine "$INSTALL_DIR/$BIN_NAME" 2>/dev/null || true
fi

echo "kt installed: $($INSTALL_DIR/$BIN_NAME --version)"
