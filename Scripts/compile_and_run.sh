#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/Purrr.app"

pkill -f "Purrr.app/Contents/MacOS/Purrr" 2>/dev/null || true
"$ROOT_DIR/Scripts/package_app.sh" debug
open -n "$APP_BUNDLE"

for _ in {1..12}; do
  if pgrep -f "Purrr.app/Contents/MacOS/Purrr" >/dev/null 2>&1; then
    echo "Purrr is running."
    exit 0
  fi
  sleep 0.5
done

echo "ERROR: Purrr exited immediately. Check Console.app for a crash report." >&2
exit 1
