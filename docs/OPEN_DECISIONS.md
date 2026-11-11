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
- Players walking a round arena of 20 m radius exist in the simulation, and balloons burst on the ground and on the wall. Hit detection, damage, hit points, respawn, and the kill cam do not, because the combat rules are not specified.
- The arena numbers are first guesses to tune by feel: walking speed 3.2 m/s, jump speed 3 m/s (the lab's, about 46 cm), throw power 6 to 18 m/s over 1.2 s of holding, 0.5 s between throws, a throw height of 1.5 m, eight spawn points on a ring of 14 m, and a coliseum with five tiers and an outer wall 12 m high.
- The incinerator takes only the balloon in the hand, and what it burns is gone for good with no undo. It stands at the east end of the south counter, past the loadout rack.
- The lab is to grow into a full building with a shop area and a firing range, where flasks are bought when they have been destroyed, along with equipment. The owner will work out the game loop and the chemicals himself, and nothing of it is built.
- The player character is a temporary low-poly stand-in, 668 triangles in six stiff parts moved by a pose. The owner wants a soft, ragdollable one that has weird physics when blown up or melted, which is a different thing: the likely way is the balloon's soft body, limbs as chains of particles, and a stiffness that falls as it melts.
- The arena has a stand-in bot as a second player so there is somebody to look at. It wanders, jumps, and throws water, and it has no purpose until the combat rules exist.
- The drawing screen has the tools on the right and the balloon on the left, as the owner asked. A way to put an image from the phone straight onto a balloon was asked about and looked into, and is not built. What was found: the app is a pure native activity with no Java (`hasCode="false"`), and Android gives the result of a picker to the activity's `onActivityResult`, which a native activity does not pass on, so a system picker needs a small Java class, `hasCode="true"`, and `javac` and `d8` steps in `android.yml`, which cannot be tried outside CI. Without Java, the app can ask for All files access (`MANAGE_EXTERNAL_STORAGE`, a switch in Settings that a sideloaded app may use) and read a folder such as `/sdcard/TerminalViscosity` itself, with JNI calls to framework classes only to open that Settings page and to ask whether it is granted. Putting a file in the app's own `Android/data` folder is not dependable from Android 13, where most file managers cannot open it. As built, raylib reads PNG and not JPEG, and Odin's own `core:image/jpeg` decoded all four of the owner's JPEGs, so decoding is not the obstacle. The art is 256 by 256 in 16 colours and the wire format already carries 16 colours with each drawing, so an image can bring its own palette. On four of the owner's images the error against the original was, in mean squared error per channel, about 460 to 1730 for the nearest colour in the game's palette, 24 to 68 with dithering, and 5 to 183 with the image's own 15 colours. Which way to get the file in is the owner's choice.
- A throw does not use up the balloon, and with no balloon on any hook the arena offers a plain water balloon of 500 ml. Neither was asked for.
- Drawn between ticks, the arena shows the world one tick, 17 ms, late.
- Other players' balloons are drawn plain at 500 ml, because the snapshot carries neither their fill nor their drawing. Drawings are meant to be sent once, when a player joins, and that is not built.
- Tick rate is 60 Hz. The snapshot rate is not chosen.

### Combat in the arena (assumed so that a player can be hurt)

None of this was specified. It was written so that the stand-in bot could be hurt, and the numbers are first guesses to change by playing.

- **Hit points.** 100 each. A direct hit by a plain balloon takes 20, so five knock a player out. Volatility adds up to 80 more, which is nothing until the compound database is shared.
- **Splash.** A burst hurts everyone but the thrower within its radius, by less the farther it is, down to nothing at the radius, measured to the body. The radius is the radius of the burst, 1 m for a plain 500 ml balloon.
- **The thrower.** Never hurt by their own balloons. Whether they should be is open.
- **Knock-out.** At 0 hit points a player is down for three seconds: no walking, jumping or throwing, and balloons pass through. They come back at their own spawn point with full hit points. Nothing counts knock-outs, and nothing is shown for them yet, such as a kill cam.
- **Who threw.** The snapshot does not say whose balloon hurt whom. The client shows a red cross whenever any other player is hurt, which is right while there are two players and no more.
- **The bot.** Its distances, its timing, its aim error and its lead (see `bot.odin` in `client/docs/client.md`) are guesses. At the range it likes it hits a standing player about two times in three.
- **The throw pad and the controls.** The throw pad turns the view by how far its finger moves, as the look finger does, instead of a rate stick. The first fire stick (fixed middle, squared response) was too sensitive to aim with, and the second (floating, straight-line response at 1.8 and 1.2 rad/s) was reported on the phone as still needing work on aiming and movement. The owner pointed at Tower-Of-Babylon, whose controls `touch.odin` follows: the walking stick floats in the left half with a ring 19 percent of the screen height and a dead zone of 0.08, the look finger is any finger on the right half, and the view cannot turn more than a fifth of the screen height in a frame. All these numbers are Tower-Of-Babylon's and none has been tried in this game on a phone. The view turns at the lab's `LOOK_SPEED` for every finger, which is also untried for aiming a throw.

### Reactions by compound (the owner's idea, not built)

The owner will rework the chemicals and the recipes himself, and proposed that instead of one general reaction matrix each compound gets its own page of reactions, that more than two compounds can be combined to make something else, and that the player buys or unlocks certain mixtures. Questions that the owner will have to settle when he does:

- Where a reaction of three compounds lives. On the page of each of them, written once and listed on each, is the likelier way, so that a page is a complete answer to what can be made with its compound.
- Which wins when a mix is covered by several: the whole set, if one is defined, and the pairs inside it only if not, seems the plain rule.
- That the order of pouring does not matter, or does, and whether a mix is a set of compounds or a set with amounts.
- What an unlock is: a flag per reaction that the player holds, and what a mix the player has not unlocked does when it is made, whether it still happens, or is refused.
- The server has an empty table, so volatility, and with it the damage a balloon does beyond its base, depend on how that is shared.

Nothing of this is built. `carry.compound_density` is the one place a density would go, for the scale.

The owner's plan for it is locked in `docs/DESIGN.md`, and a format for the pages that answers the questions above is proposed in `docs/REACTIONS.md`. The owner has seen it and asked for two things that are in it: a reaction level of at most two, and a base colour and shader seed for each liquid. What is still open: whether electrolysis counts as a level, whether a catalyst does, the shader itself, and the product pages beyond the first thirteen.

### Lab equipment added (see `equipment.odin` and `gear.odin` in `client/docs/client.md`)

- **Vial racks.** Four, with twelve holes each, and 24 empty vials start in them. A vial is a small vessel that holds about 33 ml. It is drawn into a free hole within 3 cm when it is let go of. Whether vials should be able to hold more than one compound, and whether they are for carrying samples or for storing, is open.
- **First aid cabinet.** Back to full health at once, then it rests for 30 seconds. The numbers are guesses, and whether the cabinet is to give less, or cost something, is open.
- **Scale.** Reads the glass and the contents in grams, with a tare. Every compound weighs a gram a millilitre until the compound table has a density.
- **Shelves.** Two shelves of forty bottles in the colours of the compounds in turn, with pale labels without writing. Whether a shelf bottle is ever to be taken, or to say what it holds, is open.
- **Not built:** the graduated cylinder and the dropper, the fridge, the waste bucket and the whiteboard that were suggested.

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
- **Open: heat.** A fully hot liquid adds 0.6 to the volatility of a meeting and a fully cold one takes 0.6 of it away, the plate warms in about five seconds and the liquid cools back in about half a minute, and the plate is always on. All are first guesses. The matrix menu shows the volatility in the room. Solids that can be dropped into a mixture come later.
- **Open: the loadout.** Three hooks, set in one place. The drawing is one per balloon, which is assumed. The loadout is saved to a file when it changes and read back at the start, with its drawings. It is not sent to the server yet. A balloon is let down to 1000 ml when tied. A balloon in the hand swings from its neck and has no knot yet.
- **Open: the blending pen.** It smudges and dithers, which is one reading of a pen that blends, and might not be what is wanted. Its reach, which is a five by nine window of pixels, and its strength, which is one pass for each dab, are first guesses.
- **Open: the oven spout.** It is off the right end of the oven over a tray, and a vessel is filled held near it or standing on the tray. The product comes out at the temperature of the room.
- **Open: the drawing.** The picture is made on a tablet beside the paint station and goes once round the balloon and from the tip to the bottom, so it is pinched under the clamps. Color 0 is no paint and the eraser, so there are 15 paints, which is an assumption. There are three brushes and eight undos. Drawings are saved with the loadout in the byte layout of the Rust codec, which the Odin code matches byte for byte, and are not sent yet. The second clamp is only for show, so how it pins the soft body is not done. The palette and the sizes of everything on the screen are first guesses.
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
