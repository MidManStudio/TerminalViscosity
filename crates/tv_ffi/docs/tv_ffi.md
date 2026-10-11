# tv_ffi

## Overview

C ABI over the simulation, built as a static library for the Odin client. The header is `include/tv.h`.

Every function checks pointers for null, checks buffer sizes before copying, and turns a Rust panic into `TV_ERR_PANIC` instead of unwinding into the caller. Data crosses the boundary as wire bytes from `tv_proto` plus a few small `repr(C)` view structs, so the layout surface stays tiny.

## Modules

### `Cargo.toml`
**What it does:** Builds both a `staticlib` for Odin and an `rlib` so the Rust tests can call the same functions.

### `lib.rs`
**What it does:** All exported functions, the view structs, and the error codes.

**Decisions:**
- The crate sets `#![allow(unsafe_code)]`, the one place the workspace lint is lifted, as the Rust guidelines describe. Raw-pointer handling lives in two small helpers, `bytes_in` and `bytes_out`, so most unsafe blocks are one line each, and every block has a `// SAFETY:` note.
- Commands go in as encoded bytes (`tv_encode_throw`, then `tv_world_submit`) so the Odin side never builds a Rust enum.
- Snapshots and events come out as bytes and are decoded into arrays of view structs in one call, which avoids per-item calls and repeated decoding.
- `tv_world_take_events` keeps the events if the output buffer is too small.
- The world uses `NullChem` for now. A chemistry-backed constructor arrives with the chemistry adapter.
- Struct sizes are exported (`tv_sizeof_*`) so the client can assert its own layouts at startup.

### `tv.h`
**What it does:** C declarations, error codes, struct layouts, and size constants.

**Decisions:** Written by hand. `cbindgen` would add a build dependency for a header this small. `ffi_tests.rs` guards against drift.

### `ffi_tests.rs`
**What it does:** A full cycle through the C ABI, hash equality between identical worlds, null and bad-input handling, and a header check: constants and struct sizes match, and every exported function is declared in `tv.h`.

## CI and Workflows

- `.github/workflows/ci.yml` job `rust` runs these tests. Job `odin` links the static library into the client and runs `tv_client --selftest`, which checks the ABI from the Odin side.

## Fixes and Problems

### `lib.rs`
- None recorded yet.

### `tv.h`
- None recorded yet.
