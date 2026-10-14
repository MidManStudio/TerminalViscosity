# Architecture

## Overview

Terminal Viscosity is a multiplayer-first 3D game about hurling chemical water balloons. This repository holds the Rust simulation, the Odin and raylib client, and the tooling around them.

```
client (Odin + raylib)           crates (Rust)
  window, input, shaders  --->   tv_ffi    C ABI, static library
  soft-body jiggle (local)       tv_sim    deterministic fixed-step world
                                 tv_proto  wire protocol, art codec
                                 tv_server headless binary (self-test only so far)
```

The dependency direction is `tv_ffi` and `tv_server` on `tv_sim`, and `tv_sim` on `tv_proto`. `tv_proto` depends on nothing.

## Multiplayer first

Multiplayer-first here means the simulation boundary is shaped like a network protocol from the start: commands go in, snapshots and events come out, and nothing else crosses. Sockets come later. A local single-player session runs the same code in the same process, and a dedicated server runs it behind a transport.

The client does not sync soft-body nodes. It receives high-level balloon state and runs the jiggle itself. Detonations arrive as one event each.

Rules the code follows:
- Only the server's simulation is authoritative. Clients never decide a detonation.
- A snapshot always fits one 1200-byte datagram. A test enforces it.
- Every decoder rejects malformed bytes without panicking.

## Layout

| Path | What lives there |
|---|---|
| `crates/tv_proto` | Wire messages and the art codec |
| `crates/tv_sim` | World, balloons, chemistry seam, RNG, test kit |
| `crates/tv_ffi` | C ABI and `include/tv.h` |
| `crates/tv_server` | Headless binary |
| `benches/` | Criterion benchmarks, own Cargo workspace |
| `android/` | Android manifest and the C shim that starts the Odin client |
| `client/` | Odin client, soft-body package, shaders, Odin benchmark |
| `scripts/` | Repo checks, benchmark tools, client build |
| `docs/` | This file, CI, benchmarks, open decisions, and `references/` |
| `.mdix/replacements/` | mdix-scaffold replacement manifest and archives |

Each crate and package keeps its own documentation file in its own `docs/` folder, as the documentation guidelines in `docs/references/guidelines/` require.

## Toolchains

- The game crates keep a Rust 1.75 floor and use no external dependencies. That is checked in CI on 1.75 and on stable.
- `benches/` needs a recent stable toolchain because of Criterion. It is its own workspace so it never enters the root lockfile.
- `chemistry_core` from unity-chem-sim declares a Rust 1.83 floor. The cause is twenty `const` uses of `f32::from_bits` and `to_bits` inside its vendored mid-math, not an external dependency. See `docs/OPEN_DECISIONS.md`. Until that is patched, its adapter follows the same isolation pattern as `benches/`.
- The Odin version is pinned in CI.

## Modules

### `Cargo.toml`
**What it does:** Root workspace manifest.

**Decisions:**
- `resolver = "2"`, members listed explicitly, and `benches` excluded because it is a separate workspace.
- Lint table as in the Rust guidelines: `unsafe_code = "deny"`, `missing_docs = "warn"`, and `undocumented_unsafe_blocks = "warn"`. Every crate opts in with `[lints] workspace = true`. Only `tv_ffi` lifts the unsafe lint, in one line at its crate root.
- A `wasm-release` profile is defined for the browser build, with size optimization and fat LTO.
- No `[workspace.package]` table. The project is proprietary, see `LICENSE` at the repository root, and every crate sets `publish = false`.

### `rustfmt.toml`
**What it does:** Formatter settings. Edition 2021 and a 100 column limit. 100 is already the rustfmt default, and the file pins it so the limit is visible.

## CI and Workflows

See `docs/CI.md`.

## Fixes and Problems

### `Cargo.toml`
- None recorded yet.

### `rustfmt.toml`
- None recorded yet.
