#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_TARGET="aarch64-apple-darwin"

# audiopus_sys otherwise falls back to bundled Opus with obsolete CMake policies.
if ! command -v pkg-config >/dev/null 2>&1 || ! pkg-config --exists opus; then
  echo "ERROR: Opus and pkg-config are required. Install them with: brew install opus pkgconf" >&2
  exit 1
fi
OPUS_LIBRARY_DIR="$(pkg-config --variable=libdir opus)"
if [[ ! -f "$OPUS_LIBRARY_DIR/libopus.a" ]]; then
  echo "ERROR: Missing static Opus library at $OPUS_LIBRARY_DIR/libopus.a" >&2
  exit 1
fi

MACOSX_DEPLOYMENT_TARGET=14.0 cargo build \
  --manifest-path "$ROOT_DIR/Rust/PurrrSpeechBridge/Cargo.toml" \
  --locked \
  --release \
  --target "$RUST_TARGET"
