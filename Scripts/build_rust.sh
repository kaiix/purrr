#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_TARGET="aarch64-apple-darwin"

MACOSX_DEPLOYMENT_TARGET=14.0 cargo build \
  --manifest-path "$ROOT_DIR/Rust/PurrrSpeechBridge/Cargo.toml" \
  --release \
  --target "$RUST_TARGET"
