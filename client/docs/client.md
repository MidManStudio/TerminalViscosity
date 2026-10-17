# client

## Overview

The Odin client: window, input, rendering, scenes, and the crafting-lab prototype. It links the Rust simulation through the C ABI in `tv_ffi`. Raylib comes from the `vendor:raylib` package that ships with the Odin compiler (raylib 6.0 in the release used here).

The game is arranged in scenes, as in Unity. There is one scene so far, the lab: a 3D water balloon that can be grabbed and dragged. Lifting it by its tied tip makes it hang as a teardrop, and dropping it makes it squash and wobble. The balloon editing menu, the arena, networking, and balloon painting are not started.

Commands, run from the repository root with `cargo` and `odin` on the path:

- `bash scripts/build_client.sh` builds the Rust library and the client into `build/`.
- `build/tv_client --selftest` runs without a window and checks the ABI, the simulation, and the 3D balloon.
- `odin test client/src/balloon` runs the balloon tests, and `odin test client/src/softbody` runs the older 2D ring tests.
- `odin run client/bench -o:speed` runs the soft-body and balloon benchmarks.
- From `build/`, `./tv_client --fixed-step --frames 240 --screenshot lab.png` runs the lab for a fixed number of frames and saves a screenshot. The screenshot path is relative to the working directory. Under a virtual display this works in CI: `xvfb-run -a ./tv_client ...`.
- `--demo hang` and `--demo swing` script the pointer: after 90 frames the tip is grabbed and lifted, and `swing` then sways it side to side. `--fixed-step` advances the game by exactly 1/60 s per frame, so a given frame count always shows the same picture. `--size 1600x720` opens a window of that size, which is handy for trying a phone's wide screen.

## Modules

### `softbody.odin`
**What it does:** The 2D predecessor of the balloon. `Ring`, a 2D loop of point masses with Verlet integration, edge-length constraints, and a position-based area constraint. It has no raylib dependency, so tests and benchmarks run without a window.

**Decisions:**
- Area is held by projecting node positions along the gradient of the polygon area (the volume-constraint method from Mueller et al.), not by a pressure force. A stiff pressure force blew the ring off screen on hard impacts, see Fixes and Problems.
- No node may move more than one edge length per step. This is a safety net, not the main stabilizer.
- `area_stiffness` is the share of the area error removed per constraint pass. Lower values give a wobblier balloon.
- The cursor interaction is a grab (pin one node to the mouse) and a poke (push nearby nodes away).

**Benchmarks:** `client/bench/softbody_bench.odin`.

**Tests:** `softbody_test.odin`.

**Status:** The lab no longer uses it. The self-test and the benchmark still do, so it stays until the balloon has taken over those jobs.

### `softbody_test.odin`
**What it does:** Initial area, finiteness under 10,000 random pokes, settling on the floor near rest area, a grabbed node following its target, nearest-node lookup, grab-and-throw, and a sweep over 72 combinations of step size, node count, radius, and floor height that must all stay bounded.

### `softbody_bench.odin`
**What it does:** Times `ring_step` for 16, 24, 48, and 64 nodes, takes the median of nine samples, and prints `BENCH <name> <ns_per_step>` lines.

**Decisions:** Plain `core:time` instead of a framework. `scripts/bench_summary.py` parses the output format.

### `geodesic.odin`
**What it does:** Builds the closed triangle mesh of a balloon and its rest shape. The mesh is a geodesic sphere: an icosahedron with each face cut into f by f triangles and pushed onto the unit sphere, with vertex 0 at +Y. Frequency 6 gives 362 vertices, 1,080 edges, and 720 faces, and the formulas are 10 f squared plus 2, 30 f squared, and 20 f squared. `shape_point` moves a unit direction onto the rest shape: a sphere with a slim neck that narrows toward the tip and a small swelling for the knot.

**Decisions:**
- A geodesic sphere has nearly equal triangles everywhere and no poles, so the rubber behaves the same in every direction. A latitude and longitude sphere would have thin triangles at the poles.
- Vertices are numbered so that points on shared icosahedron edges are created once, and every face is wound counter-clockwise seen from outside. Tests check the counts, the Euler characteristic, that every directed edge is used once and its reverse once, that every vertex has five or six neighbors, and that all faces point outward.
- The edges are sorted by color, where no two edges that share a vertex have the same color. The solver visits them in list order, and a plain spatial order leaked a little spin into the balloon every substep, see Fixes and Problems.
- The neck is shaped by the polar angle from the tip, and the lateral scale is squared so the neck stays slim for most of its length before it flares into the body.

**Tests:** `balloon_test.odin`.

### `balloon.odin`
**What it does:** Package `balloon`, the 3D soft body of a water balloon: a closed rubber membrane around a fixed volume of water, tied off at one vertex (the tip, vertex 0). It has no raylib dependency, so it is tested and benchmarked without a window. `Config` holds every tunable number, `init` builds the mesh and rest shape, `step` advances by one frame, `pin` and `unpin` hold a vertex on its way to a target, and `update_normals`, `tip_frame`, `volume`, `bounds`, and `max_speed` are for the renderer and the tests.

**Decisions:**
- The solver is XPBD with a fixed number of substeps (8 by default) and a single constraint pass in each, the "small steps" approach. It stays stable at stiffnesses that a force-based spring model would blow up on.
- Rubber is one distance constraint per edge. The rest length is 97 percent of the rest-shape length, so the shell is slightly stretched. Compliance falls as the edge stretches, so the rubber stiffens like real latex and a hard yank cannot pull the neck out without limit. The knot is ten times stiffer than the rest.
- Water is one global volume constraint. Its gradient at a vertex is a third of the area vectors of the faces around it, and the same vector gives the direction and size of a pressure force on that vertex. The multiplier of the constraint divided by the step squared is the pressure holding the volume, and it is tracked.
- Water weight is modeled as hydrostatic pressure. In a frame that moves with the balloon, pressure grows linearly along g minus the balloon's acceleration. That is what turns a held balloon into a teardrop: the bottom is pushed out hard and the neck is pulled long. The sum of these forces is the weight of the water, and the vertex masses already carry it, so the net force is removed and only the redistribution is applied. The acceleration is measured from the mean velocity and low-pass filtered, so a hard stop presses the water into the floor and a free fall makes it weightless.
- Total pressure is never allowed below zero, and the gain on the hydrostatic part is capped at four times gravity's. Both are guards against a yank folding the membrane inside out.
- The held vertex follows its target like a critically damped spring with a speed limit, so a drag is smooth. On release it keeps its velocity, so a drag becomes a throw.
- Three kinds of damping serve different jobs. Edge damping slows only stretching and squeezing. Shape damping slows every change of shape relative to the best-fit rigid motion, so flying and spinning are free. Contact damping adds to the shape damping while many vertices touch the floor, which turns a landing into a splat instead of a bounce. A fourth, held damping, drags the whole balloon against the hand while it is pinned, because the pin fixes a point and not an orientation.
- Hot loops use plain floats and one fused pass where possible, and they skip bounds checking. The Android build is compiled with little optimization, and vector arithmetic on small arrays cost a lot there.
- If the shape ever goes non-finite or its volume leaves a sane range, the balloon is put back in its rest shape instead of staying broken.
- The floor, the walls, and friction are part of the solver. Friction moves a vertex back along the ground by at most the friction coefficient times how deep it was pushed in.

**Tests:** `balloon_test.odin`.

**Benchmarks:** `client/bench/balloon_bench.odin`.

### `balloon_test.odin`
**What it does:** Mesh topology for frequencies 1 to 8, outward faces, the rest shape, and the knot weights. Then the physics: a dropped balloon rests flattened on the floor with its volume kept, a landing does not rebound above 1.3, a balloon held by the tip is a tall teardrop that is widest in its lower half and clear of the floor, hanging is taller than resting, a released balloon falls and settles, the held vertex follows its target within the speed limit, filling and emptying keeps the volume, 25 seconds of deterministic random grabs and throws never leave the room or lose more than a fifth of the volume, a sweep over mesh detail, substeps, step size, and fill stays bounded, identical inputs give an identical balloon, and the shape holds still in zero gravity. The tip frame and the smoothed normals are checked too.

### `camera.odin`
**What it does:** `Camera_Rig`, an orbit camera, and `Camera_Frame`, the numbers needed to turn a pixel into a ray and a world point into a pixel. `camera_to_raylib` hands the rig to `BeginMode3D`.

**Decisions:**
- The ray and projection code is plain Odin and matches how raylib builds its perspective, so picking never calls a raylib function that returns a struct of floats. Those are unsafe on 32-bit ARM Android, see `android_entry.odin`.
- Pitch and distance are clamped, so the camera cannot flip over or end up inside the balloon.

### `balloon_view.odin`
**What it does:** Puts the balloon on the screen. One dynamic raylib mesh holds the balloon and is rewritten every frame. A second small dynamic mesh is the knot: a lathe shape with a bulb, a pinch, and a short tail, placed on the tip vertex and turned with it. `view_draw` draws the knot first, because it is opaque, then the balloon in two passes.

**Decisions:**
- The balloon is drawn inside first, then outside, so the far wall shows faintly through the near one with no depth sorting.
- Mesh memory comes from raylib's allocator, because `UnloadMesh` frees it with raylib's free.
- A mesh with 362 vertices was too coarse to show a knot, so the knot is a separate shape. It reaches past the tip vertex, because placed inside the neck it was hidden by the neck's own translucent cone.
- If the balloon shader fails to compile, the balloon is drawn flat with raylib's default shader.
- All the raylib calls here pass the same register layout from Odin as from C on 32-bit ARM, which was checked by comparing Odin's compiled declarations with clang's for every raylib and rlgl function the client calls.

### `scene.odin`
**What it does:** The scene system. `Scene` is five procedures, `load`, `update`, `draw`, `draw_ui`, and `unload`. `Game` holds what every scene shares: the screen size, the heat-shader pass, the off-screen render target, the current scene and its state, and the scripted demo mode. `game_switch` asks for another scene, and the switch happens at the end of the frame.

**Decisions:**
- A scene allocates its own state in `load` and returns it as a pointer, and the manager only hands it back. That keeps scenes independent of one another.
- `draw` renders into the shared render target, which the heat shader puts on screen. `draw_ui` draws on the screen afterwards, so text is never distorted.
- The scene table is a `switch` inside a procedure, not a constant array of procedures, so nothing needs package-level initialization, which does not run on Android.

### `scene_lab.odin`
**What it does:** The lab scene. It owns one balloon, its view, and a camera. Pressing on the balloon grabs the nearest vertex that faces the camera, and the tip counts as twice as close, so the small tied end is easy to catch with a finger. The held vertex is dragged in a plane facing the camera. Pressing anywhere else turns the camera, and the mouse wheel zooms. Physics runs in fixed steps of 1/60 s, at most three per frame. The floor is a large quad with a grid, and a soft disc under the balloon grows and fades as it rises.

**Decisions:**
- One pointer is enough for everything, so the lab works the same with a mouse and with a finger.
- A slow frame runs at most three steps and then drops the rest of the time, so a slow phone sees slow motion instead of ever longer frames.
- The scene sets tighter clip planes, 0.5 to 80, so a 16-bit depth buffer on a phone has enough precision, and puts raylib's defaults back on unload.
- The floor uses plain rlgl vertices rather than `DrawPlane`, which takes structs of floats by value.
- The shadow is drawn without depth testing right after the floor, so it sits exactly on the floor without flickering against it.
- The overlay shows the milliseconds the physics took, so the cost on a phone can be read off a screenshot.
- The scripted demo grabs the tip at frame 90 and lifts it over 45 frames. `swing` sways it after frame 170.

### `balloon.vs`
**What it does:** Vertex shader for the balloon. The mesh is already in world space, so positions and normals pass straight through. The first texture coordinate carries how much of the knot a vertex is. There are two versions, `shaders/glsl330/` and `shaders/glsl100/`.

**Decisions:** The two files are kept in step by hand. Both pass `glslangValidator`, and the OpenGL ES 1.00 pair compiled, linked, and rendered the same picture as the desktop pair on a software OpenGL context.

### `balloon.fs`
**What it does:** Fragment shader for latex over water. A soft diffuse term, a broad highlight, and a reflection of a fake sky that grows toward the edge of the shape, where the rubber is seen at a slant. The inside pass is darker and more transparent. The knot is opaque, darker rubber.

**Decisions:**
- Highp precision is used where the device has it, because a phone defaults to mediump in fragment shaders and the lighting math needs more.
- The highlight is broad and the normals are smoothed once over their neighbors in `update_normals`. A tight highlight showed every ridge of the long thin triangles on a stretched neck.

### `balloon_bench.odin`
**What it does:** Times one 60 Hz step of the balloon, all substeps included, while the tip is held and swung, so the pin, the constraints, and the damping all run. Cases are mesh frequency 4 with 6 substeps, 6 with 8, and 8 with 8, plus a frame for frequency 6 that also builds the render normals. It prints `BENCH balloon_step_f6_s8 <ns>` style lines.

**Decisions:** On the development machine a frequency 6 step with 8 substeps takes about 0.18 ms compiled with `-o:speed`, and about 0.5 ms with `-o:minimal`, the level the Android build uses. A phone core is several times slower, so the lab overlay shows the real cost.

### `tv_ffi.odin`
**What it does:** Odin declarations for `tv.h`, with compile-time `#assert`s on struct sizes.

**Decisions:**
- The library path is the `TV_LIB` config value, so other targets can point at a different build with `-define:TV_LIB=...`.
- The system libraries listed are the ones `rustc --print native-static-libs` reports for Linux. Other operating systems are not set up yet.

### `selftest.odin`
**What it does:** Windowless check. It compares the ABI version and struct sizes with the Rust side, plays one balloon from throw to detonation through the C ABI, decodes the snapshot and event bytes, and steps the soft-body ring. It also drops the 3D balloon, then lifts it by the tip, and checks the volume, the resting position, and the teardrop shape.

### `main.odin`
**What it does:** Entry point, argument handling, and the frame loop. Each frame it updates the current scene, renders the scene into an off-screen texture, copies that through the heat shader, and then draws the scene's overlay.

**Decisions:**
- The scene renders to an off-screen texture and is drawn through the heat shader, so post effects can cover the whole frame.
- Layout comes from the real screen size, so the same code fits a 1280 by 720 desktop window and a phone.
- The 4x multisampling hint is skipped on Android.
- A missing `os.args` is handled, because it is empty on Android.
- `--fixed-step`, `--demo`, and `--size` exist so headless runs are repeatable and can show a held balloon. They are for CI and screenshots, and the phone never passes them.

### `android_entry.odin`
**What it does:** Exports `tv_odin_main`, the one procedure the C shim in `android/entry.c` calls. It builds a default context and calls `main`. The file only compiles for the Android target, through the `#+build linux:android` tag, so desktop builds never see it.

**Decisions:**
- The Odin runtime start-up is not run in this build mode. Code on the Android path must not rely on package-level initializers or on `os.args`, which is empty there.
- It also holds the Android `platform_mouse_position`, which calls a C wrapper instead of raylib directly. Odin's 32-bit ARM backend returns a struct of two floats in registers, while the NDK returns it through a hidden pointer.

### `platform_desktop.odin`
**What it does:** The desktop version of `platform_mouse_position`, which calls raylib's `GetMousePosition` directly. It compiles for every target except Android, through the `#+build !linux:android` tag. `android_entry.odin` holds the Android version.

### `shaders.odin`
**What it does:** Resolves shader file paths, loads the heat-distortion and balloon shaders, and draws the scene through the heat shader. If the heat shader fails to compile, the scene is drawn without it.

**Decisions:**
- Shader files are found relative to the executable, and `scripts/build_client.sh` copies `client/shaders` next to it. On Android they are read from the APK's assets by relative path.
- Browser and Android builds need the OpenGL ES shaders, so the directory is chosen at compile time by target.
- The scene is copied to the screen with blending off. A translucent balloon leaves an alpha below 1 in the scene texture, and blending that onto black would darken the picture. This holds with and without the heat shader.

### `heat_distort.fs`
**What it does:** A small screen-space ripple. There are two versions, `shaders/glsl330/` for desktop and `shaders/glsl100/` for OpenGL ES 2 and the browser.

**Decisions:**
- The two files are kept in step by hand. Both pass `glslangValidator`, and the desktop one compiled and ran on a software OpenGL context in a headless test.
- The output alpha is forced to 1. The scene is opaque on screen, and the translucent balloon would otherwise leave a lower alpha in the scene texture.

## CI and Workflows

- `.github/workflows/ci.yml` job `odin` downloads a pinned Odin release, runs `odin check`, the soft-body and balloon tests, validates all the shader files, builds and runs `--selftest`, and renders headless screenshots of the lab resting and held by its tip, which are kept as an artifact.
- `.github/workflows/bench.yml` runs the Odin benchmark and merges it into the result file.
- `scripts/build_client.sh` is described in `docs/CI.md`.

## Fixes and Problems

### `softbody.odin`
- The first version used a pressure force proportional to the area error. A headless render showed no balloon, and a sweep showed the ring thrown far off screen after hitting the floor for some combinations of step size and node count (for example 60 Hz with 24 nodes of radius 80 and the floor at 640). The first unit tests passed only because they used one lucky combination. Replaced with the area constraint, and added the parameter sweep test and the grab-and-throw test.

### `geodesic.odin`
- With the edges listed in spatial order, a balloon held by its tip kept twisting about the vertical axis at a steady rate that never died down, and a floating balloon drifted the same way. Sweeping the edges in one direction leaks a little spin into the body every substep. A symmetric double pass removed it but doubled the cost, so the edges are now sorted by color. The held twist dropped from about 0.26 to 0.08 units per second, and the floating balloon turns so slowly it is invisible.

### `balloon.odin`
- The first held balloon exploded when the tip was yanked from rest: the measured acceleration spiked, the hydrostatic gradient grew several times larger than the pressure inside, the top of the shell was sucked inward, and the mesh turned inside out. Fixed with four guards: the held vertex now follows a critically damped spring, the total pressure cannot go below zero, the hydrostatic gain is capped, and the rubber stiffens with stretch. A health check puts the balloon back in its rest shape if it ever blows up anyway.
- Alternating the edge sweep direction every substep made the stiff knot flip between two positions each substep, which showed as a fast jitter on the five vertices around the tip. The sweep now always runs the same way.
- A balloon dropped from 2.5 units rebounded like a rubber ball. Damping that only acts on edge lengths barely touches a slow, whole-body shape change, and damping toward the best-fit rigid motion acts too slowly during a 0.1 s impact. Extra shape damping while many vertices touch the floor turns the landing into a splat.
- A held balloon swung and twisted for several seconds, because the pin fixes a point and not an orientation. Held damping drags it against the hand.
- Compiled with `-o:minimal`, the first version of the physics took about five times as long as with `-o:speed`. Skipping bounds checks in the hot loops, plain float arithmetic, and fewer passes brought a step from about 0.93 ms to about 0.5 ms. `-o:size` is as fast as `-o:speed` on the desktop and also compiles for 32-bit ARM Android, but it has not been run on a device.
- The settled zero-gravity balloon turns about 0.02 radians per second about the vertical axis. It is the last trace of the sweep order effect above and is not visible.

### `balloon_view.odin`
- The first knot was placed on the tip vertex and was invisible: the simulated neck near the tip was wider than the knot, so the knot sat inside the neck's translucent cone. The neck is now slimmer, and the knot reaches past the tip vertex.
- A stretched neck showed wiggly bright streaks in the highlight. The long thin triangles of a stretched neck make the interpolated normals uneven. `update_normals` now blends each normal with its neighbors once, and the highlight is broader.

### `scene_lab.odin`
- `rl.DrawPlane` was replaced by plain rlgl vertices. It takes a Vector3 and a Vector2 by value, which Odin and clang describe with different but equivalent types on 32-bit ARM. It was the only new call in that group, so avoiding it removes the question.

### `shaders.odin`
- Shader paths were first resolved against the working directory, so the shader did not load when the client ran from another directory. Now resolved against the executable's directory.
- The scene texture's alpha channel is below 1 where the translucent balloon was drawn. Copying it to the window with blending on darkened those pixels. Caught when the OpenGL ES shaders ran with the heat shader unavailable, where the picture was visibly dimmer.

### `main.odin`
- Raylib's `TakeScreenshot` prepends the working directory to the path it is given, so absolute paths fail. The flag documentation says the path is relative to the working directory.

### `tv_ffi.odin`
- Odin rejects an absolute path in a foreign import ("Invalid import path"), so the Android build passes `TV_LIB` as a path relative to `client/src`.

### `android_entry.odin`
- The first installed Android build crashed on launch. Odin's ABI lowering for 32-bit ARM returns an 8-byte float struct in registers, but the NDK uses a hidden return pointer, so the per-frame call to `GetMousePosition` made raylib write through a garbage pointer. All other raylib calls matched. Fixed with a C wrapper, and `scripts/check_android_abi.py` now guards against the same mistake. Confirmed on the device: the app runs.
- Odin's default CPU for 32-bit ARM is an ARMv6 `arm1176jzf-s`, which is why the build now passes `-microarch:cortex-a7`.
- Odin dev-2026-10 crashes inside LLVM when compiling for 32-bit ARM Android with `-o:speed` or `-o:aggressive`. `-o:minimal` and `-o:size` work. The Android build uses `-o:minimal` unless `TV_OPT` says otherwise.
- `-build-mode:executable` is rejected for the Android subtarget, and `-build-mode:shared` defines a `main` that does nothing, which would stop raylib from starting the game. Hence plain objects plus the C shim.
- Every raylib and rlgl function the 3D client calls on Android (50 of them) was compared with how clang compiles the C prototype for 32-bit ARM. 43 are identical, including `BeginMode3D`, `DrawMesh`, `UploadMesh`, `UpdateMeshBuffer`, `UnloadMesh`, and the rlgl calls that take doubles. The other 7 differ only in names for the same layout: arrays of floats versus integers of the same size, `i1` versus `i8` for a returned bool, and extra attributes on a hidden return pointer. All 7 were already in use by the working 2D build.

### `selftest.odin`
- None recorded yet.

### `softbody_bench.odin`
- None recorded yet.

### `balloon_test.odin`
- The first zero-gravity test expected the balloon to be perfectly still after one second. It is still easing back from its pre-stretched rest shape, and turns very slowly. The test now allows a small speed and drift after two seconds.
- The full suite took 26 seconds in an unoptimized build with every combination in the parameter sweep. The sweep was trimmed to 24 combinations that still cover each mesh size, substep count, step size, and fill range, and the faster solver loops cut the rest.
