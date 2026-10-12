#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../DiffViewer"
npm ci --ignore-scripts --no-audit --no-fund
npx tsc -p .
npm run build
