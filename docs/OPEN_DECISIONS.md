# Decisions

## Decided

- **License.** Proprietary. Copyright (c) 2026 MidManStudio, all rights reserved. The full text is in `LICENSE`.
- **Scope for now.** The balloon-editing side only: crafting, compartments, the jiggle, and painting. The arena and the match flow wait.
- **Compounds.** They are defined in this game. The compound list from the grand-theft-grimoire project is a different game's and is not needed.
- **Chemistry.** Treated as finished and well optimised. This repo does not redo it. It only needs an adapter behind `ChemBackend` in `tv_sim`.
- **Networking.** Finish `mid-net` instead of adopting ENet. It is reusable in other projects. What exists today is described under Open, below.
- **Balloon art.** The canvas is 256 by 256 with a 16-colour palette, and nothing filters what players draw. That is intentional.
- **Android.** Required, not optional. The details and requirements are in `docs/ANDROID.md`.

## Open

### Chemistry integration

- **Which level a balloon uses.** `chemistry_core` in unity-chem-sim is an atom-level simulation behind a handle-based C API. `nuclear_core` works on macroscopic samples. A balloon needs a compound-level answer, which `ChemBackend` expects. A table of compounds written for this game, plus adapters over the two crates where they help, would fit.
- **The Rust floor of `chemistry_core`.** It is declared as 1.83, and it has no heavy dependencies. The cause is twenty `const` uses of `f32::from_bits` (18) and `to_bits` (2) in its vendored mid-math: `f32::from_bits` only became a const fn in Rust 1.83. In a scratch copy, replacing those twenty sites with `transmute` (const-stable since 1.56) let mid-math, `chemistry_core`, `nuclear_core`, and `mid-collections` all compile on Rust 1.75, and the library tests (873 across the four crates) passed identically on Rust 1.91 before and after. The remaining external crates are `lazy_static` on non-wasm targets and `criterion` for benches. Until mid-math is patched upstream, an adapter would live outside the root workspace, the way `benches/` does. The patch is delivered separately as `mid-math-const-bits.patch`.
- **mid-math in this repo.** Not used. `tv_sim` does its vector arithmetic on plain `[f32; 3]` arrays and has no dependencies. Adopting mid-math would be reasonable once the sim needs more than a few vector operations.

### Networking with mid-net

- **What exists.** Per its own doc: QUIC with unreliable datagrams for state and reliable streams for events, a hand-written wire format, a `Transport` trait with a loopback implementation, and a generic `Connection<T>`. The native backend over `quinn` compiled once on CI. The browser backend was written but has never compiled.
- **What is missing for this game.** Its C interface exposes only the packet codec, not `Connection`. The Odin client needs a concrete connection type behind C functions, because Rust generics cannot cross the boundary.
- **Fit.** Snapshots map to datagrams, and balloon art and one-time events map to reliable streams. That matches how the art canvas is now sized.
- **Untested.** `quinn` on 32-bit ARM Android has not been tried.

### Game rules that are still placeholders

- Total balloon volume (1000 ml), chamber count (4), the burst combining rule, the blast radius formula, launch speed per unit of power, and spawn positions are scaffold values in `tv_sim`.
- Players, hit detection, and the arena do not exist in the simulation yet.
- Tick rate is 60 Hz. The snapshot rate is not chosen.

### Balloon body

- **Mesh detail.** The balloon is a geodesic sphere of frequency 6 (362 vertices). Frequency 8 (642) is smoother and costs about 1.7 times as much. The right value depends on how the physics runs on the phone, which is not measured yet.
- **The knot.** It is a separate small mesh placed on the tip vertex, because the balloon's own mesh is too coarse to show one. A finer neck would let the balloon's own mesh carry it.
- **Compartments and membranes.** The editing menu will need inner walls that only break on impact. The balloon is currently one closed shell with one volume constraint. Inner chambers would add more volume constraints and shared membranes.
- **Painting.** The art canvas needs a way to map flat pixels onto the balloon. The mesh has no texture coordinates yet, apart from the knot weight in the first one.
- **Optimization level on Android.** `-o:minimal` is the safe level, `-o:size` is much faster and compiles, and neither `-o:speed` nor `-o:aggressive` compiles for 32-bit ARM with this Odin release. Whether `-o:size` runs correctly on the phone is untested.

### Art

- Whether 16 colours is enough, or a 256-colour palette should replace it.
- Hosting the game on Google Play would bring a user-generated-content policy, which expects reporting and blocking tools. Sideloading does not.

### Browser build

- `vendor:raylib` in the pinned Odin release ships a prebuilt web library, so Odin has raylib support for WebAssembly. The Emscripten link step, the browser main loop, the Rust library for `wasm32-unknown-emscripten`, and hosting are not built or tested. Shaders for it already exist in `client/shaders/glsl100/`.

### Housekeeping

- The Odin foreign import lists Linux desktop libraries only. The Android build does not use them, because it links with the NDK in `scripts/build_android.sh`.
- No devcontainer.
