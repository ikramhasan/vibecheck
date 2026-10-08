#!/usr/bin/env bash
# Downloads the pinned CodexBar CLI release into apps/macos/vendor/codexbar (cached).
# The binary is not committed; bundle.sh calls this. Bump VERSION + SHA256 together.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.73.0"
case "$(uname -m)" in
  arm64)  ARCH="arm64";  SHA256="cd8f853779f8faec003f53d5fc2a1614aef577ec9f603cbd58a9559b54e159b9" ;;
  x86_64) ARCH="x86_64"; SHA256="19e7059de688e62be98790bc10198257f5d326e4a3f4191183c23106eb91780a" ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

DEST="vendor/codexbar"
if [[ -x "$DEST/CodexBarCLI" && "$(cat "$DEST/VERSION" 2>/dev/null)" == "$VERSION" ]]; then
  exit 0
fi

TARBALL="CodexBarCLI-v${VERSION}-macos-${ARCH}.tar.gz"
URL="https://github.com/steipete/CodexBar/releases/download/v${VERSION}/${TARBALL}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Fetching CodexBar CLI ${VERSION} (${ARCH})…"
curl -fsSL "$URL" -o "$TMP/$TARBALL"
echo "${SHA256}  $TMP/$TARBALL" | shasum -a 256 -c - >/dev/null \
  || { echo "Checksum mismatch for $TARBALL" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"
tar -xzf "$TMP/$TARBALL" -C "$DEST"
# The tarball ships CodexBarCLI, its resource bundle, VERSION and a `codexbar` symlink.
rm -f "$DEST/codexbar"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
echo "CodexBar CLI ${VERSION} ready in $(pwd)/$DEST"
