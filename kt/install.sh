#!/usr/bin/env bash
# kt install script. Downloads the latest kt release from fede-iglesias/tools
# and installs to $HOME/.local/bin/kt by default (user-scope, no sudo).
#
# Usage:
#   curl -fsSL https://github.com/fede-iglesias/tools/releases/download/kt-vX.Y.Z/install.sh | bash
#
# Override the install directory (writes there instead of $HOME/.local/bin):
#   curl ... | KT_INSTALL_DIR=/usr/local/bin bash
#
# Skip the duplicate-binary check (re-install over an existing path elsewhere):
#   curl ... | KT_INSTALL_FORCE=1 bash
set -euo pipefail

REPO="fede-iglesias/tools"
BIN_NAME="kt"
INSTALL_DIR="${KT_INSTALL_DIR:-$HOME/.local/bin}"
FORCE="${KT_INSTALL_FORCE:-0}"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=30" \
  | grep -oE '"tag_name":[[:space:]]*"kt-v[^"]+"' \
  | head -1 \
  | sed 's/.*"kt-v\([^"]*\)".*/\1/')

if [ -z "$TAG" ]; then
  echo "no kt release found in $REPO" >&2
  exit 1
fi

# Detect kt binaries already on PATH that live outside the target INSTALL_DIR.
# Without this check, installing to ~/.local/bin while a stale /usr/local/bin/kt
# also exists leaves two kt binaries on PATH and `kt uninstall` later removes
# only the one resolved at exec time, leaving a ghost that the user can still
# invoke. Abort here so the user picks the right home before fragmenting state.
TARGET_PATH="$INSTALL_DIR/$BIN_NAME"
EXISTING=""
if command -v "$BIN_NAME" >/dev/null 2>&1; then
  if command -v which >/dev/null 2>&1; then
    EXISTING=$(which -a "$BIN_NAME" 2>/dev/null | grep -v "^$TARGET_PATH\$" || true)
  fi
fi
if [ -n "$EXISTING" ] && [ "$FORCE" != "1" ]; then
  echo "kt already on PATH at:" >&2
  echo "$EXISTING" | sed 's/^/  /' >&2
  echo "" >&2
  echo "Installing to $TARGET_PATH would leave multiple kt binaries on PATH." >&2
  echo "Remove the existing one(s) first, or set KT_INSTALL_FORCE=1 to install anyway." >&2
  exit 1
fi

echo "installing kt v$TAG for $OS/$ARCH to $INSTALL_DIR..."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

mkdir -p "$INSTALL_DIR"
if [ -w "$INSTALL_DIR" ] || [ ! -e "$INSTALL_DIR" ]; then
  install -m 755 "$TMP/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
else
  sudo install -m 755 "$TMP/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
fi

if [ "$OS" = "darwin" ]; then
  xattr -d com.apple.quarantine "$INSTALL_DIR/$BIN_NAME" 2>/dev/null || true
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo ""
    echo "WARNING: $INSTALL_DIR is not on your PATH." >&2
    echo "Add this to your shell profile (~/.zprofile, ~/.bashrc, etc.):" >&2
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\"" >&2
    echo ""
    ;;
esac

echo "kt installed: $($INSTALL_DIR/$BIN_NAME --version)"
