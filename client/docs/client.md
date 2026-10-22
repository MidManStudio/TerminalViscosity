# client

## Overview

The Odin client: window, input, rendering, scenes, and the crafting-lab prototype. It links the Rust simulation through the C ABI in `tv_ffi`. Raylib comes from the `vendor:raylib` package that ships with the Odin compiler (raylib 6.0 in the release used here).

The game is arranged in scenes, as in Unity. There are two scenes. The lab room is the chemistry lab, walked around in first person: a large open room with long counters along the walls and one in the middle. The balloon lab is the balloon on its own: a 3D water balloon that can be grabbed and dragged. Lifting it by its tied tip makes it hang as a teardrop, and dropping it makes it squash and wobble. The lab overlay also shows the result of a start-up check of the local database, which reads and writes DixScript through its C library. The balloon editing menu, the arena, networking, and balloon painting are not started.

Commands, run from the repository root with `cargo` and `odin` on the path:

- `bash scripts/build_client.sh` builds the Rust library and the client into `build/`.
- `build/tv_client --selftest` runs without a window and checks the ABI, the simulation, and the 3D balloon.
- `odin test client/src/lab` runs the lab layout, player, and collision tests.
- `odin test client/src/balloon` runs the balloon tests, and `odin test client/src/softbody` runs the older 2D ring tests.
- `odin test client/src/store` runs the local-database tests. Three of them need a DixScript library and skip themselves without one. `TV_MDIX_FAKE_LIB` points at the stand-in built with `cc -shared -fPIC -o libfake_mdix.so client/src/store/testdata/fake_mdix_ffi.c`, and `TV_MDIX_LIB` points at the real DixScript library.
- `odin run client/bench -o:speed` runs the soft-body and balloon benchmarks.
- From `build/`, `./tv_client --fixed-step --frames 240 --screenshot lab.png` runs the lab for a fixed number of frames and saves a screenshot. The screenshot path is relative to the working directory. Under a virtual display this works in CI: `xvfb-run -a ./tv_client ...`.
- `--demo hang` and `--demo swing` script the pointer: after 90 frames the tip is grabbed and lifted, and `swing` then sways it side to side. `--fixed-step` advances the game by exactly 1/60 s per frame, so a given frame count always shows the same picture. `--size 1600x720` opens a window of that size, which is handy for trying a phone's wide screen. `--scene room` or `--scene balloon` picks the scene to start in, and the demos only act in the balloon scene. In the lab room a desktop walks with WASD or the arrow keys and looks by dragging the mouse. A small button in the top right corner switches scenes.

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
**What it does:** The scene system. `Scene` is five procedures, `load`, `update`, `draw`, `draw_ui`, and `unload`. `Game` holds what every scene shares: the screen size, the heat-shader pass and how strongly it wobbles, the off-screen render target, the current scene and its state, the scripted demo mode, and the local database with the result of its check. `game_switch` asks for another scene, and the switch happens at the end of the frame.

**Decisions:**
- A scene allocates its own state in `load` and returns it as a pointer, and the manager only hands it back. That keeps scenes independent of one another.
- `draw` renders into the shared render target, which the heat shader puts on screen. `draw_ui` draws on the screen afterwards, so text is never distorted.
- The balloon lab and the lab room each have a button in the top right corner that moves to the other.
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
- It also shows the result of the database check, green when it passed and orange when not. The line is broken to fit the screen, because a loader error that names a path is longer than a phone is wide.
- The scripted demo grabs the tip at frame 90 and lifts it over 45 frames. `swing` sways it after frame 170.

### `layout.odin`
**What it does:** Package `lab`, the chemistry lab as data, in metres. `build` fills a `Layout` with the boxes the room is made of and the footprints a player cannot enter. The room is 24 by 16 with a 3.6 m ceiling. It has long counters along the north, south, and west walls, one island counter in the middle, four rows of ceiling light panels, and a clear east wall for a way in. A counter is a glowing plinth, a dark body, and a light top that overhangs a little. It has no raylib dependency, so it is tested without a window.

**Decisions:**
- Everything is boxes. The floor, walls, and ceiling are slabs lying outside the room, so their outward faces are the ones seen from inside, and no face needs special handling.
- No two boxes share a visible face, and nothing sits closer than 4 cm to a surface it is not meant to touch, so a 16-bit depth buffer on a phone cannot make surfaces flicker.
- Colors, glow, and gloss are constants at the top of the file. The look is a clean light room with dark counters and teal glow, between the dark teal and white clinical references. Changing it is a matter of editing those constants.
- The balloon is not placed yet. Its physics runs at a scale where the balloon is 2 units across, and when it is placed in the lab it will be drawn scaled down.

**Tests:** `lab_test.odin`.

### `player.odin`
**What it does:** A walker seen from above, with a view direction. `player_look` turns the view and keeps the pitch within about 70 degrees. `player_move` walks for one frame at a stick position, and `blocked` says whether a spot is inside a counter or outside the room.

**Decisions:**
- Collision is a circle against rectangles. Each axis is tried on its own, so a diagonal push into a counter slides along it.
- A move is cut into pieces of at most 15 cm, so a long frame on a slow phone cannot carry the player through a counter.
- Yaw 0 faces -z and a positive yaw turns to the right. The stick is limited to a length of 1, so walking diagonally is not faster.

**Tests:** `lab_test.odin`.

### `lab_test.odin`
**What it does:** The layout fits its arrays and every box has a size, glow, and gloss in range. The player starts in the open. Full stick covers the walking speed. A counter stops the player at the right distance and a slanted walk slides along it. The player cannot leave the room in any of six directions. Three long frames in a row do not carry the player through the island. Looking clamps the pitch, and walking follows the view direction.

### `lab_mesh.odin`
**What it does:** Turns the layout into one static raylib mesh with a color for each vertex, and draws it with one call. The first texture coordinate carries how much a surface glows and the second how glossy it is.

**Decisions:**
- One mesh and one call for the whole room is the cheapest thing a phone can draw. Boxes go in already placed in the world, so no model matrix is passed.
- Each face is built from a normal and two tangents that turn toward each other the right way round, which makes the corners come out counter-clockwise seen from outside without any per-face fixing.
- Mesh and material memory comes from raylib's allocator, because `UnloadMesh` frees it.
- If the lab shader fails to compile, the room is drawn with raylib's default shader in flat colors.

### `input.odin`
**What it does:** Reads every finger on the screen as a list of pointers with stable ids, and turns them into movement and look controls. On a phone, the first finger that lands on the left 40 percent of the screen becomes a floating joystick wherever it lands, and a finger that lands elsewhere turns the view. With a mouse there is no joystick and the keyboard walks instead. It also draws the joystick and the scene-switch button.

**Decisions:**
- A finger is tracked by the id Android gives it and not by its index, because the index shifts when another finger lifts.
- A finger that lands on the button is kept out of the controls until it lifts, so a tap on the button never starts the joystick or turns the view.
- The joystick is floating, so a thumb does not have to find a fixed spot. A faint ring shows where it starts.
- A finger that was already down last frame is never re-assigned a role.
- Touch positions on Android come from the C wrapper in `android/entry.c`.

### `scene_room.odin`
**What it does:** The lab room scene. It owns the layout, the player, the room mesh, and the controls. Each frame it reads the pointers, turns the view by the look drag, and walks by the joystick or the keyboard. The camera is at eye height, 1.6 m, with a 70 degree field of view.

**Decisions:**
- First person with a joystick, so the room can be crossed without a pointer tap on a floor spot and so later stations can be reached by walking.
- The clip planes are 0.08 to 70 for the room. The default far plane of 4000 gives a 16-bit depth buffer almost no precision.
- The button in the corner changes scenes, so the balloon lab stays reachable on a phone.

### `lab.vs`
**What it does:** Vertex shader for the room. The mesh is in world space, so positions and normals pass straight through, with the vertex color and the glow and gloss values passed on. There are two versions, `shaders/glsl330/` and `shaders/glsl100/`.

**Decisions:** The two files are kept in step by hand. Both pass `glslangValidator`.

### `lab.fs`
**What it does:** Fragment shader for the room. The lab has no real lights. Shading is a sky-and-floor ambient term, a soft key light from above, full brightness for the ceiling panels and counter glow, a sheen on glossy surfaces that grows at a slant, and fog that fades the far end of the room into the background color.

**Decisions:** Fake lighting costs the same however many lights the room has. The fog color matches the clear color of the room scene, so the far wall fades into the background. Highp precision is used where the device has it.

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

### `mdix_dyn.odin`
**What it does:** Package `store`, the game's local database, and its door to DixScript. `Mdix` holds the 13 DixScript C functions the game calls. `mdix_open` loads the library by file name at run time and looks each function up by name, and `db_get_int` and `db_get_string` read values with their ownership handled.

**Decisions:**
- The library is loaded at run time and not linked at build time. A linked library that is missing or wrong stops the app from starting with no message, and there is no log on the phone. A loaded one fails into a sentence: the loader's own error text, or the name of the function that is missing. Both are shown on screen.
- Only whole numbers and strings cross the boundary. Booleans and floating point numbers passed by value are where C calling conventions on 32-bit ARM differ most, so the game stores a flag as a number.
- The official `mdix-odin` wrapper was read and its signatures were used, but its `foreign import` is a build-time link, so the game keeps its own small table of functions instead.
- The library is never unloaded. Rust libraries that start threads or hold thread-local data do not unload cleanly, and the game needs it until it exits.
- Package `store` has no raylib dependency, so it is tested without a window.

**Tests:** `store_test.odin`.

### `store.odin`
**What it does:** `run_check` proves the database works inside the running game: it loads the library, asks its version, parses a small document, reads values from it, reads the saved profile, builds a new one, saves it, reads it back, and counts the launch. The result is one line of text for the overlay. `File_IO` is how it reads and writes files, so tests can pass memory.

**Decisions:**
- Nothing in the check can stop the game from starting. A failure becomes a line of text and a status.
- Before each risky step, the check writes the step's name to a small file. If the library takes the whole app down, the next launch reads that name, skips the library once and says where it stopped, and then tries again the launch after. A failure the code handled counts as `retry`, not as a crash.
- The saved profile is a DixScript document built by the library and read back by it, so the check covers the same path as every later save.
- If the saved profile cannot be read, the check starts a new one and says so, instead of failing.
- This is a spike. The profile holds only the launch count and the library version so far. Settings, discovered recipes, and saved balloons come after the lab model.

**Tests:** `store_test.odin`.

### `store_test.odin`
**What it does:** Without any library: a missing library is a message and the step file is left at `retry`; a step file that names a real step makes the check skip the library once and then proceed; and `done`, `retry`, and an empty step file are not treated as a crash. With the stand-in library: three launches count up and persist through the file interface, the step file ends at `done`, and an unreadable profile starts over. With the real library: two launches pass the same check. The library tests skip themselves when their environment variable is not set.

### `fake_mdix_ffi.c`
**What it does:** A stand-in for DixScript's C library, about 130 lines, with just the functions the store calls. It understands documents of the form `@DATA( key = 5, name = "text" )` and writes the same form back.

**Decisions:** It exists so the loader, the ownership of strings, and the file round trip can be tested on any machine, including CI, without the real library. It is not a copy of DixScript's behavior.

### `file_io.odin`
**What it does:** Gives the store raylib's file functions, and says where the DixScript library is. On Android raylib writes a name into the app's private storage and reads it back from there, after looking in the APK's assets. On a desktop the name is relative to the working directory. The library is loaded by name on Android, from the folder the APK installs native libraries into, and from next to the executable on a desktop.

**Decisions:** One pair of read and write functions serves both platforms, so no path has to be found in C. DixScript's own file functions are not used, because the Rust library cannot see files inside the APK.

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
- The first scene is the lab room, and `--scene` can pick the other.
- `--fixed-step`, `--demo`, and `--size` exist so headless runs are repeatable and can show a held balloon. They are for CI and screenshots, and the phone never passes them.
- The database check runs before any scene starts, and its result sits in `Game` for the overlay.
- The heat-wobble strength starts at 0 and lives in `Game`. The wobble belongs to blasts, so it is off until something asks for it.

### `android_entry.odin`
**What it does:** Exports `tv_odin_main`, the one procedure the C shim in `android/entry.c` calls. It builds a default context and calls `main`. The file only compiles for the Android target, through the `#+build linux:android` tag, so desktop builds never see it.

**Decisions:**
- The Odin runtime start-up is not run in this build mode. Code on the Android path must not rely on package-level initializers or on `os.args`, which is empty there.
- It also holds the Android `platform_pointers`. The finger count and ids are plain integers, so raylib is called directly for them, but a touch position goes through a C wrapper, like the mouse position does.
- It also holds the Android `platform_mouse_position`, which calls a C wrapper instead of raylib directly. Odin's 32-bit ARM backend returns a struct of two floats in registers, while the NDK returns it through a hidden pointer.

### `platform_desktop.odin`
**What it does:** The desktop version of `platform_mouse_position`, which calls raylib's `GetMousePosition` directly. It compiles for every target except Android, through the `#+build !linux:android` tag. `android_entry.odin` holds the Android version.

### `shaders.odin`
**What it does:** Resolves shader file paths, loads the heat-distortion and balloon shaders, and draws the scene through the heat shader. If the heat shader fails to compile, the scene is drawn without it.

**Decisions:**
- Shader files are found relative to the executable, and `scripts/build_client.sh` copies `client/shaders` next to it. On Android they are read from the APK's assets by relative path.
- Browser and Android builds need the OpenGL ES shaders, so the directory is chosen at compile time by target.
- `draw_scene` takes the wobble strength as an argument.
- `load_lab_shader` loads the room shader the same way as the balloon shader.
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

### `scene_lab.odin` (overlay and wobble)
- The heat-distortion pass ran at full strength all the time, which made the background move even when nothing had exploded. It is now off by default.

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

### `layout.odin`
- None recorded yet.

### `player.odin`
- None recorded yet.

### `lab_test.odin`
- None recorded yet.

### `lab_mesh.odin`
- None recorded yet.

### `input.odin`
- None recorded yet. The joystick and look controls have been compiled for the phone and never touched on one.

### `scene_room.odin`
- None recorded yet.

### `lab.vs`
- None recorded yet.

### `lab.fs`
- None recorded yet.

### `mdix_dyn.odin`
- None recorded yet. The library calls were checked on the desktop only against the stand-in library, and the real library is tested in CI. Neither has run on the phone.

### `store.odin`
- None recorded yet.

### `store_test.odin`
- None recorded yet.

### `fake_mdix_ffi.c`
- None recorded yet.

### `file_io.odin`
- raylib's `SaveFileText` takes its text as a pointer to bytes and not as a C string, which the Odin binding spells `[^]byte`. A cast is needed, and the text it is given must end in a zero byte.

### `selftest.odin`
- None recorded yet.

### `softbody_bench.odin`
- None recorded yet.

### `balloon_test.odin`
- The first zero-gravity test expected the balloon to be perfectly still after one second. It is still easing back from its pre-stretched rest shape, and turns very slowly. The test now allows a small speed and drift after two seconds.
- The full suite took 26 seconds in an unoptimized build with every combination in the parameter sweep. The sweep was trimmed to 24 combinations that still cover each mesh size, substep count, step size, and fill range, and the faster solver loops cut the rest.
