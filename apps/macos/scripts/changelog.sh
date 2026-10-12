#!/usr/bin/env bash
set -euo pipefail

TAG="$1"
PREVIOUS="$(git describe --tags --abbrev=0 --match 'v*' "$TAG^" 2>/dev/null || true)"
CHANGES="$(git log "${PREVIOUS:+$PREVIOUS..}$TAG" --format='- %s' | grep -Ev '^- (docs|chore|ci|test)(\([^)]*\))?!?:' || true)"
echo "${CHANGES:-- Maintenance release}"
