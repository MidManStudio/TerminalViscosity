#!/usr/bin/env bash
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "build_client.sh"
# ============================================================================
# Builds the Rust static library, then the Odin client, then optionally runs
# the windowless self-test. Needs `cargo` and `odin` on PATH.
#
#   scripts/build_client.sh            build only
#   scripts/build_client.sh --selftest build, then run ./build/tv_client --selftest
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

cargo build --release -p tv_ffi
mkdir -p build
odin build client/src -out:build/tv_client -o:speed -vet -strict-style
rm -rf build/shaders
cp -r client/shaders build/shaders

if [[ "${1:-}" == "--selftest" ]]; then
    ./build/tv_client --selftest
fi
