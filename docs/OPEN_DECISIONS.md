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

### The lab room

- **Decided: first person with a floating joystick and a look drag.** A pointer-tap walk was the alternative.
- **Decided: the room is in metres.** The balloon's physics runs at a scale where it is 2 units across, so in the lab it will be drawn scaled down. The ratio is not chosen.
- **Open: the look.** It is a clean light room with dark counters and teal glow, a mix of the dark teal and white clinical references. Palette and glow are constants at the top of `layout.odin`.
- **Open: where the other stations go.** A sink with a drain is on the west counter, a fume hood on the north counter, and the balloon fill station on the south counter. A reaction oven is on the north counter. The chamber machine, the hot plate and ice bath, the scale, the storage racks, the recipe terminal, and the loadout rack have no place yet.
- **Open: ceiling.** The ceiling is flat with straight light panels. The hexagon panels in one reference are not done.
- **Decided: a violent mix hurts.** A blast damages the player and breaks the container, and a spatter stings and spills some liquid. Mixing is a button pressed with one vessel held over another.
- **Decided: the liquid simulation is for the lab only.** The gameplay balloon does not use it. On the first phone runs the simulation cost 4.3 microseconds a particle each step, so a 125 ml splash fits the frame budget at 3 cm cells and not at 2 cm.
- **Decided: pouring is aimed with the crosshair.** The held vessel tips over while a button is held, and the stream goes into the vessel under the crosshair if it is within 1.5 m. Under a tap on the bottle wall the same button fills the vessel.
- **Open: the lab's gameplay loop.** The lab is to have its own enjoyable loop. Not everything is open from the start, and there will be a store and things earned by playing, but that comes later, once the lab feels right. The taps already have an `unlocked` flag as the place for it, and the reaction matrix menu shows every pair for now, where later it could show only what has been found.
- **Open: the numbers of the workstations.** The fume hood stops four fifths of a blast's damage, a balloon holds 1000 ml at its natural size and bursts at 1.35 times that, a fresh one is clamped two seconds after one is lost, and an overfill hurts nobody. All are first guesses to tune by playing. A reaction in the balloon hurts as in a vessel.
- **Open: the oven.** Its four ports are mixed first to last, a run takes 6 seconds at normal speed, nothing is lost in a run, a port holds one liquid at a time, and a run cannot start until the tank is emptied. All are first guesses. Whether the oven should also feed the balloon, so a product goes into a balloon without a vessel, is not decided.
- **Open: the speed of liquid.** Pours, taps, the spout of the oven, and its run go 1, 2, 4, or 8 times faster by a button, and a faster speed makes each drop stand for more liquid. The setting is not saved. It belongs in the settings screen that is still to be built.
- **Open: what a filled balloon becomes.** It cannot be taken off the clamp yet. That needs the loadout rack, and the tie that gives it its knot.
- **Open: the look of a blast.** Particles, a ring, a flash of light on the room, a knock to the view, and a wobble of the picture, scaled by the power of the blast and smaller in the hood. Sizes, counts, and timings are first guesses, and none of it has been seen on a phone. Scorch marks, per-liquid looks, and sound are not done.
- **Open: the numbers of a bad mix.** The reaction matrix, how much a blast and a spatter hurt, how fast health comes back, and the reset of the lab when the player is knocked out are first guesses to tune by playing.

### Local data

- **Decided: the DixScript library is loaded at run time and not linked.** A missing library then becomes a message on screen. Its Android build comes prebuilt from DixScript's own repository, pinned by commit and checksum.
- **Decided: the game crates stay dependency-free.** DixScript lives in the client only. The server can read the same `.mdix` files with the `dixscript` crate.
- **Open: where shipped content lives.** The plan is compound, reaction, and membrane tables as `.mdix` files in the APK's assets, read with raylib and parsed with `mdix_load_str`, with a content hash at the handshake. Nothing is built yet.
- **Open: what a save protects.** DixScript can compress and encrypt files. The server stays the authority, so a save cannot grant power, and encryption would only deter casual editing.
- **Open: other platforms.** Only the Linux and Android libraries are wired up. DixScript's repository also ships Windows, macOS, and other Android builds.
- **Open: the Rust version.** The core DixScript crate declares 1.75, its C library crate declares 1.85, and the game crates keep a 1.75 floor. The prebuilt library avoids the question for the client.

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
