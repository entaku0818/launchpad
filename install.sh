#!/bin/sh
# launchpad installer
# Usage: curl -fsSL https://raw.githubusercontent.com/entaku0818/launchpad/main/install.sh | sh

set -e

REPO="entaku0818/launchpad"
BINARY="launchpad"
INSTALL_DIR="/usr/local/bin"

# Detect latest version
VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "$VERSION" ]; then
  echo "Error: could not fetch latest release version." >&2
  exit 1
fi

TARBALL="${BINARY}-${VERSION}-macos.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${TARBALL}"
TMP_DIR=$(mktemp -d)

echo "Installing launchpad ${VERSION}..."

curl -fsSL "$URL" -o "${TMP_DIR}/${TARBALL}"
tar -xzf "${TMP_DIR}/${TARBALL}" -C "$TMP_DIR"

if [ ! -w "$INSTALL_DIR" ]; then
  sudo install -m 755 "${TMP_DIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
else
  install -m 755 "${TMP_DIR}/${BINARY}" "${INSTALL_DIR}/${BINARY}"
fi

rm -rf "$TMP_DIR"

echo "✓ launchpad ${VERSION} installed to ${INSTALL_DIR}/${BINARY}"
launchpad --version 2>/dev/null || true
