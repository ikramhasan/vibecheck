#!/usr/bin/env bash
# Syncs CodexBar's provider icons (MIT, © Peter Steinberger) into the app's resources.
# Pinned to the same release as the bundled CLI; re-run after bumping VERSION.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.73.0"
REPO="steipete/CodexBar"
SRC="Sources/CodexBar/Resources"
DEST="Sources/Vibecheck/Resources/ProviderIcons"

names=$(gh api "repos/$REPO/contents/$SRC?ref=v$VERSION" \
  -q '.[] | select(.name | test("^ProviderIcon-.*\\.svg$")) | .name')

rm -rf "$DEST"
mkdir -p "$DEST"
for name in $names; do
  curl -fsSL "https://raw.githubusercontent.com/$REPO/v$VERSION/$SRC/$name" -o "$DEST/$name"
done
curl -fsSL "https://raw.githubusercontent.com/$REPO/v$VERSION/LICENSE" -o "$DEST/LICENSE"
echo "$VERSION" > "$DEST/VERSION"
echo "Synced $(ls "$DEST"/*.svg | wc -l | tr -d ' ') icons from CodexBar v$VERSION"
