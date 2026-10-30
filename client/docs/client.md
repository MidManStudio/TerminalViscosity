# client

## Overview

The Odin client: window, input, rendering, scenes, and the crafting-lab prototype. It links the Rust simulation through the C ABI in `tv_ffi`. Raylib comes from the `vendor:raylib` package that ships with the Odin compiler (raylib 6.0 in the release used here).

The game is arranged in scenes, as in Unity. There are two scenes. The lab room is the chemistry lab, walked around in first person: a large open room with long counters along the walls and one in the middle. Glass vessels with colored liquid in them stand on the middle counter, ten with one of each stock liquid and the rest empty, and can be picked up, carried in the player's hands, and poured into each other, which makes the liquids react: the held vessel tips over and its liquid runs out as a stream of drops, simulated, into the vessel under the crosshair. A bottle wall along the east side fills a held vessel from a tap for each stock liquid, when the vessel is within half a metre of the nozzle, and the stream is aimed into the vessel's mouth. Four workstations stand on the counters: a sink with a drain on the west side, a fume hood on the north side that takes most of the force out of a blast inside it, and a balloon fill station on the south side, where a balloon hangs by its neck from a clamp under a funnel and is filled by pouring, with a gauge beside it, until it is overfilled and bursts, and a reaction oven on the north side with four ports that each take one liquid, which mixes them inside the machine when it runs, so a violent mixture gives its product and hurts no one. A speed button sets how fast liquid runs, 1, 2, 4, or 8 times normal, for pours, taps, the spout of the oven, and its run. A hot plate and an ice bath on the north counter heat and cool the liquid in a vessel that stands on them, and heat adds to how violent a mixture is while cold takes some of it away. A balloon can be tied off at the fill station and carried in the hand, where it swings from its knot. It can be clamped into the paint station, where the balloon wears a drawing that is made on a tablet beside it, or hung on a hook of the loadout rack, which has three hooks and is the set of balloons that goes into a match. Blasts, spatters, and bursting balloons have a look of their own: fire, sparks, smoke, drops, a ring, a flash of light on the room, a knock to the view, and a wobble of the picture. Some reactions are violent enough to hurt the player and break the vessel, and a menu shows every reaction and which are volatile. The player can also jump. The balloon lab is the balloon on its own: a 3D water balloon that can be grabbed and dragged. Lifting it by its tied tip makes it hang as a teardrop, and dropping it makes it squash and wobble. The lab overlay also shows the result of a start-up check of the local database, which reads and writes DixScript through its C library. The balloon editing menu, the arena, networking, and balloon painting are not started.

Commands, run from the repository root with `cargo` and `odin` on the path:

- `bash scripts/build_client.sh` builds the Rust library and the client into `build/`.
- `build/tv_client --selftest` runs without a window and checks the ABI, the simulation, and the 3D balloon.
- `odin test client/src/lab` runs the lab layout, player, collision, and workstation placement tests.
- `odin test client/src/chem` runs the compound and reaction matrix tests.
- `odin test client/src/mpm` runs the liquid simulation tests.
- `odin test client/src/effects` runs the tests of the look of blasts, spatters, and bursting balloons.
- `odin test client/src/carry` runs the tests for picking up, carrying, and dropping vessels, what a vessel holds, mixing and its blasts, health, the vessel and hand shapes, the hand poses, the balloon fill station and its gauge, the sink, the fume hood, the reaction oven, the speed of liquid, the taps, heat, the loadout, the drawings, and the layout of the drawing screen.
- `odin test client/src/balloon` runs the balloon tests, and `odin test client/src/softbody` runs the older 2D ring tests.
- `odin test client/src/store` runs the local-database tests. Three of them need a DixScript library and skip themselves without one. `TV_MDIX_FAKE_LIB` points at the stand-in built with `cc -shared -fPIC -o libfake_mdix.so client/src/store/testdata/fake_mdix_ffi.c`, and `TV_MDIX_LIB` points at the real DixScript library.
- `odin run client/bench -o:speed` runs the soft-body, balloon, and liquid simulation benchmarks.
- From `build/`, `./tv_client --fixed-step --frames 240 --screenshot lab.png` runs the lab for a fixed number of frames and saves a screenshot. The screenshot path is relative to the working directory. Under a virtual display this works in CI: `xvfb-run -a ./tv_client ...`.
- `--demo hang` and `--demo swing` script the pointer: after 90 frames the tip is grabbed and lifted, and `swing` then sways it side to side. `--fixed-step` advances the game by exactly 1/60 s per frame, so a given frame count always shows the same picture. `--size 1600x720` opens a window of that size, which is handy for trying a phone's wide screen. `--scene room`, `--scene balloon`, or `--scene bench` picks the scene to start in, and the demos only act in the balloon scene. In the lab room a desktop walks with WASD or the arrow keys and looks by dragging the mouse. A small button in the top right corner switches scenes, a button in the bottom right corner grabs the vessel under the crosshair or lets go of the one held, and a jump button sits above it. A pour button sits left of the grab button: held down it tips the held vessel over to pour into the vessel under the crosshair, and it says mix when there is one close enough, fill under a tap, balloon with the crosshair on the fill station, port 1 to 4 with the crosshair on the oven, and pour otherwise. With the crosshair on the oven and nothing held, the grab button says run and starts a run. At the fill clamp, the paint station, and the hooks of the rack, it ties off and takes, clamps, stores, or takes a balloon, and says which. With a balloon in the hand and nothing to do with it, it says full. With a balloon clamped and the crosshair on the tablet beside the paint station, it says paint, and the drawing screen opens: the tablet is the big rectangle on the left, with the 16 colors in two columns beside it and three brushes, undo, and clear under it, and the balloon is in the clamp on the right, where a drag turns it. A done button at the top right is always there. The speed button under the matrix button goes to the next speed, and V does the same on a desktop. On a desktop E grabs, M held pours, R opens the reaction matrix, and space jumps. A button under the sim test button opens the reaction matrix, a menu with a close button that shows which mixes are volatile. A button under the scene switch opens the liquid sim test.

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
- `view_draw_at` draws the balloon moved and scaled by a matrix, which is how the fill station draws a small balloon. The shader works in the balloon's own space, so the eye is given in that space. `hide_knot` leaves the knot out, and `strain` is passed to the shader. Views that share one shader do not unload it, so only the one that owns it does. `view_set_art` puts a drawing on the balloon and `view_clear_art` takes it off. The vertex tangent carries the direction of the vertex at rest.
- The balloon is drawn inside first, then outside, so the far wall shows faintly through the near one with no depth sorting.
- Mesh memory comes from raylib's allocator, because `UnloadMesh` frees it with raylib's free.
- A mesh with 362 vertices was too coarse to show a knot, so the knot is a separate shape. It reaches past the tip vertex, because placed inside the neck it was hidden by the neck's own translucent cone.
- If the balloon shader fails to compile, the balloon is drawn flat with raylib's default shader.
- All the raylib calls here pass the same register layout from Odin as from C on 32-bit ARM, which was checked by comparing Odin's compiled declarations with clang's for every raylib and rlgl function the client calls.

### `scene.odin`
**What it does:** The scene system. `Scene` is five procedures, `load`, `update`, `draw`, `draw_ui`, and `unload`. `Game` holds what every scene shares: the screen size, the heat-shader pass and how strongly it wobbles, the off-screen render target, the current scene and its state, the scripted demo mode, the local database with the result of its check, and the loadout, which is the balloons the player has made and has to outlive a visit to another scene, with the drawings that go with them. `game_switch` asks for another scene, and the switch happens at the end of the frame.

**Decisions:**
- A scene allocates its own state in `load` and returns it as a pointer, and the manager only hands it back. That keeps scenes independent of one another.
- `draw` renders into the shared render target, which the heat shader puts on screen. `draw_ui` draws on the screen afterwards, so text is never distorted.
- The balloon lab and the lab room each have a button in the top right corner that moves to the other. The sim-test scene is a third scene, opened by a button under the scene switch in the lab room, and its button in the top right corner goes back to the lab room.
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
**What it does:** Package `lab`, the chemistry lab as data, in metres. `build` fills a `Layout` with the boxes the room is made of and the footprints a player cannot enter. The room is 24 by 16 with a 3.6 m ceiling. It has long counters along the north, south, and west walls, one island counter in the middle, four rows of ceiling light panels, and a clear east wall for a way in. A counter is 1.1 m high: a glowing plinth, a dark body, and a dark teal top that overhangs a little, which sets it apart from the light floor and holds clear glass and bright liquids well. It has no raylib dependency, so it is tested without a window.

**Decisions:**
- Everything is boxes. The floor, walls, and ceiling are slabs lying outside the room, so their outward faces are the ones seen from inside, and no face needs special handling.
- No two boxes share a visible face, and nothing sits closer than 4 cm to a surface it is not meant to touch, so a 16-bit depth buffer on a phone cannot make surfaces flicker.
- Colors, glow, and gloss are constants at the top of the file. The look is a clean light room with dark teal counters and teal glow, between the dark teal and white clinical references. Changing it is a matter of editing those constants.
- The balloon of the fill station is the one balloon in the lab. Its physics runs at a scale where the balloon is about 2 units across, and it is drawn scaled down, see `filler_view.odin`.
- The box limit is 160. The room, the bottle wall, and the three workstations use about 110 of them.

**Tests:** `lab_test.odin`.
- A counter along the east wall carries the bottle wall, with a way round it at each end. `add_dispensers` adds its rack: a backboard and, for each of ten taps, a bottle in the color of its liquid, an arm, and a nozzle. The colors are passed in, so the bottles match what comes out. `dispenser_nozzle` says where a nozzle tip is, and the carrying code uses it.

### `apparatus.odin`
**What it does:** Package `lab`, where the workstations are and what is static about them, in metres. The sink basin is 50 by 100 cm on the west counter, with a low rim and a drain grate. The fume hood is a bay 1.6 m wide on the north counter, with a back, two sides, a top, and a glowing strip under the top. The balloon fill station stands on the south counter: a base plate, a pole, an arm, a collar that holds the neck of a balloon, a funnel on top of the collar, and the back of a gauge of ten lights beside it. The reaction oven is a box 1.6 m wide and 52 cm high on the north counter, with a funnel for each of its four ports on top, a dark window, a spout out of the front, and places on the front for its lights. The hot plate and the ice bath are two stations side by side on the north counter, a dark plate with a glowing coil and a pale tub with ice in it. The paint station on the west counter is a frame with a clamp that holds the neck of a balloon, a second clamp under its bottom, a palette board of 16 swatches, and a cup of brushes. The loadout rack on the south counter is a board with a hook for each slot and a light over each. `add_apparatus` adds the boxes. The places they act on are constants: `SINK_BASIN`, `HOOD`, `FILLER_CLAMP`, `FILLER_MOUTH`, the capture column, and the box the crosshair tests. `gauge_light` says where each gauge light is, `filler_center` where the round part of the balloon hangs, and `in_rect` whether a point is inside a footprint.

**Decisions:**
- The glass of the hood and the lights of the gauge change from frame to frame, so they are not part of the static room mesh. The client draws them, see `filler_view.odin`.
- The hood glass starts 45 cm above the counter, as a sash that is raised. A vessel and the hands go under it, so the glass never blocks a pour.
- The stand is on the south counter, so a player standing at its edge has the funnel 55 cm ahead and a little above the eye, which is where a held vessel sits. The balloon hangs 40 cm clear of the counter even when stretched.
- The oven is low, with its top at 1.62 m, so its ports are at about the height of the eye and a held vessel pours into them without looking up. Its spout sticks out of the front, so a vessel under it clears the body.
- A vessel counts as standing on the plate or the bath when its middle is inside the footprint and it is resting near the counter top, so a vessel held over them does not heat.
- The paint station is placed so that a balloon of 1000 ml hangs 15 cm below its clamp, which was measured from the soft body, and the second clamp is under where its bottom is at that size. The swatches on the board are stand-ins, and so are the colors on the drawing screen, because the palette is not decided. Swatch 0 is no paint, so there are 15 paints.
- The tablet is a flat panel, twice as wide as it is high, on two short legs beside the clamp, facing a player at the counter. Its screen is not part of the room mesh, because it shows the drawing, so the client draws it.
- The number of hooks is `LOADOUT_SLOTS` here, 3, in one place, because the number is not decided. The rack, its aim boxes, and its lights follow it.
- Nothing here blocks the player. The counters do that already, and the workstations sit on them.

**Tests:** `apparatus_test.odin`.

### `player.odin`
**What it does:** A walker seen from above, with a view direction. `player_look` turns the view and keeps the pitch within about 70 degrees. `player_move` walks for one frame at a stick position, and `blocked` says whether a spot is inside a counter or outside the room.

**Decisions:**
- Collision is a circle against rectangles. Each axis is tried on its own, so a diagonal push into a counter slides along it.
- A move is cut into pieces of at most 15 cm, so a long frame on a slow phone cannot carry the player through a counter.
- Yaw 0 faces -z and a positive yaw turns to the right. The stick is limited to a length of 1, so walking diagonally is not faster.

**Tests:** `lab_test.odin`.
- A jump is a height above the standing eye and a speed, moved by `player_update_air`, which only changes how high the view is. Walking and collision stay as they were. A jump peaks at about 46 cm, well under the 1.1 m counters, so a collision circle on the floor is still right and nothing can be climbed. A second jump cannot start in the air.

### `lab_test.odin`
**What it does:** The layout fits its arrays and every box has a size, glow, and gloss in range. The player starts in the open. Full stick covers the walking speed. A counter stops the player at the right distance and a slanted walk slides along it. The player cannot leave the room in any of six directions. Three long frames in a row do not carry the player through the island. Looking clamps the pitch, and walking follows the view direction. A jump peaks between 40 and 50 cm and lands, there is no jump in the air, and a jump stays lower than a counter. The bottle wall fits over its counter and in the room, and the east counter stops the player but can be walked round.

### `apparatus_test.odin`
**What it does:** The workstations fit in the box limit together with the room and the bottle wall, and every box is inside the room. The basin is on the west counter, the hood on the north counter with a gap under its glass and the glass at the front, and the clamp on the south counter with the balloon hanging clear of it. The funnel is above the clamp, inside the capture column, which stops above the clamp so nothing is taken from under it. The aim box holds the mouth. The gauge lights stack upward beside the funnel, within reach of the eye. The footprints do not overlap. The oven is on the north counter, clear of the hood and low enough to pour into from eye height. Its four ports are in an even row on top, inside its footprint, and in the aim box. Its spout is out in front, with room for a tall bottle under it, and its lights are on the front. The hot plate and the ice bath are on the north counter, apart from each other, the hood, and the oven, and big enough to stand a flask on. The paint station is on the west counter, far from the sink, with a balloon hanging clear of the counter and the aim box holding the clamp and the bottom of the balloon. The palette has 16 different colors, and an index outside it counts as the end. The tablet is twice as wide as high, on the west counter, with its aim box holding the whole screen and apart from the aim box of the clamp, so each is aimed at alone, and clear of the clamp. Swatch 0 is pale, like the rubber. The rack has a hook for each slot over the south counter, with the aim boxes side by side and not overlapping, clear of the gauge, with room for balloons beside each other.

### `chem.odin`
**What it does:** Package `chem`, what the lab liquids are and what happens when two of them meet. It has the compounds (ten stock liquids and eight products), the ten classes they belong to, and the reaction matrix. `react(a, b)` gives the product, the volatility from 0 to 1, and the heat, in either order. The answer has the same shape as `ChemBackend::react` in `tv_sim`, with the product added for the lab. It has no raylib dependency.

**The matrix.** Only classes meet, so a new compound only needs a class. Every pair of classes has exactly one rule, 55 in all. A number after a product is the volatility, and `keeps it` means the other compound stays what it is, only thinned:

| | Neutral | Acid | Base | Fuel | Oxidizer | Cryo | Gel | Lube | Dye | Inert |
|---|---|---|---|---|---|---|---|---|---|---|
| **Neutral** | Water | keeps it | keeps it | Slurry | keeps it | Slush | Sticky | Slick | keeps it | Slurry |
| **Acid** | keeps it | Slurry | Foam 0.25 | Slurry 0.2 | Brew 0.7 | Slush 0.1 | Sticky | Slick 0.05 | Slurry 0.05 | Slurry |
| **Base** | keeps it | Foam 0.25 | Slurry | Slick 0.1 | Brew 0.35 | Slush 0.1 | Sticky | Slick | Slurry 0.05 | Slurry |
| **Fuel** | Slurry | Slurry 0.2 | Slick 0.1 | Slurry | Char 1 | Slurry | Sticky 0.05 | Slick 0.1 | Slurry 0.05 | Slurry |
| **Oxidizer** | keeps it | Brew 0.7 | Brew 0.35 | Char 1 | Slurry | Slush 0.55 | Sticky 0.2 | Slick 0.15 | Slurry 0.15 | Slurry |
| **Cryo** | Slush | Slush 0.1 | Slush 0.1 | Slurry | Slush 0.55 | Slush | Sticky | Slick | Slush | Slurry |
| **Gel** | Sticky | Sticky | Sticky | Sticky 0.05 | Sticky 0.2 | Sticky | Sticky | Sticky | Sticky | Sticky |
| **Lube** | Slick | Slick 0.05 | Slick | Slick 0.1 | Slick 0.15 | Slick | Sticky | Slick | Slick | Slurry |
| **Dye** | keeps it | Slurry 0.05 | Slurry 0.05 | Slurry 0.05 | Slurry 0.15 | Slush | Sticky | Slick | Magenta | Slurry |
| **Inert** | Slurry | Slurry | Slurry | Slurry | Slurry | Slurry | Sticky | Slurry | Slurry | Slurry |

Heat is in the rules too: cryo mixes are cold (below zero) and the oxidizer and fuel reactions are hot. The stock liquids are Water (neutral), Fizz Acid (acid), Soda Base (base), Ember Oil (fuel), Spark Blue (oxidizer), Frost Gel (cryo), Glue Goo (gel), Slick (lube), and Dye Red and Dye Violet (dye). The products are Neutral Foam and Slush (neutral), Sticky Mess (gel), Slick Mess (lube), Char, Slurry, and Acrid Brew (inert), and Magenta (dye).

**Decisions:**
- The danger sits around the oxidizer, Spark Blue. Fuel with oxidizer is the worst blast, at 1.0. Acid with oxidizer is a smaller blast, at 0.7. Base with oxidizer, at 0.35, and cryo with oxidizer, at 0.55, spatter. Everything else is calm. A test fails if any other pair becomes dangerous, so a change is made on purpose.
- Mixing acid and base is safe and makes foam, so there is a harmless reaction to learn from first.
- Gel takes over anything it meets, lube makes a slippery mess, water thins acids, bases, oxidizers, and dyes without changing them, and two dyes blend into a new one.
- Inert products are dead ends. Whatever meets slurry or char becomes slurry, so a bad mix wastes the ingredients, and a vessel holds one compound at a time.
- Unordered pairs of the same compound do not react, and neither does anything with an empty vessel.
- This table is a stand-in. The compound database is planned as DixScript content shared with the server, and these rules will come from there.

**Tests:** `chem_test.odin`.
- `compound_cname` gives a name as a C string, for drawing text without a copy.

### `hazard.odin`
**What it does:** What a reaction does to the player. A volatility below 0.3 is calm, 0.3 up to 0.6 spatters, and 0.6 and over is a blast. `heated` adds what heat does to a volatility: a fully hot liquid adds 0.6, so a pair that is calm in the room blasts, and a fully cold one loses 0.6 of it, so the worst blast is a spatter. A spatter does up to 15 damage and a blast 30 to 100, the most at point blank and falling in a straight line to nothing at the edge: 1.5 m for a spatter, and 2 to 4 m for a blast, larger for a stronger one.

**Decisions:**
- A blast damages the player and breaks the container, as decided. A spatter only stings and throws 20% of the liquid out of the vessel.
- Mixing is done with the vessel in the hands, under a metre from the eye. At 0.8 m the worst blast does 80 damage, which hurts a lot and does not kill from full health, the acid blast does about 32, and a spatter does a few.
- Temperature runs from -1 for fully cold through 0 for the room to 1 for fully hot, and a meeting happens at the temperature of the blend of the two liquids, each counting for its amount. Heat adds and cold multiplies, so heat can make something dangerous that was safe, which was asked for, and cold only tames what is already violent.
- Every number here is a first guess to be tuned by playing.

### `chem_test.odin`
**What it does:** The ids and the table agree, and names are unique. Every pair of classes has exactly one rule, and every product is a known compound. The outcome does not depend on the order. Nothing reacts with itself or with nothing. A reaction always makes a real compound. Water thins acids, bases, oxidizers, and dyes. The known recipes make what they should. Only the planned pairs are dangerous, two blasts and two spatters, all around the oxidizer. Damage falls with distance and grows with volatility, and the worst blast at arm's length hurts a lot but does not kill. Heat only raises volatility and cold only lowers it, both stay between 0 and 1, and the ends count for anything beyond them. A calm pair spatters when warm and blasts when hot, and the worst blast is a spatter when fully cold.

### `effects.odin`
**What it does:** Package `effects`, the look of a violent reaction as data. It holds the particles of a blast, a spatter, or a burst balloon, the rings that spread from it, the one flash of light it throws on the room, how hard it knocks the view, and how hard it wobbles the picture. It decides nothing about the game and has no raylib dependency, so it is tested without a window. `blast`, `spatter`, and `pop` make an effect, `vent` puffs steam from a vent, `steam` makes a wisp of it, `rumble` gives the view a small steady shake, `step` moves everything on, and `tint`, `opacity`, `ring_state`, `light_intensity`, and `look_shake` give the drawing code what it needs.

**Decisions:**
- A blast has five parts: fire that cools from white-yellow through orange to dark red, sparks that fall under gravity, smoke made dark from the colors of the two liquids that met, drops of those two liquids, and a ring. A spatter is drops of the liquid and a little mist, with a faint light and no ring. A burst balloon is drops in the color of its liquid, mist, and a small ring.
- The power of a blast sets its size: more particles, a ring from 1.5 to 4 m, which is the range of its damage, a harder knock, and a wider, brighter light.
- `open` runs from 1 in the open to 0 in the fume hood. A contained blast keeps 35 percent of the size and the rest follows `open`, so it is smaller, dimmer, and softer, and still seen.
- The pools are fixed, 220 particles and 6 rings, so nothing is allocated. When the particle pool is full a new particle takes the place of the one nearest the end of its life.
- Only one light is kept, the strongest of those still going, because the room shaders take one. A weaker light does not replace a stronger one that has not faded.
- The random numbers come from a small generator with a fixed start, so a given blast looks the same each time and the tests can be exact.
- Debris is wiped when it falls below the height of what it lands on, which the caller gives as `floor`. Smoke ignores the floor.
- `steam` is a single thin wisp, with no sparks, for a vessel of hot liquid, made a few times a second.
- `vent` is steam that rises, with now and then a spark, for a machine that is running. It throws no light and has no ring. `rumble` only ever raises the shake, so it cannot make a blast weaker.

**Tests:** `effects_test.odin`.

### `effects_test.odin`
**What it does:** A blast makes fire, sparks, smoke, drops, a ring, a light, a knock, and a wobble. A stronger blast is bigger in each of those. A blast in the hood is smaller, dimmer, and softer, but not nothing. Everything ends, and the light, knock, and wobble reach zero. The pool never overflows, and when it is full the particle nearest its end is the one replaced. Liquid falls and is gone at the floor. The same start gives the same blast. A burst balloon is in the color of its liquid. A spatter has no ring and is fainter than the weakest blast. A weaker light does not replace a stronger one until the stronger has faded. Fire cools and fades as it ages. The knock is zero when idle and never more than the shake. A ring spreads and fades. A vent makes steam that rises and throws no light, and a wisp of steam is thin and has no sparks. A rumble only raises the shake.

### `carry.odin`
**What it does:** Package `carry`, the things in the lab room that the player can pick up, in metres. It has no raylib dependency, so it is tested without a window. A `Prop` is a vessel standing on a counter or the floor, holding one compound as an id and an amount in millilitres. Each frame `update` finds the prop under the crosshair, puts the held prop at a hold point in front of the eyes, and lets every other prop fall until it stands on something. `grab` takes the prop under the crosshair when the hands are empty and `release` lets go. `state_of` says whether the hands are idle, reaching, or holding, and that drives the hands, the crosshair, and the grab button. `props_remove` takes a vessel out when it breaks and keeps the held and aimed indices right, `focus` names the vessel the contents label is about, and `far_to_near` orders the props for drawing see-through glass. The view follows the player's eye, so it rises with a jump. While the pour button is down the held vessel tips over, to 137 degrees, and comes back when it is released. `update` aims every frame, even while a vessel is held, so the crosshair can pick the vessel to pour into, and `pour_target` is that vessel when it is within 1.5 m and has room.

**Decisions:**
- The crosshair test is a ray from the eye against a box around each prop, padded by 5 cm, with a reach of 2 m. The padding makes small vessels easy to hit when aiming with a thumb. A counter between the eye and a prop hides it.
- One prop is held at a time. A held vessel is held by its middle and tips about it, and is kept above the counters by how far it reaches up and down at its tilt.
- The hold point is 0.55 m ahead, 0.17 m to the right, and 0.20 m below the eye. The held prop is kept inside the room and never lower than the counter top when any part of it is over a counter, so it rests on the counter instead of passing through it. This is a clamp and not a push, so it cannot jam.
- A released prop falls under gravity and stops on the counter top or the floor under any part of its footprint. Props do not collide with each other yet, and a vessel that is only partly over a counter edge stays up on the counter.
- A vessel holds one compound, and an amount above what it can hold is cut down when it is added. A vessel with no compound holds nothing.
- A vessel has the temperature of its liquid, from -1 to 1, 0 for the room. An empty vessel has none.
- `Props.speed` is how many times faster than normal liquid runs, from the list in `stream.odin`. It is set to 1 when the props are set up, and a value that was never set counts as 1.
- Twenty-three vessels stand on the island in five rows along its near edge: one filled with each of the ten stock liquids, so every reaction can be tried, and thirteen empty ones, some in a back row and some at the ends, to pour into and mix in. A test checks that no two overlap.

**Tests:** `carry_test.odin`.

### `vessels.odin`
**What it does:** What a vessel is and what it holds. It has the outline of the space inside each kind of vessel and the maths that follows from that outline: how much a vessel holds, how high a given amount stands, and the height of the surface in the world. The liquids themselves are in `chem`.

**Decisions:**
- Capacity comes from the shape, so the glass and the numbers cannot disagree. Each step of the inside outline is a slice of a cone, so the volume is exact, and the level for a given amount is found by halving the range. A beaker holds about 935 ml, a conical flask about 645 ml, and a bottle about 790 ml, which suits a balloon that holds 1000 ml in total.
- The glass is 6 mm thick, a little thicker than real glassware, so the rim reads on a phone screen.
- The level is worked out for an upright vessel. When pouring tilts a vessel, the surface stays flat in the world and its height has to come from the volume and the tilt, which is the next step.

**Tests:** `carry_test.odin`.
- A tipped vessel is cut by a level plane, because a liquid surface is level in the world, and the amount below the plane is found by adding up 32 slices across the inside. The capacity of a tipped vessel is what lies below the plane through its lowest rim point. The slices make the level right to within a few millilitres, which is enough to draw.

### `mixing.odin`
**What it does:** What happens when a drop of one liquid falls into a vessel. `apply_droplet` adds the drop. When two different liquids meet, they react once for the whole pour: a `Session` remembers the vessel and what is being poured into it, until the drops stop for 0.6 s, and the contents become the product, with the drops that follow in the same pour joining the product as it is. A calm reaction leaves the product, a spatter loses 20% of it and stings, and a blast breaks the vessel and takes the liquid with it. The first drop of a meeting gives a `Mix_Result` saying what happened and how much damage the player takes, from the distance between the eye and the vessel. The reaction is as violent as the matrix says plus what the heat of the meeting adds, see `hazard.odin`, and the contents take the temperature of the blend.

**Decisions:**
- A dangerous pair reacts on the first drop that touches it, as it would on contact, so a blast cannot be avoided by pouring slowly, and the damage does not depend on how much is poured.
- A whole pour is one meeting, so the amount poured sets how much product there is and not how many reactions happen. Acid poured into base makes foam, and not foam turned back into acid by the next drop.
- A second pour after a pause is a new meeting, with the product as what is in the vessel.
- A drop into an empty vessel, or one with the same liquid, simply joins it. A drop into a full vessel is lost.
- The vessel that was poured from is not touched by a blast, and stays in the hands.
- A drop brings its temperature, and the liquid it joins takes the blend of the two, each counting for its amount. A drop into an empty vessel is the drop's own temperature. The meeting happens at the blend before the drop is added, so a hot vessel with a little cold liquid poured in is still hot, and a splash of hot liquid in a cold vessel hardly warms it.
- The rule lives in `mix_into`, which works on any container's contents, so a vessel and the balloon of the fill station react by the same rules. `apply_droplet` is `mix_into` for a vessel, and removes the vessel on a blast. A result says where the reaction happened, which the hood and the look of a blast need.

**Tests:** `carry_test.odin`, and `stations_test.odin` for the balloon.

### `stream.odin`
**What it does:** Liquid in the air: poured from a vessel or let out of a tap, falling, splashing, and either landing in a vessel, which takes it, or on a surface, where it is wiped away after a moment. Each drop is a particle of the liquid simulation, standing for 3.4 ml, in a box of 44 cells of 3 cm that is set in the world when the first drop is made, with its floor on whatever is under it. `pour_flow` lets the held vessel pour, `pour_flow_to` does the same and aims at a given mouth when no vessel is under the crosshair, which is how a pour goes into the funnel of the fill station, `stream_step` runs the simulation, and `stream_capture` hands drops to the vessels they have fallen into. Each drop knows how much liquid it stands for. `stream_spawn_ml` makes one that stands for a given amount, and `stream_spawn` one that stands for 3.4 ml. `SPEEDS`, `flow_speed`, and `speed_cycle` are the speed setting. A drop also knows its temperature, which is that of the vessel it was poured from, and 0 from a tap.

**Decisions:**
- The cell size comes from the first phone benchmark. At 4.3 microseconds a particle each step, a 3 cm cell lets a pour of about twenty drops in flight run in a few milliseconds, and a finer cell does not fit. A pour never has more than 96 drops in flight. When the stream is full, the liquid waits at the lip, so a pour slows down and the frame does not.
- A tipped vessel keeps what it can hold below its lowest rim point, found from the shape, and the rest runs over the lip, as fast as its neck allows: 150 ml a second for a beaker, 90 for a flask, 70 for a bottle. A vessel can tip to 137 degrees, because a narrow neck kept about 24 ml at 100 degrees.
- With the crosshair on a vessel close enough, the drops leave the lip with the velocity of an arc that ends at its mouth, so the stream goes in however the lip is placed. With no target they leave forward from the lip.
- A drop inside a column a little wider than a vessel, reaching 12 cm above its rim, goes in. That is the aim assist of a pour, and it makes a small mouth easy to hit with a thumb. A vessel being poured from does not take drops, and one held upright does, which is how a tap fills it.
- Drops let out in one frame are spread along their way, as if let out at different moments. Two made in one place push each other apart in the simulation, which sent half a pour to the wrong place until a test showed it.
- Liquid at the lip when the vessel is put upright runs back in, and a vessel that runs dry is emptied.
- A speed of 2, 4, or 8 does not make more drops, it makes each drop stand for more liquid. A particle in the simulation does not care how much it stands for, so a faster pour costs the simulation nothing more, and a beaker that lets out 150 ml a second at normal speed lets out 1200 at 8. The capture uses the amount each drop carries. The last of a pour goes as one smaller drop, so none of it is lost.
- Puddles are not kept. A drop is wiped away after lying still for 1.2 s or after 8 s.
- When the floor is more than a metre below the lip, the box floor is in the air, and a drop that reaches it falls out.

**Tests:** `carry_test.odin`.

### `station.odin`
**What it does:** The bottle wall: a tap for each of the ten stock liquids, in the order of their ids. `dispenser_under` finds the tap the held vessel is near enough to be filled from: upright, with room in it, within half a metre of the nozzle sideways, and its top not more than 35 cm over the tip or 90 cm under it. When two taps are near, the nearer one is it. `station_flow_to` lets 110 ml a second out of the nozzle as drops, times the speed, aimed into the mouth of the vessel with `tap_mouth`, and `station_flow` is the same straight down at normal speed. `station_colors` gives the colors of the bottles, from the liquids in them.

**Decisions:**
- The supply is endless. Each tap has an `unlocked` flag that stops it giving anything, as the hook for the progression the lab is meant to have, where not everything is open from the start. Every tap is unlocked for now.
- The pour button fills the vessel near a tap, and tips the vessel over everywhere else, so one button does both. The scene works out which before the button is pressed, so the button shows fill when it can be used.
- A tap used to need the vessel within 12 cm of the point under the nozzle, which asked for the player to stand in the right place to within a hand, and the button only lit up once it was pressed, so the taps seemed not to work. A stream that is aimed into the mouth of the vessel does not need that.

**Tests:** `carry_test.odin`.

### `filler.odin`
**What it does:** The balloon fill station, in package `carry`. A `Filler` is a balloon held by its neck under a funnel. It holds one liquid at a time, as a vessel does, and its fill is its amount over 1000 ml, so a fill of 1 is the natural size of the balloon. `filler_take_drop` takes a drop with the same rule as a vessel, `mix_into`: it joins, or reacts once for the whole pour. A violent reaction bursts the balloon, and so does a fill of 1.35. A burst balloon and its liquid are lost, and two seconds later a fresh balloon is clamped. `filler_capture` takes the drops that have fallen into the funnel column, `filler_aim` says whether the crosshair is on the station, `filler_pour_ready` whether the pour button is ready for it, and `filler_mouth` where a pour is aimed. `strain` runs from 0 at a fill of 1 to 1 at the limit, and `gauge_color` says what color each light of the gauge shows. The balloon has a temperature, like a vessel, and a hot balloon is as dangerous to pour into as a hot vessel. Tying a balloon off is in `loadout.odin`.

**Decisions:**
- The 1000 ml rest volume is the total balloon volume of the simulation crate, so a balloon filled here is a balloon the arena can hold. The limit of 1.35 is the middle of the 130 to 140 percent in the design notes.
- A balloon in the lab has no chambers. Pouring two liquids into it makes them react on the spot, as in the design, and the chamber machine, which would split it first, comes later.
- An overfill only bursts the balloon, with liquid flying, and hurts nobody. A reaction that is a blast hurts as it does in a vessel, from the distance of the eye. That is an assumption.
- A drop that falls into the funnel with no balloon there is lost, and the capture column stops above the clamp.
- The station has a pour session of its own, so a pour into a balloon and a pour into a vessel do not interfere.
- The pour is aimed at the station when the crosshair is on it, close enough, and no vessel is nearer. A vessel under the crosshair wins.
- The gauge runs from empty to the limit in ten lights, green under a fill of 1, amber to 1.2, and red above, so the last lights are the warning.
- There is no way yet to take a filled balloon off the clamp. That belongs to the loadout rack.

**Tests:** `stations_test.odin`.

### `workstation.odin`
**What it does:** What the sink and the fume hood do, in package `carry`. `stream_drain` takes the drops that have fallen into the sink basin, near the counter top, down the drain. `in_hood` says whether a point is inside the hood. `shield_factor` is 1 in the open and 0.2 in the hood, `felt_damage` is the damage of a reaction once that is counted, and `openness` says how open a reaction was, for the size of its look.

**Decisions:**
- The hood takes four fifths of the damage and shrinks the look of the blast. The number is a first guess to tune by playing.
- The reaction itself is the same in the hood. The vessel breaks and the liquid is lost. The hood only protects the player.
- The shield counts the vessel where the reaction happened, not where the player stands, so pouring into a vessel in the hood from outside it is protected.
- The drain only takes drops. A vessel stood in the sink keeps what is in it.

**Tests:** `stations_test.odin`.

### `oven.odin`
**What it does:** The reaction oven, in package `carry`. An `Oven` has four ports, each holding one liquid kept apart from the others, up to 500 ml, and a tank that holds up to 2000 ml. `oven_capture` takes the drops that fall into the funnel of a port. A port takes one liquid at a time, so a drop of another liquid is turned away, and the player is told which port holds what, at most once in 1.5 seconds. `oven_start` begins a run, which takes 6 seconds divided by the speed. `oven_update` ends it: `oven_fold` mixes the ports in order, as a vessel would, the first liquid with the second, that product with the third, and so on. The ports are emptied, and the product waits in the tank. A violent mix gives its product, all of it, and hurts no one, because the oven is shut. `oven_spout_under` finds a held vessel near the spout, by the rule of a tap, and `oven_flow` lets the product out of the spout as drops aimed into its mouth, 110 ml a second times the speed. `oven_aim` says whether the crosshair is on the oven and which port it points at, `oven_pour_ready` and `oven_run_ready` say when the pour and grab buttons are ready for it, and `oven_mouth` is where a pour is aimed.

**Decisions:**
- The oven is how a volatile product can be made at all. In a vessel a blast breaks the vessel and the liquid is lost, so Char and Acrid Brew could never be collected. In the oven the same reaction ends as the product in the tank.
- The ports are mixed in the order of the ports, empty ones skipped. A liquid in two ports is simply added. One loaded port is moved to the tank unchanged, which is also how a port that was loaded by mistake is emptied. The order is an assumption.
- Nothing is lost in a run, not even from a spatter or a blast. The client shows a violent run as a blast at the top of the oven that hurts no one.
- A port takes one liquid until a run empties it, because the ports are meant to be separate. A drop of another liquid is turned away and lost.
- A run cannot start while the tank still holds a product, so a product is not mixed into the next run by accident. The tank is emptied at the spout, or poured away.
- While a run goes the ports are shut and take nothing.
- The run time is divided by the speed, and the flow of the spout is multiplied by it, so the speed setting covers the oven too.
- The tank holds as much as the four ports together, so a run always fits.
- The port a pour is aimed at is the one under the line of the crosshair at the depth of the funnels, and not where the line first meets the oven, so a player looking along the oven from an angle does not get the neighbour.

**Tests:** `oven_test.odin`.

### `art.odin`
**What it does:** The drawings, in package `carry`. A `Canvas` is 256 by 256 pixels, each one of the 16 colors of the palette, as the wire format of the arena has it, and color 0 is no paint, the bare rubber. `canvas_dab` makes one round spot, `canvas_line` a line of them with no gaps, and `canvas_clear` takes it all off. A canvas has a version and the rectangle that has changed, so what shows it can send only that. `Art_Store` holds 16 drawings: `art_new` makes a blank one and gives its id, from 1, and a balloon carries the id of its drawing, so a drawing goes with its balloon wherever it is put. `canvas_to_rgba` turns a rectangle of a drawing into pixels for the screen. `Paint` is the state of drawing: the paint and brush chosen, the stroke in progress, and the last eight canvases to take strokes back with.

**Decisions:**
- The picture goes once round the balloon, left to right, and from the tip to the bottom, top to bottom, taken from the direction of each vertex from the middle of the balloon at rest. It stays on the rubber as the balloon stretches. The left and right edges are the same meridian, so a dab that runs off one comes in at the other.
- The way round the balloon is about twice the way from pole to pole, so a pixel is twice as wide as it is high. The tablet is twice as wide as high for that reason, so what is drawn looks the same on the balloon at its middle, and a round brush is twice as many pixels high as wide. Near the tip and the bottom the picture is pinched, under the clamps.
- Color 0 is no paint and is also the eraser, which leaves 15 paints. The wire format has 16 colors and nothing see-through, so this uses one for it. It is an assumption.
- There are three brushes, 2, 5, and 10 pixels wide, so 4, 10, and 20 high.
- Undo keeps eight canvases, 512 KB, and a clear is a stroke that can be taken back.
- Sixteen drawings can exist at once, a megabyte. A balloon gets its drawing at its first stroke, and the player is told when there is no room. Nothing frees a drawing yet, because a balloon is never thrown away.
- Drawings are not saved or sent anywhere yet. The codec of the arena, in `tv_proto`, is not called from here, and a canvas is the same shape as what it takes.

**Tests:** `art_test.odin`.

### `paint_layout.odin`
**What it does:** Where everything is on the drawing screen, as rectangles, and what a touch is on, in package `carry`, with no raylib in it. `paint_layout` places the palette as two columns down the left, the tablet to the right of it, twice as wide as high and filling half the width or most of the height, the three brushes, undo, and clear under the tablet, a done button at the top right, and the rest of the right side as the balloon. `paint_hit` says what a point is on, `canvas_texel` which pixel of the drawing is under a point, and `balloon_ndc` how far to the side the balloon area is, which is how far the camera has to look aside to put the balloon there.

**Decisions:**
- The buttons are tested first, so a button that is over another area is the one that is pressed.
- Everything is placed from the screen size and keeps its shape, so the same layout does for a phone and a desktop window.
- The done button is large and always there, as every screen must have a visible way out.

**Tests:** `paint_layout_test.odin`.

### `heat.odin`
**What it does:** The hot plate and the ice bath, in package `carry`. `station_heat` says what a vessel is standing on: 1 for the hot plate, -1 for the ice bath, 0 for anything else, when its middle is inside the footprint and it is resting near the counter top. `props_heat_update` moves the temperature of the liquid in every vessel on by a frame: on the plate it rises by 0.2 a second, in the bath it falls by 0.2 a second, and anywhere else, in the hands too, it drifts back toward the room by 0.03 a second. A vessel with nothing in it has no temperature. `heat_word` gives a word for the line under the crosshair: warm and hot above 0.25 and 0.75, cool and cold below -0.25 and -0.75, and nothing near the room.

**Decisions:**
- Full heat takes five seconds on the plate, and the liquid is back to the room in about half a minute, so a mix can be made while it is hot and has to be made soon. Both are first guesses.
- The plate is always on. A switch can come later.
- Only a vessel that is resting heats. One in the hands does not, so the player cannot warm a vessel by holding it over the plate.
- The temperature belongs to the liquid and not to the glass, so an empty vessel has none, and a vessel that is poured out and filled again starts at the temperature of the new liquid.
- What heat does to a reaction is in `hazard.odin`, and how a temperature is blended on mixing is in `mixing.odin`.

**Tests:** `heat_test.odin`.

### `loadout.odin`
**What it does:** The balloons the player has made, in package `carry`. An `Item` is a tied balloon: its liquid, how much, its temperature, and an id for its drawing, which is 0 until there is drawing. A `Loadout` has the balloon in the hand, the one in the paint station, and a balloon for each hook of the rack, which is the set that goes into a match. `loadout_aim` finds what the crosshair is on among the fill clamp, the paint station, and the hooks, the nearest within reach and nearer than any vessel. `balloon_action` says what the grab button would do there: tie off and take at the fill clamp, clamp or take at the paint station, paint at the tablet when a balloon is clamped, store or take at a hook, and nothing while a vessel is held. Painting moves nothing, the scene opens the drawing screen. `balloon_do` does it, and `filler_tie` is what happens at the fill clamp: the balloon is tied, its contents go to the hand, and the station makes another. `loadout_presets` gives what the server needs of each balloon on a hook: the compound, the volume, and the drawing id, which is one chamber of a recipe.

**Decisions:**
- The hands hold a vessel or a balloon, not both. With a balloon in the hand the grab button does not grab a vessel, and says so.
- A balloon that is stretched past full is let down to 1000 ml when it is tied, and the excess is lost, because a recipe is at most 1000 ml in total. The player is told how much.
- A balloon with nothing in it cannot be tied off and taken.
- The drawing is one per balloon, and its pixels are in `art.odin`. Each balloon carries its own id, so each can be painted differently, and the server is sent the drawing of each preset. That follows from the loadout holding balloons that are painted one by one. If the art is to be one per player instead, the id moves out of the item.
- The number of hooks is `LOADOUT_SLOTS` in the lab, set in one place because it is not decided. A preset is made for each hook that holds a balloon, in the order of the hooks.
- Nothing here is saved to disk yet. The loadout and the drawings live in `Game`, so they outlive a visit to another scene, and are lost when the program ends. Saving it goes with the local database, and sending the presets goes with the server.

**Tests:** `loadout_test.odin`.

### `art_view.odin`
**What it does:** The texture a drawing is shown with, in the client. An `Art_Texture` follows one drawing: 256 by 256 pixels, RGBA, with no alpha where there is no paint, made when it is first needed. `art_texture_sync` brings it up to date with a drawing of the store: a different drawing is sent whole, a change to the same one is sent as the rectangle that changed, and nothing is sent when nothing changed. It says whether there is a drawing to show.

**Decisions:**
- The texture has no mipmaps and repeats, so a drawing that wraps round the seam of the balloon has no line in it.
- Only the rectangle that changed is sent while drawing, so a stroke costs as much as the stroke is big.
- One buffer for turning a drawing into pixels is shared by every balloon.

### `paint_view.odin`
**What it does:** The drawing screen, in the client. `paint_touch_update` takes the fingers: a new finger on the tablet starts a stroke and keeps drawing as it moves, held to the edge of the tablet if it leaves it, a new finger on a swatch or a brush chooses it, on undo or clear does that, on done ends the drawing, and on the balloon turns it as it moves. The first stroke on a balloon makes its drawing. `paint_camera` puts the camera close to the balloon in the clamp, looking along the counter, turned aside so that the balloon is in the middle of the part of the screen left for it. `draw_paint_ui` draws the tablet with the drawing on it, the palette with the chosen paint marked and the first swatch crossed out as the eraser, the brushes as dots of their sizes, undo, clear, and the done button.

**Decisions:**
- The drawing is made on a flat picture of the tablet on the screen and not on the balloon, so a finger draws in a rectangle and there is no picking on a curved surface. The balloon wears it as it is drawn.
- A finger that was down when drawing began, or landed on a button, does nothing more, as in the walking controls.
- A drag across the balloon turns it so that the surface follows the finger, about a quarter of the screen height for a radian.
- The turn is only how the balloon is seen. The tablet and the drawing are not turned.

### `stream_view.odin`
**What it does:** Draws the liquid in the air as small diamonds in the color of the liquid, lighter on top and darker underneath. They are drawn by the batch renderer with no lighting, without back-face culling.

**Decisions:** A diamond is eight triangles, so a full stream of 96 is under 2300 vertices, which is cheap on a phone. Spheres drawn one at a time would not be.

### `effects_view.odin`
**What it does:** Draws the effects and gives the room shaders the light of a blast. Two small textures, a soft dot and a ring, are made in code. Particles are squares that face the viewer. Smoke, liquid, and mist are blended over the picture first. Fire, sparks, and the rings are added to it afterwards, so they glow. Nothing writes depth, so particles overlap without cutting each other, and the room still hides them. `blast_light_set` gives a shader the place and reach of the flash, its color, and its brightness, which `lab.fs` and `vessel.fs` add to their lighting. With no blast going the reach and brightness are zero.

**Decisions:**
- The textures are made in code, so there is no image file to package into the APK.
- Squares are drawn as triangles through the batch renderer, as the drops are. A full pool is 220 squares, about 1300 vertices.
- The balloon shader does not take the flash, so a balloon is lit by the room only.
- The flash lights by distance to its point only, with no shadows. A blast behind a counter still lights the room beyond it.

### `filler_view.odin`
**What it does:** Everything on the screen about the balloons and stations that is not static. A `Balloon_Body` is one soft-body balloon at the size of the lab. It is simulated at the size it was tuned for, about one unit across, with its tip pinned at the origin, and drawn scaled down and moved to where it hangs. The scale is chosen so that the rest volume of the soft body takes the volume of 1000 ml, so how big the balloon looks is how full it is. `body_step` sets the fill, shifts the body when the point it hangs from has moved, and steps the simulation while it is still moving, and `body_draw` draws it. `Filler_View` is the body of the fill station. `Loadout_View` has the bodies of the balloon in the hand, the one in the paint station, and one for each hook of the rack, each made ready when an item arrives and costing nothing while its place is empty. A balloon in the hand hangs in front of the player, a little to the right, and swings as the player moves. A body wears the drawing of its balloon, kept up to date by `body_art`. `tablet_draw` draws the screen of the tablet, with the drawing of the balloon in the clamp on it, or dark when there is none. `stations_draw` draws the ten lights of the gauge, a light over each hook in the color of what hangs on it, and the glass of the fume hood.

**Decisions:**
- The balloons have mesh detail 4 and 6 substeps, less than the balloon lab. A body sleeps 1.5 s after its fill last changed, so a balloon at rest costs nothing, and it is stepped at most once a frame. The balloon in the hand is always awake, because it is always moving.
- To make the balloon in the hand swing, the body is drawn at the hand, and each frame it is moved back by how far the hand has moved, so it stays where it is in the world and the pinned neck pulls it along. A move of more than 60 cm in a frame is a jump, as after a reset, and the balloon starts afresh. The neck of the hand body may follow the hand ten times as fast as the others may follow a clamp, or it would lag far behind a walking player.
- Every body but the one of the fill station shares its shader and does not unload it, so one shader is loaded for seven balloons.
- An empty balloon is drawn at 55 percent of its rest volume, so it looks limp. Squeezing the soft body to a fraction of its volume would make it crumple.
- The knot is hidden. A balloon being filled is open at the neck, and the collar covers its top. A tied balloon in the hand, the paint station, or a hook is drawn the same way, so none of them has a knot yet. That is a gap to fix when the tie is shown.
- Near the limit the rubber goes thin and pale, from a `strain` value in the balloon shader, and the red lights of the gauge blink.
- The gauge and the hood glass are drawn each frame because the fill changes. The glass is blended, comes last, and writes no depth.

### `oven_view.odin`
**What it does:** The parts of the reaction oven that change from frame to frame, drawn over its front: a light for each port in the color of the liquid in it, brighter the fuller the port, dark when empty; a light for the product in the tank; a glow in the window that pulses while a run goes; and a strip of ten lights that fills as the run goes on. The static box, funnels, and spout are in the room mesh.

**Decisions:**
- The lights are flat boxes drawn without lighting, as the gauge of the fill station is, so they read at any distance and in any light.
- The glow in the window is a sawtooth and not a smooth wave, because it is cheap and looks busy.

### `menu_ui.odin`
**What it does:** The reaction matrix menu, opened from the matrix button under the sim test button, or R on a desktop. It is a panel over the lab with a title, a key, and a grid of the ten stock liquids against each other. Each cell is green for no volatile, amber for a spatter, and red for volatile, which is a blast, with what the two make written in it and a tag on the dangerous ones. Two of the same liquid are gray. A red close button in the top right corner closes it. While it is open the lab is paused.

**Decisions:**
- The grid is worked out from `chem.react` and `chem.hazard_of`, the same as the game uses, so it cannot say something the game does not do.
- Every pair is shown from the start. Hiding what the player has not found yet belongs to the lab's gameplay loop, which comes later.
- The close button is large and red, and the panel has no other way out on a phone, so it cannot be missed.

### `health.odin`
**What it does:** The player's health, from 0 to 100, for what the lab can do to them. A hit lowers it and makes the screen flash red, in proportion to the damage. Health comes back at 8 a second after 4 seconds without a hit, and nothing heals once it reaches zero.

**Decisions:** The numbers are first guesses. A player at zero is knocked out, and the lab room then puts everything back as it was at the start, which keeps a bad mix from leaving the lab without the vessels it needs. That is an assumption to revisit.

**Tests:** `carry_test.odin`.

### `shapes.odin`
**What it does:** Builds meshes as plain arrays (`Shape`) so they can be tested without a window. `lathe_build` turns a profile of radius and height pairs around the vertical axis. For each kind of vessel `vessel_shape` makes the glass, a hollow shell open at the top, `liquid_shape` makes a solid that fills the whole inside, and `cap_shape` makes the cap of a bottle. `box_build` makes the unit cube that the hands are drawn from. The client copies a shape into a raylib mesh.

**Decisions:**
- Each band of a profile has its own vertices, slope, and color, so corners such as the rim, the base, and the shoulder stay sharp while the shading is smooth around the shape.
- One rule decides every normal and every winding: the outward normal of a band is to the right of the direction of travel along the profile. For the glass the profile runs up the outside, across the rim, and down the inside. The tests check each triangle of each shape against its own normals, which stands in for looking at a render.
- The glass and the liquid come from the same outlines, so they always fit. The liquid is drawn 0.6 mm inside the glass so the two never fight over a pixel.
- A shape has a fixed capacity of 512 vertices and 1536 indices. A test fails if one is cut off.

### `hands.odin`
**What it does:** The first-person hands as boxes: for each hand a sleeve, a palm, two finger segments that curl, and a thumb. `hands_update` moves a curl value and a lift value toward the pose for the current state, and `hands_place` turns the parts into world frames for drawing. At rest the hands sit low in the bottom corners with only the fingertips in view. With something in reach the right hand lifts a little. While holding, the right hand closes around the held vessel and the left hand rises a little.

**Decisions:**
- Parts are described in the camera's frame with z toward the viewer, so ahead is negative. That keeps the frame right-handed, so the triangle winding of the cube survives and no part is drawn inside out. A test checks every part in every state.
- The grip follows the vessel's real position and not the ideal hold point, so the hand stays on a vessel that a counter has lifted.
- Every number (wrist spots, segment lengths, curl angles) is a constant in `hand_parts`. They were set without seeing the result on a screen and are expected to need tuning on the phone.
- Matrices are built by hand, because raylib's matrix helpers return a struct, which is not safe to call from Odin on Android.
- A prop is placed turned to face the way the player looks and tipped over toward it, with its frame built from that, so a tipped vessel is drawn in the same pass as an upright one.

**Tests:** `carry_test.odin`.

### `carry_test.odin`
**What it does:** Every shape, the glass, the liquid, the cap, and the box, faces outward, has unit normals, has the expected number of vertices, and stays inside its vessel's size. The view is a right-handed set and rises with a jump. The default props stand on the island without overlapping, hold no more than their capacity, include one of each stock liquid, and thirteen empty vessels. A disc is cut by a line at the right area. The geometry of a tipped vessel agrees with the upright one, holds the same liquid at the level it finds, and holds less the further it tips, nothing at full tilt. The lip is the lowest point of the rim. A tipped prop keeps a right-handed frame. The crosshair picks a second vessel while one is held, close enough and with room. A slightly tipped vessel lets nothing out. A stream goes into the vessel under the crosshair. A calm pour reacts once for the whole pour. Pouring the oxidizer into the oil blasts, hurts, and breaks the vessel. A drop starts a reaction only the first time, and only after a pause does the next start another. A drop into a full vessel is lost and a spatter loses some liquid. A vessel is found under a nozzle only in the right place, a tap fills it with its own liquid, a locked tap gives nothing, and the bottles are the colors of their liquids. A drop lands and is wiped away, one outside the box or in a full stream is refused, and a pour from high over the floor falls out. Removing a vessel keeps the other indices right. Health drops, comes back, and ends at zero. A vessel cannot be filled past its capacity and holds nothing without a compound. Capacities are between 400 and 1000 ml, and a beaker's matches a hand calculation. The level never drops as the amount grows and matches the volume. See-through props are ordered far to near. The crosshair picks a prop it points at, and not one it points over or one out of reach. A counter hides what is behind it. Grabbing takes the aimed prop once. A sweep of positions and view directions near and far from the counters shows that a held prop never enters a counter or leaves the room. A vessel in open space sits at the hold point. Released props fall to a counter or the floor. The hands close and open again, every hand part is right-handed and stays near the eye, an unturned part follows the view, and a turned prop keeps a right-handed frame.

### `stations_test.odin`
**What it does:** A balloon takes drops of one liquid, keeping all of it. A pour of another liquid into it is one meeting, with the product of the pair, and the balloon survives a calm one. Ember Oil with Spark Blue is a blast: the balloon and its liquid are gone, it hurts, drops with no balloon are lost, and a fresh balloon is clamped after two seconds. Filling with water bursts it on the first drop over the limit, once, and no more than a drop past. Strain runs from 0 at a fill of 1 to 1 at the limit. A spatter loses a fifth. A reaction says where it was. The crosshair finds the funnel when looking at it, and not when looking away, too far, or with no balloon. A nearer vessel wins the aim. The pour button is ready for the station only with a vessel held, the station aimed at and close, and no vessel to pour into. A full pour from a held beaker into the funnel puts most of it in the balloon and makes nothing from nothing. Drops pass through the funnel with no balloon, and only drops inside its column are taken. The drain takes what falls in the basin near the counter top, and nothing else. The hood shields only what is inside it, and a blast in the hood hurts a fifth as much as the same blast outside. The gauge lights one after another, from the bottom, and goes from green through amber to red. Speed goes round 1, 2, 4, 8, and an unset speed is 1. A pour into the funnel at eight times normal speed empties the beaker more than three times sooner than at normal speed and delivers as much. A tap fills a vessel that is not under it, and a tap at four times normal speed gives more than two and a half times as much in the same time, and neither makes liquid from nothing. Each test was checked by changing the code on purpose and seeing it fail.

### `oven_test.odin`
**What it does:** A port takes one liquid and turns other liquids away, telling the player once, then again after a while, and the turned away drop is gone. Each port has its own funnel. A full port loses the rest, and only drops inside a funnel are taken. A shut oven takes nothing. A run needs something in a port and an empty tank, and cannot start twice. A run takes its time and then makes the product of the reaction matrix with the amounts added up. A violent mix, which is a blast in a vessel, is safe in the oven and gives its product, with none lost. The ports are mixed in order. The same liquid in two ports adds up, and one port moves over unchanged. Speed shortens a run. The crosshair finds the oven and the port it points at, for each of the four, and not when looking away, too far, or with a vessel nearer. The run and pour buttons are ready only when they should be. A vessel is found at the spout only when there is product, and not when it is too far to the side, far below, tipped, full, or not held. The spout fills a vessel that is off to one side with the product and loses none. A spout at eight times normal speed lets out drops of eight times the size, empties the tank in under a second, and has no more drops in flight than at normal speed. Each test was checked by changing the code on purpose and seeing it fail.

### `heat_test.odin`
**What it does:** A vessel on the hot plate warms by a fifth in a second and is fully hot in about five, and one in the ice bath cools the same way, and neither goes past the ends. A hot vessel taken off cools slowly, and a cold one warms the same way. An empty vessel, a held vessel, one in the air, and one beside the plate take no heat. The words for the temperature change at the right places. A hot drop warms the liquid it joins by its share, and into an empty vessel it is the drop's own temperature. A mix that is calm in the room spatters when warm and blasts when hot, and the worst blast is a spatter when the vessel is fully cold. A pour carries the temperature of the vessel it comes from, and a hot or cold drop that lands in a vessel or the funnel brings its temperature. A hot balloon blasts when acid is poured in, and loses its temperature when it bursts. Each test was checked by changing the code on purpose and seeing it fail, and four gaps that it found in the tests were closed.

### `loadout_test.odin`
**What it does:** The crosshair finds the paint station, each hook, and the fill clamp, and nothing when looking away, when too far, or when a vessel is nearer. The grab button does the right thing at each place: tie and take only with empty hands and something in the balloon, clamp or take at the paint station, store or take at a hook, and nothing when the place or the hand is the wrong way round, or when a vessel is held. Tying takes what is in the balloon, with its temperature, and the station makes another. A stretched balloon is let down to full, and the excess is told. Balloons move between the hand, the paint station, and the hooks with every field unchanged. The presets are what the server needs of the hooks that hold a balloon, with the volume rounded and held to a full balloon, and with the balloon in the hand and the paint station left out. Each test was checked by changing the code on purpose and seeing it fail.

### `art_test.odin`
**What it does:** A dab is a round spot, 5 across to each side and 10 down, with an empty corner. A dab at the seam comes in on the other side, and a dab at the top or bottom is cut off and nothing is outside the canvas. Everything that changed is in the dirty rectangle, the version goes up, and taking the rectangle forgets it. A line leaves no gaps, flat or slanted, and goes straight across the canvas and not the short way round the seam. The eraser takes paint off, and clear takes all of it. Pixels become RGBA with no paint see-through. The store gives out ids from 1, runs out, takes freed ids again, and a reused drawing is blank. A stroke paints with the chosen paint and brush, and moving without a stroke paints nothing. Undo takes strokes back in order, to the eight it keeps, and a clear can be taken back. Each test was checked by changing the code on purpose and seeing it fail.

### `paint_layout_test.odin`
**What it does:** On six screen sizes, everything is on the screen, the tablet is twice as wide as high and big enough to draw on, and nothing covers anything else. A touch is on the thing under it: done, undo, clear, each brush, each swatch, the tablet, the balloon, and nothing in a corner. The edges of the tablet are the edges of the drawing, and a point outside it is not on it. The balloon area is to the right of the middle. The test of overlaps found that the row of brushes had been put halfway up the tablet instead of under it, before it was ever run on a screen.

### `mpm.odin`
**What it does:** Package `mpm`, the liquid simulator for the lab: the Moving Least Squares Material Point Method of Hu et al. (2018) for a weakly compressible fluid, in 3D. Particles carry the liquid and a background grid works out the forces. Each substep sends mass and momentum from the particles to the grid, updates the grid with gravity and walls, and reads velocities back with the affine matrix of APIC. The stress comes from each particle's volume ratio alone and is folded into the transfer, as in section 3.4 of the paper, so no kernel gradient is ever evaluated. It has no raylib dependency. After `sim_init` nothing is allocated, so stepping never touches the allocator.

**Decisions:**
- The simulation is for the lab only: pours, splashes, and liquid in motion. The gameplay balloon does not use it.
- The stiffness is low, a bulk modulus of 1e4 as in the paper's water examples, so the liquid is slightly squashy. Real water would need steps far too small. The step must stay under about 0.3 dx / (sound speed + fastest flow), which is about 0.3 ms for 1 cm cells.
- Eight particles to a cell on a lattice, so a block always has the same count and a run always comes out the same on one device. Results are not meant to match between arm32 and x86, so the liquid is a visual only and the server never depends on it.
- The walls are the outer three cells of the grid, and every particle position is forced into the grid each step, written so that even a NaN falls inside. That is what makes it safe to read and write the grid through plain pointers, with no bounds checks, in the hot loops.
- Only the block of the grid that the particles touch is cleared and updated. The first phone run showed the whole 32 cell grid costing 3 ms a step, more than the liquid itself for a small splash, and this removed it. `active_nodes` says how many nodes the last step used.
- The build the phone uses has no optimizer, so the loops are written to need none: the three nodes along z are done together, what does not depend on z is worked out once for the row, and the matrix products are rearranged to sums along the row. The tests keep the original plain version of the step and require the fast one to match it.
- A particle's volume ratio is limited to 0.2 to 5, so one bad step cannot spread.
- Thin glass walls, which the paper handles with CPIC, are not here yet.

**Tests:** `mpm_test.odin`. **Benchmarks:** `client/bench/mpm_bench.odin`.
- `sim_add_particle` and `sim_remove_particle` add and take out one particle at a time, which is how the stream uses it. Removing moves the last particle into the gap, so the order changes.

### `scenario.odin`
**What it does:** The one liquid every benchmark uses: a cube with 6, 8, 10, 12, or 16 particles along each side, so 216 to 4096 particles, centered in a grid of 32 cells and a little above the floor, so it drops and splashes.

**Decisions:** The desktop benchmark and the sim-test scene both use it, so their numbers can be compared.

### `mpm_test.odin`
**What it does:** A block holds two particles to a cell along each side and is cut off at the capacity. The grid receives all the mass. A block in free fall speeds up at gravity. Momentum is conserved without gravity. A block set spinning keeps its spin, which fails if the affine matrix is rebuilt at the wrong scale. A tank of liquid comes to rest, slightly compressed by its own weight. A dropped block splashes and stays inside the grid. The same start gives the same liquid bit for bit. The fast step matches the plain original step to within a millimetre after 200 steps, which fails if a single term of the affine matrix is wrong. Only the block of the grid that the liquid touches is worked on. A particle with a NaN or enormous velocity stays inside the grid. The benchmark cube has the stated particle counts and stays finite. Particles can be added and taken out one at a time.

### `lab_mesh.odin`
**What it does:** Turns the layout into one static raylib mesh with a color for each vertex, and draws it with one call. The first texture coordinate carries how much a surface glows and the second how glossy it is.

**Decisions:**
- One mesh and one call for the whole room is the cheapest thing a phone can draw. Boxes go in already placed in the world, so no model matrix is passed.
- Each face is built from a normal and two tangents that turn toward each other the right way round, which makes the corners come out counter-clockwise seen from outside without any per-face fixing.
- Mesh and material memory comes from raylib's allocator, because `UnloadMesh` frees it.
- If the lab shader fails to compile, the room is drawn with raylib's default shader in flat colors.
- It looks up where the shader takes the light of a blast, and the scene sets it before the room is drawn.

### `input.odin`
**What it does:** Reads every finger on the screen as a list of pointers with stable ids, and turns them into movement and look controls. On a phone, the first finger that lands on the left 40 percent of the screen becomes a floating joystick wherever it lands, and a finger that lands elsewhere turns the view. With a mouse there is no joystick and the keyboard walks instead. It also draws the joystick and the scene-switch button. The controls take a list of button boxes, such as the scene switch and the grab button, and report which one a finger pressed.

**Decisions:**
- A finger is tracked by the id Android gives it and not by its index, because the index shifts when another finger lifts.
- A finger that lands on a button is kept out of the controls until it lifts, so a tap on a button never starts the joystick or turns the view.
- The joystick is floating, so a thumb does not have to find a fixed spot. A faint ring shows where it starts.
- A finger that was already down last frame is never re-assigned a role. The same goes for a finger that was already down when the scene started, so the tap that switched scenes cannot press the button of the new one.
- Touch positions on Android come from the C wrapper in `android/entry.c`.
- `held` says which button a finger is still down on, for the pour button, which does its work while it is held. `pressed` is still only the frame a finger lands.

### `scene_room.odin`
**What it does:** The lab room scene. It owns the layout, the player, the room mesh, the controls, the props, the hands, the stream of liquid, the bottle wall, and the health. Each frame it reads the pointers, turns the view by the look drag, and walks by the joystick or the keyboard. The pour button held down either fills the held vessel from the tap it is under or tips it over to pour. The liquid is let out, simulated, and taken by the vessels it falls into, and a reaction that a pour starts is shown and takes its damage. The grab button, or E on a desktop, grabs or releases, and the jump button, or space, jumps. The matrix button, or R, opens the reaction matrix and pauses the lab until it is closed. The room is drawn first, then the hands and the bottle caps, then the liquid in the air, then the liquid in the vessels, then the glass blended over it all. The camera is at eye height, 1.6 m, with a 70 degree field of view. It also owns the effects, the fill station, the reaction oven, and the views of the balloons in the hand, the paint station, and the rack; the balloons themselves are in the loadout in `Game`. The grab button does the balloon action under the crosshair first, then the oven run, and otherwise grabs and lets go, and with a balloon in the hand it refuses to grab and says so. Every vessel is warmed or cooled by what it stands on each frame, and a hot one gives off steam. While drawing, the lab waits: the fingers draw, choose, and turn the balloon, and the camera is close to the balloon in the clamp, turned to put it on the right of the screen, with the hands left out. The drawing screen replaces the usual buttons. The pour is aimed at the funnel when the crosshair is on the station. A reaction in a vessel or the balloon is shown with the effects, takes its damage less what the hood stops, and a burst balloon sends liquid flying. The blast light is given to the room and vessel shaders before drawing, the camera is knocked by the shake, and the wobble of the picture follows the blast. The balloon is drawn after the liquid and before the glass, then the gauge, the hood glass, and the lights of the oven, then the effects. The pour chain is: a tap or the spout of the oven when the held vessel is near one and the button is down, then the vessel under the crosshair, then the funnel of the fill station, then a port of the oven, and then a plain pour. A run of the oven puffs steam and rumbles the view a little, and its end shows as a blast at the top of the oven that hurts no one, or a spatter, or just a line, by how violent the worst reaction was. At zero health the player is knocked out and the lab is put back as it was.

**Decisions:**
- First person with a joystick, so the room can be crossed without a pointer tap on a floor spot and so stations can be reached by walking.
- The clip planes are 0.08 to 70 for the room. The default far plane of 4000 gives a 16-bit depth buffer almost no precision.
- The button in the corner changes scenes, so the balloon lab stays reachable on a phone.
- The liquid takes as many substeps as a real-time frame needs, or fewer if they would take more than 5 ms, going by how long a step took lately. Then the liquid runs a little slower than real time and the frame is not late.
- The view is knocked by turning the point it looks at a little to the side and up, so the world shakes and the hands do not.
- With the matrix menu open nothing in the lab moves, and the finger that closes it is ignored until it lifts, so closing the menu does not start the player walking.

### `scene_bench.odin`
**What it does:** The sim-test scene. It times the liquid simulation on the device itself at five particle counts, six substeps a frame so the screen keeps moving, and shows for each count the grid nodes used and the cost. When it finishes it fits a straight line through the smallest and largest count to get the cost of one particle and the fixed cost of the grid, and shows what that allows for a 125 ml splash at 1, 2, and 3 cm cells. A tap runs it again, and the button in the top right corner goes back to the lab room.

**Decisions:**
- It runs on the phone because desktop numbers say little about it. On a desktop the same code is about six times slower built with `-o:minimal`, which is what the phone build uses, than with `-o:speed`.
- Six substeps in one frame keeps every frame short, so Android never thinks the app has hung, even on a very slow device.
- The first two batches of each count are warm-up, and the middle of the rest is taken.
- The build mode is shown at the top, so a run built with `TV_OPT=size` can be compared with one built without it.
- In the estimate, twice the cell size is eight times fewer particles and half the steps, and the grid cost falls with the cube of the cell size. Real time at 0.3 ms steps needs 56 substeps in a 60 Hz frame. The budget is 6 ms of the 16.7 ms frame.
- The text is formatted into a buffer on the stack, so the screen allocates nothing.
- The scene is a measuring tool. Its button comes out once pouring uses the simulation.

### `prop_mesh.odin`
**What it does:** Copies the shapes from `carry` into raylib meshes and draws them: for each kind of vessel its glass and the liquid inside it, the cap of a bottle, and a unit cube in glove blue and in sleeve white for the hands. Drawing is in passes. Hands and bottle caps are solid and use the room's material. Liquid is drawn next with the vessel shader, cut off at a flat surface in world space, with back faces on so the cut shows as the surface. Glass is drawn last, from the farthest vessel to the nearest, blended over everything behind it and without writing depth, so glass behind glass still shows. If the vessel shader fails to compile, the glass is drawn solid with the room's shader and there is no liquid. It also looks up where the vessel shader takes the light of a blast.

**Decisions:**
- The matrix for each piece is built by hand. Raylib's `Matrix` in the Odin binding is row-major, with the move in the last column.
- Mesh memory comes from raylib's allocator, because `UnloadMesh` frees it.
- The hands and the held vessel are depth tested with the room, and the hands are drawn before the glass, so fingers behind a vessel are hidden by it and fingers in front of it are not. The cost is that a hand can poke into a counter when the player looks steeply down very close to it. A separate depth pass for the hands would fix that if it shows.
- The liquid is drawn opaque, so it needs no sorting.

### `interact_ui.odin`
**What it does:** The 2D pieces of carrying, pouring, and jumping: the crosshair dot with a hand icon under it, lines about the vessel in view or in hand, the grab button in the bottom right corner, the jump button above it, and the pour button to its left. The icon is an open hand in white while nothing is in reach, in teal when something is, and a closed fist while holding. The lines name the liquid and say how full the vessel is, and with a vessel held and another under the crosshair, close enough, they add what is in that one. The grab button says grab, and release while holding, and is dimmer when nothing is in reach. The pour button is held down. It says mix and is bright when there is a vessel to pour into, fill under a tap, and pour and dim when it would only spill. The jump button is dimmer in the air. At the top are a health bar and, for a moment after a hit, a red flash over the whole screen, a white-hot one for a blast or spatter, and a message saying what a mix made. A small button under the scene switch opens the liquid sim test. With the crosshair on the fill station, a line says what the balloon holds and how full it is, in teal turning to red as it nears bursting, and the pour button says balloon.

**Decisions:**
- Grabbing on a phone is a button that turns into the release button while holding, as decided in the design discussion.
- Pouring is a held button. The target is the vessel under the crosshair within 1.5 m, and that is what makes the button bright. The first version asked for the held vessel to be directly over the target, which was hard to line up and gave no hint, so it was changed.
- Buttons have a dark backing, a bright edge, and a shadowed label, so they read on the light floor and walls as well as on the dark counters.
- The icons are drawn from rounded rectangles in code, so no image files have to be packaged into the APK.
- The icons are opaque with a dark outline, so overlapping pieces do not blend twice and the icon reads on light and dark surfaces.
- The contents lines are built in a buffer on the stack, so nothing is allocated each frame.
- The balloon line is not shown when a vessel is the pour target, so two lines never overlap. The oven line shows what each port holds, with the one the crosshair points at in brackets.
- The balloon actions have the grab button too, and it is lit and labelled for what it does here: tie & take, clamp, take, store. A balloon in the hand is told on a line near the bottom of the screen, and a line under the crosshair says what is on the paint station or a hook.
- The contents line adds warm, hot, cool, or cold when the liquid is far from the room.
- Billboards, which the blasts and steam are, are turned to face the camera and not the player, so they are right when the view is shaken and while drawing.
- The speed button is lit when the speed is not normal, and says which. The grab button becomes the run button when the crosshair is on the oven with nothing held and a run could start.

### `lab.vs`
**What it does:** Vertex shader for the room, the vessels, and the hands. The room mesh is in world space and is drawn with an identity model matrix, so its positions and normals pass straight through. Vessels and hands are drawn with a model matrix that moves them, and the shader applies it so the lighting and fog work on world positions. The vertex color and the glow and gloss values are passed on. There are two versions, `shaders/glsl330/` and `shaders/glsl100/`.

**Decisions:** The two files are kept in step by hand. Both pass `glslangValidator`.
- The glass and liquid of the vessels use this same vertex shader, with `vessel.fs` as their fragment shader.

### `lab.fs`
**What it does:** Fragment shader for the room. The lab has no real lights. Shading is a sky-and-floor ambient term, a soft key light from above, full brightness for the ceiling panels and counter glow, a sheen on glossy surfaces that grows at a slant, and fog that fades the far end of the room into the background color. A blast adds light by the square of the distance left to the edge of its reach, from the `blastPos` and `blastColor` values.

**Decisions:** Fake lighting costs the same however many lights the room has. The fog color matches the clear color of the room scene, so the far wall fades into the background. Highp precision is used where the device has it.

### `vessel.fs`
**What it does:** Fragment shader for the glass vessels and the liquid in them. One file serves both, switched by the `liquidMode` uniform. Glass is nearly clear in the middle of a surface, turns more solid toward its edge, and has a bright glint where it catches the light. Liquid is shaded like the room and cut off at a flat surface at the height `levelY`, in world space, in the color `liquidColor`. The liquid is drawn as a closed solid, so where the surface cuts it we see the inside of its far wall, and that is painted as the surface. Both the glass and the liquid take the light of a blast, as the room does.

**Decisions:**
- The cut is made against the world position of each pixel, so when a vessel is tilted for pouring the surface will stay flat in the world with no change to the shader.
- Glass alpha stays at or below 0.88, so even the edge of a vessel shows what is behind it.
- Fog is the same as in `lab.fs`, so vessels far away fade with the room.
- The lighting is the same fake light as the room, so no real light is needed. The GLES 2 version is kept in step with the desktop one by hand.

### `balloon.vs`
**What it does:** Vertex shader for the balloon. The mesh is already in world space, so positions and normals pass straight through. The first texture coordinate carries how much of the knot a vertex is, and the tangent carries the direction of the vertex from the middle of the balloon at rest, which is where a drawing is taken from. There are two versions, `shaders/glsl330/` and `shaders/glsl100/`.

**Decisions:** The two files are kept in step by hand. Both pass `glslangValidator`, and the OpenGL ES 1.00 pair compiled, linked, and rendered the same picture as the desktop pair on a software OpenGL context.

### `balloon.fs`
**What it does:** Fragment shader for latex over water. A soft diffuse term, a broad highlight, and a reflection of a fake sky that grows toward the edge of the shape, where the rubber is seen at a slant. The inside pass is darker and more transparent. The knot is opaque, darker rubber. A `strain` value from 0 to 1 makes the rubber thinner and paler, which is how a balloon near its limit looks. It is 0 in the balloon lab. When the balloon has a drawing, the paint is taken from a texture by the direction of the vertex at rest, once round the balloon by the angle round and once from the tip to the bottom, and bare rubber is see-through. The drawing can be turned round the balloon by a share of a turn. Paint is opaque, and seen from inside it is dim like the rest of the inside pass.

**Decisions:**
- Highp precision is used where the device has it, because a phone defaults to mediump in fragment shaders and the lighting math needs more.
- The highlight is broad and the normals are smoothed once over their neighbors in `update_normals`. A tight highlight showed every ridge of the long thin triangles on a stretched neck.

### `balloon_bench.odin`
**What it does:** Times one 60 Hz step of the balloon, all substeps included, while the tip is held and swung, so the pin, the constraints, and the damping all run. Cases are mesh frequency 4 with 6 substeps, 6 with 8, and 8 with 8, plus a frame for frequency 6 that also builds the render normals. It prints `BENCH balloon_step_f6_s8 <ns>` style lines.

**Decisions:** On the development machine a frequency 6 step with 8 substeps takes about 0.18 ms compiled with `-o:speed`, and about 0.5 ms with `-o:minimal`, the level the Android build uses. A phone core is several times slower, so the lab overlay shows the real cost.

### `mpm_bench.odin`
**What it does:** Times one substep of the liquid simulation at each of the five benchmark particle counts, the median of nine samples of 40 steps, and prints `BENCH mpm_step_<count> <ns>` lines.

**Decisions:** The cost is almost all per particle, so the five counts give a straight line from which the cost of one particle and the fixed cost of the grid can be read. The same cases run on the phone in the sim-test scene.

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
- `load_vessel_shader` pairs the lab vertex shader with `vessel.fs`, so the vessels share the room's way of moving a mesh into the world.

### `heat_distort.fs`
**What it does:** A small screen-space ripple. There are two versions, `shaders/glsl330/` for desktop and `shaders/glsl100/` for OpenGL ES 2 and the browser.

**Decisions:**
- The two files are kept in step by hand. Both pass `glslangValidator`, and the desktop one compiled and ran on a software OpenGL context in a headless test.
- The output alpha is forced to 1. The scene is opaque on screen, and the translucent balloon would otherwise leave a lower alpha in the scene texture.

## CI and Workflows

- `.github/workflows/ci.yml` job `odin` downloads a pinned Odin release, runs `odin check`, the soft-body, balloon, lab, carry, and effects tests, validates all the shader files, builds and runs `--selftest`, and renders headless screenshots of the lab resting and held by its tip, which are kept as an artifact.
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
- The balloon is now also drawn small, at the fill station, with its knot hidden and a strain value in the shader. The balloon lab draws as before. How the small balloon looks has not been seen.

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
- None recorded yet. The box limit was raised from 96 to 160 for the workstations.

### `player.odin`
- A jump changes only the height of the view, and has not been tried on a phone yet.

### `lab_test.odin`
- None recorded yet.

### `chem.odin`
- The damage and volatility numbers have not been played yet. The matrix is a first design, with one blast pair around fuel and one around acid, and it is expected to change after playing.

### `hazard.odin`
- All the numbers are first guesses.

### `chem_test.odin`
- None recorded yet.

### `carry.odin`
- Props do not collide with each other, so two vessels let go at the same spot overlap. A vessel only partly over a counter edge stays up on the counter instead of tipping off.

### `vessels.odin`
- The stock liquid table is a stand-in with fictional names. The compound database will replace it, and the level is only right for an upright vessel until pouring is added.

### `mixing.odin`
- The first version mixed with a button press and wanted the held vessel exactly over the target, which was hard to do and never showed it was ready. It was replaced by the pour, aimed with the crosshair. A blast removes the vessel with no shards or spill.
- The rule was moved into `mix_into` so the balloon of the fill station uses the same one. The earlier tests passed unchanged, and a result now says where the reaction happened.

### `health.odin`
- The knock-out rule, which resets the lab, is an assumption.

### `stream.odin`
- The first pours lost most of their liquid. Drops let out in the same frame were made in the same place and pushed each other apart in the simulation, and the vessel was allowed to tip so far that its lip was inside the counter. Both were found with a test that pours into a vessel and counts what arrives.
- Nothing has run on a phone yet. The drops use the liquid simulation at 3 cm cells, which the benchmark said fits.
- The first speed setting would have meant more drops, and the liquid simulation is the most expensive thing in the lab, so the drops carry more liquid instead. A drop at speed 8 is 27 ml, a big drop to look at, and how that looks has not been seen.

### `station.odin`
- The taps did not work for the first player to try them. They needed the held vessel within about 12 cm of the point under the nozzle, which at a normal standing place is a band of about 19 cm for the player to stand in, and the button did not light until it was pressed. A probe that stood a player at the counter and moved sideways found the band. The window is now half a metre and the stream is aimed into the vessel.
- Every tap is unlocked, and nothing takes a cost for the liquid.

### `stream_view.odin`
- None recorded yet.

### `menu_ui.odin`
- None recorded yet.

### `shapes.odin`
- The vessels were opaque pastel solids at first. They are now see-through glass with liquid, as asked after the first test on the phone.

### `mpm.odin`
- On a desktop, the version with the active block and the unrolled loops is 2.3 times faster per particle than the first, and the grid cost is gone. Only a box of liquid so far: no walls thinner than a cell, no cohesion, and no coupling to the vessels. None of it has run on a phone yet, and the cost there is what the sim test is for.

### `scenario.odin`
- None recorded yet.

### `mpm_test.odin`
- The first version of the tests did not notice a wrong affine matrix scale. Checking it by changing the scale on purpose showed that, and the spin test was added, which does fail.

### `hands.odin`
- The pose numbers were set from the geometry and have not been seen on a screen or a device. Expect to tune the wrist spots and the curl angles after the first look on the phone.

### `carry_test.odin`
- None recorded yet.

### `scene_bench.odin`
- First phone run, built with `-o:minimal` on a Galaxy A13: 10.1 us for each particle and 3.0 ms for the grid, each step, so a 125 ml splash cost 736 ms a frame at 1 cm cells, 46 ms at 2 cm, and 9 ms at 3 cm. That led to the grid being limited to the block in use. The estimate rows assume the grid cost falls with the cube of the cell size. A run built with `TV_OPT=size` has not been seen yet.

### `mpm_bench.odin`
- None recorded yet.

### `prop_mesh.odin`
- The glass is blended without writing depth and sorted by the distance to the base of each vessel, which is right for vessels standing apart and may be wrong for vessels touching. A hand can poke into a counter when the player looks steeply down close to it, because the hands are depth tested with the room.

### `interact_ui.odin`
- The grab button was hard to see over the light counter tops. It now has a dark backing and the counter tops are dark teal.

### `lab_mesh.odin`
- None recorded yet.

### `input.odin`
- The controls took one button box and now take a list. The scene-switch button is index 0 and the grab button is index 1 in the lab room.
- Tapping the button in the balloon scene loaded the lab room and then immediately returned to the balloon scene. The finger was still down when the room started, the room's controls had not seen it before, and it sat on the same corner where the room draws its own button, so it counted as a new press. The controls now start knowing which fingers are already down.

### `scene_room.odin`
- A first check that forced blasts, oven runs, and balloons into the scene put the forcing in the loading code and not the update, because the two have the same lines, so it never ran those paths. It was redone in the update, with a control run that had no drawing and no blasts: that had no red pixels on the screen where the run with the drawing had tens of thousands.
- The carrying, hands, crosshair, and grab button were written and compile for desktop and Android, but have not been seen running on a phone yet.
- The effects, the fill station, the hood, and the sink compile for desktop and for Android with `-o:minimal` and `-o:size`, and the ABI check passes, but none of it has been seen running on a phone.

### `lab.vs`
- The shader now reads the model matrix. The room is drawn with an identity matrix, so its look does not change. The normal is moved with `vec4(normal, 0.0)` and not `mat3(matModel)`, because GLSL ES 1.00 may not accept a matrix built from a matrix.

### `lab.fs`
- None recorded yet. The blast light compiles and validates in both versions but is unseen on a device.

### `vessel.fs`
- None recorded yet. The glass and liquid look has been compiled and validated with glslang for both GLSL versions, but not seen on a device. The blast light was added the same way and is also unseen.

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

### `effects.odin`
- None recorded yet. The size, count, and timing of every part are first guesses. Nothing has been seen on a phone.

### `effects_test.odin`
- The first test of the full pool could not tell the particle nearest its end from any other. Changing the code to replace a fixed one, and then to replace the youngest, still passed. The test now marks one particle nearest its end and one young one, and checks which is replaced.
- The first run of the check that changes the code on purpose used a script with its arguments shifted, so no change was applied and every run counted as a pass. It was redone with a check that the change was applied, and then every change made a test fail.

### `effects_view.odin`
- None recorded yet. Not seen on a phone: how the blended and added particles look together, how large they are on a small screen, and whether the room hides them as it should.

### `apparatus.odin`
- None recorded yet. Nothing has been seen on a phone. The distance from the player's usual place to the funnel and to the sink was worked out from the hold point and not tried by hand.

### `apparatus_test.odin`
- None recorded yet.

### `filler.odin`
- None recorded yet. The limit of 1.35, the two second wait for a new balloon, and the 1000 ml rest volume are assumptions to tune by playing. A filled balloon cannot be taken off the clamp yet.

### `workstation.odin`
- None recorded yet. The fifth that gets out of the hood is a first guess.

### `stations_test.odin`
- The full pour into the funnel passed the first time it ran, which is a reason to doubt it. Turning off the aim at the funnel made it fail, so it does check the aim.
- The first run of the change-on-purpose check applied nothing, as in `effects_test.odin`, and was redone. All twelve changes made at least one test fail.

### `filler_view.odin`
- None recorded yet. Not seen on a phone: the scale of the balloon, how it hangs, how limp it looks empty, how it swells, and what its soft body costs on the old phone. If it is too slow, the mesh detail and the substeps at the top of the file are the first things to lower.

### `oven.odin`
- None recorded yet. The run time, the sizes of the ports and the tank, and the order in which the ports are mixed are first guesses to tune by playing. A liquid in a port cannot be taken out except by a run.

### `oven_test.odin`
- A first test put drops over all four ports at once and found ports 3 and 4 empty. The simulation box is set by the first drop and is a metre and a third wide, which does not hold the whole oven, so a drop outside it is refused. The test now does one port at a time. A pour from a vessel stays near one port, so the game does not meet this.
- The first test of the speed let out no drop in its first frame, because a drop of eight times the size takes two frames of flow to gather. The test now runs two frames before it looks.
- All nineteen deliberate changes to the oven, taps, and speed made at least one test fail.

### `oven_view.odin`
- None recorded yet. The lights have not been seen on a phone.

### `heat.odin`
- None recorded yet. The rates are first guesses, and the plate is always on. Nothing has been seen on a phone, including the steam.

### `heat_test.odin`
- The first run of the change-on-purpose check found four gaps in the tests. Changing where a word for the temperature starts, leaving the temperature out of what a drop brings into a vessel, leaving it out of what the funnel takes, and leaving it in a burst balloon, all still passed. Tests for each were added.

### `loadout.odin`
- None recorded yet. The drawing is one per balloon by assumption, and nothing is saved or sent anywhere yet. The knot is not shown on a tied balloon.

### `loadout_test.odin`
- Every deliberate change to the heat and loadout code made at least one test fail, after the four gaps in the tests were closed.

### `art.odin`
- The first version of `canvas_dab` had code for a dab over the seam that did nothing the rest did not already do, and the change-on-purpose check showed it, because taking it out failed no test. It was taken out.
- Every other deliberate change to the drawing code made at least one test fail.

### `art_test.odin`
- The test of what is outside the canvas first expected less than half of each dab to be left at the edge, and a dab one pixel from the top keeps a little more than half, so it was wrong and not the code.

### `paint_layout.odin`
- None recorded yet. The sizes are first guesses, and nothing has been seen on a phone.

### `paint_layout_test.odin`
- See above: the first run found a real mistake, the brushes under the middle of the tablet.

### `art_view.odin`
- None recorded yet. The cost of sending a rectangle of the drawing on the old phone is not measured.

### `paint_view.odin`
- None recorded yet. The camera numbers, the size of the swatches, the speed of turning, and how it feels with a thumb have not been tried.

