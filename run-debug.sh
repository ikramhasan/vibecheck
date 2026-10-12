#!/usr/bin/env bash
# Stops any running vibecheck (debug or installed), then builds and runs the debug app.
# Usage: ./run-debug.sh   (Ctrl-C quits the app)
set -euo pipefail
cd "$(dirname "$0")/apps/macos"

if pkill -x Vibecheck; then
  while pgrep -x Vibecheck >/dev/null; do sleep 0.1; done
fi

swift build
exec "$(swift build --show-bin-path)/Vibecheck"
