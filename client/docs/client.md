# client

## Overview

The Odin client: window, input, rendering, scenes, and the crafting-lab prototype. It links the Rust simulation through the C ABI in `tv_ffi`. Raylib comes from the `vendor:raylib` package that ships with the Odin compiler (raylib 6.0 in the release used here).

The game is arranged in scenes, as in Unity. There are four scenes: the lab room, the balloon lab, the sim test, and the arena. The lab room is the chemistry lab, walked around in first person: a large open room with long counters along the walls and one in the middle. Glass vessels with colored liquid in them stand on the middle counter, ten with one of each stock liquid and the rest empty, and can be picked up, carried in the player's hands, and poured into each other, which makes the liquids react: the held vessel tips over and its liquid runs out as a stream of drops, simulated, into the vessel under the crosshair. A bottle wall along the east side fills a held vessel from a tap for each stock liquid, when the vessel is within half a metre of the nozzle, and the stream is aimed into the vessel's mouth. Four workstations stand on the counters: a sink with a drain on the west side, a fume hood on the north side that takes most of the force out of a blast inside it, and a balloon fill station on the south side, where a balloon hangs by its neck from a clamp under a funnel and is filled by pouring, with a gauge beside it, until it is overfilled and bursts, and a reaction oven on the north side with four ports that each take one liquid, which mixes them inside the machine when it runs, so a violent mixture gives its product and hurts no one. A speed button sets how fast liquid runs, 1, 2, 4, or 8 times normal, for pours, taps, the spout of the oven, and its run. A hot plate and an ice bath on the north counter heat and cool the liquid in a vessel that stands on them, and heat adds to how violent a mixture is while cold takes some of it away. The balloons the player makes, with their drawings, are saved to a text file when they change and read back when the game starts. A balloon can be tied off at the fill station and carried in the hand, where it swings from its knot. It can be clamped into the paint station, where the balloon wears a drawing that is made on a tablet beside it, or hung on a hook of the loadout rack, which has three hooks and is the set of balloons that goes into a match. Blasts, spatters, and bursting balloons have a look of their own: fire, sparks, smoke, drops, a ring, a flash of light on the room, a knock to the view, and a wobble of the picture. Some reactions are violent enough to hurt the player and break the vessel, and a book has a page for each compound with every reaction that makes or uses it, and which of them are volatile. The player can also jump. The balloon lab is the balloon on its own: a 3D water balloon that can be grabbed and dragged. Lifting it by its tied tip makes it hang as a teardrop, and dropping it makes it squash and wobble. The lab overlay also shows the result of a start-up check of the local database, which reads and writes DixScript through its C library. The balloon editing menu, the arena, networking, and balloon painting are not started.

The fourth scene is the arena, a coliseum with sand in the middle and stands round it, walked in first person, with the balloons of the loadout to throw. It is a thin client. The match is in the Rust simulation, which places the player and flies the balloons, and the scene sends the stick, the heading, and the throws, and draws what comes back. A button under the speed button in the lab room goes there, and a button in the top right corner goes back. The three balloons of the loadout are the three slot buttons, a throw is held to charge and let go to throw, there is a jump button, and with no balloons made there is a plain water balloon to try it with. Other players are drawn as a temporary low-poly character, and the local match has a stand-in bot as a second player that wanders, jumps, and throws balloons, so there is somebody to look at.

Commands, run from the repository root with `cargo` and `odin` on the path:

- `bash scripts/build_client.sh` builds the Rust library and the client into `build/`.
- `build/tv_client --selftest` runs without a window and checks the ABI, the simulation, and the 3D balloon.
- `odin test client/src/lab` runs the lab layout, player, collision, and workstation placement tests.
- `odin test client/src/chem` runs the tests of compound names, hazard levels and damage.
- `odin test client/src/mpm` runs the liquid simulation tests.
- `odin test client/src/effects` runs the tests of the look of blasts, spatters, and bursting balloons, near and far.
- `odin test client/src/character` runs the tests of the temporary character: its shapes, its parts, and how it walks, jumps, and throws.
- `odin test client/src/arena` runs the tests of the match as data: looking, throwing, the charge, the balloons the loadout offers, drawing between ticks, and the shape of the coliseum.
- `odin test client/src/carry` runs the tests for picking up, carrying, and dropping vessels, what a vessel holds, mixing and its blasts, health, the vessel and hand shapes, the hand poses, the balloon fill station and its gauge, the sink, the fume hood, the reaction oven, the speed of liquid, the taps, heat, the loadout, the drawings, and the layout of the drawing screen.
- `odin test client/src/balloon` runs the balloon tests, and `odin test client/src/softbody` runs the older 2D ring tests.
- `odin test client/src/store` runs the local-database tests. Three of them need a DixScript library and skip themselves without one. `TV_MDIX_FAKE_LIB` points at the stand-in built with `cc -shared -fPIC -o libfake_mdix.so client/src/store/testdata/fake_mdix_ffi.c`, and `TV_MDIX_LIB` points at the real DixScript library.
- `odin run client/bench -o:speed` runs the soft-body, balloon, and liquid simulation benchmarks.
- From `build/`, `./tv_client --fixed-step --frames 240 --screenshot lab.png` runs the lab for a fixed number of frames and saves a screenshot. The screenshot path is relative to the working directory. Under a virtual display this works in CI: `xvfb-run -a ./tv_client ...`.
- `--demo hang` and `--demo swing` script the pointer: after 90 frames the tip is grabbed and lifted, and `swing` then sways it side to side. `--fixed-step` advances the game by exactly 1/60 s per frame, so a given frame count always shows the same picture. `--size 1600x720` opens a window of that size, which is handy for trying a phone's wide screen. `--scene room`, `--scene balloon`, `--scene bench`, or `--scene arena` picks the scene to start in, and the demos only act in the balloon scene. In the lab room a desktop walks with WASD or the arrow keys and looks by dragging the mouse. A small button in the top right corner switches scenes, a button in the bottom right corner grabs the vessel under the crosshair or lets go of the one held, and a jump button sits above it. A pour button sits left of the grab button: held down it tips the held vessel over to pour into the vessel under the crosshair, and it says mix when there is one close enough, fill under a tap, balloon with the crosshair on the fill station, port 1 to 4 with the crosshair on the oven, and pour otherwise. With the crosshair on the oven and nothing held, the grab button says run and starts a run. At the fill clamp, the paint station, and the hooks of the rack, it ties off and takes, clamps, stores, or takes a balloon, and says which. With a balloon in the hand and nothing to do with it, it says full. With a balloon clamped and the crosshair on the tablet beside the paint station, it says paint, and the drawing screen opens: the tablet is the big rectangle on the left, with the 16 colors in two columns beside it and three brushes, undo, and clear under it, and the balloon is in the clamp on the right, where a drag turns it. A done button at the top right is always there. The speed button under the book button goes to the next speed, and V does the same on a desktop. On a desktop E grabs, M held pours, R opens the book of reactions, the left and right arrows turn its pages, and space jumps. A button under the sim test button opens the book of reactions, a menu with a close button, a contents page and a page for each compound that shows what makes it and what it goes into, and which of those are volatile. A button under the scene switch opens the liquid sim test.

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
- The balloon lab and the lab room each have a button in the top right corner that moves to the other. The sim-test scene is a third scene, opened by a button under the scene switch in the lab room, and its button in the top right corner goes back to the lab room. The arena is a fourth, opened by the last button in that column, and its button in the top right corner goes back to the lab room too. The lab starts afresh on the way back, as it does from the other scenes, and the loadout is kept.
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

`MAX_BOXES` is 640, up from 256, for the equipment and the shelves. The room takes about half.

**Moved stations:** A `Layout` has an `Xform`, a turn and a move that `add_box` applies to every box added while it is on: the box is turned about the origin by quarter turns (`turn_xz`) and then moved, and an odd number of quarters swaps its width and depth. `placed.odin` builds each station round the origin and sets the transform to where it stands. `counter_areas` gives the floor of the five counters in the order `build` makes them, with a name for each number (`COUNTER_NORTH` and so on), so that the placing of stations and `build` cannot disagree about where a counter is. `build` clears the transform.

### `apparatus.odin`
**What it does:** Package `lab`, where the workstations are and what is static about them, in metres. The sink basin is 50 by 100 cm on the west counter, with a low rim, a drain grate and a faucet: a pipe up the back of the basin, a spout out from its top to over the middle, a tip, and a handle that does nothing yet. The fume hood is a bay 1.6 m wide on the north counter, with a back, two sides, a top, and a glowing strip under the top. The balloon fill station stands on the south counter: a base plate, a pole, an arm, a collar that holds the neck of a balloon, a funnel on top of the collar, and the back of a gauge of ten lights beside it. The reaction oven is a box 1.6 m wide and 52 cm high on the north counter, with a funnel for each of its four ports on top, a dark window, a spout off the right end over a drip tray, and places on the front for its lights. The hot plate and the ice bath are two stations side by side on the north counter, a dark plate with a glowing coil and a pale tub with ice in it. The paint station on the west counter is a frame with a clamp that holds the neck of a balloon, a second clamp, a cradle, under the bottom of the balloon, a palette board of 16 swatches, and a cup of brushes. The loadout rack on the south counter is a board with a hook for each slot and a light over each. The incinerator on the south counter, east of the rack, is a squat furnace 60 cm wide and 42 deep with a hopper on top that a balloon is dropped into, a glowing door and a warning stripe on the front, and a chimney at the back. `add_apparatus` adds the boxes. The places they act on are constants: `SINK_BASIN`, `SINK_NOZZLE` (the tip of the faucet, which is tap number `SINK_TAP`, after the ten of the bottle wall, with `TAP_COUNT` taps in all and `tap_nozzle` giving the tip of any), `HOOD`, `FILLER_CLAMP`, `FILLER_MOUTH`, the capture column, the box the crosshair tests, `INCINERATOR` with its mouth and its aim box, and `paint_cradle` and `incinerator_vent` for the middle of the cradle and the top of the chimney. `gauge_light` says where each gauge light is, `filler_center` where the round part of the balloon hangs, and `in_rect` whether a point is inside a footprint.

**Decisions:**
- The glass of the hood and the lights of the gauge change from frame to frame, so they are not part of the static room mesh. The client draws them, see `filler_view.odin`.
- The hood glass starts 45 cm above the counter, as a sash that is raised. A vessel and the hands go under it, so the glass never blocks a pour.
- The stand is on the south counter, so a player standing at its edge has the funnel 55 cm ahead and a little above the eye, which is where a held vessel sits. The balloon hangs 40 cm clear of the counter even when stretched.
- The oven is low, with its top at 1.62 m, so its ports are at about the height of the eye and a held vessel pours into them without looking up. Its spout is off the right end, over counter that is free, with a tray on the counter under it, so a vessel can stand there to be filled. A first version had the spout on the front, flush with the edge of the counter, where nothing could stand under it.
- A vessel counts as standing on the plate or the bath when its middle is inside the footprint and it is resting near the counter top, so a vessel held over them does not heat.
- The paint station is placed for the balloon as it really hangs. The soft body sags once it has settled, so it reaches 17.6 to 19.2 cm below the clamp at any fill from empty to stretched, and the 15 cm it reaches before it has sagged was the wrong number. `PAINT_DROP` is 0.20, which covers the slackest balloon, and the cradle is 5 cm under that, so it clears the balloon by 3 cm or more. The swatches on the board are stand-ins, and so are the colors on the drawing screen, because the palette is not decided. Swatch 0 is no paint, so there are 15 paints.
- The tablet is a flat panel, twice as wide as it is high, on two short legs beside the clamp, facing a player at the counter. Its screen is not part of the room mesh, because it shows the drawing, so the client draws it.
- The number of hooks is `LOADOUT_SLOTS` here, 3, in one place, because the number is not decided. The rack, its aim boxes, and its lights follow it.
- The incinerator is on the south counter east of the rack, so the balloons are in one corner: made at the fill station, kept on the hooks, and burned at the end of it. It is only a place and some boxes. What burning does is in `loadout.odin`, and how it looks is in `scene_room.odin`.
- The fire in the hopper and the slit in the door are emissive boxes and are always lit. Whether it is burning is shown by the flash and the smoke, not by the boxes.
- Nothing here blocks the player. The counters do that already, and the workstations sit on them.

**Tests:** `apparatus_test.odin`.

`add_apparatus` also builds the racks, the cabinet and the scale, by calling `add_equipment`.
**Moved stations:** `add_apparatus` is `add_apparatus_with` with `default_placed`, and the hot plate, the ice bath and the scale are built by `add_placed` (`placed.odin`), where they stand, and not here.

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

The transform tests check `turn_xz` for each quarter and for more than four, that a box is added as it is given unless the transform is on, that it is turned and then moved with its width and depth swapped for an odd number of quarters, and that `counter_areas` is what `build` makes and `build` clears the transform.

### `apparatus_test.odin`
**What it does:** The workstations fit in the box limit together with the room and the bottle wall, and every box is inside the room. The basin is on the west counter, the hood on the north counter with a gap under its glass and the glass at the front, and the clamp on the south counter with the balloon hanging clear of it. The funnel is above the clamp, inside the capture column, which stops above the clamp so nothing is taken from under it. The aim box holds the mouth. The gauge lights stack upward beside the funnel, within reach of the eye. The footprints do not overlap. The oven is on the north counter, clear of the hood and low enough to pour into from eye height. Its four ports are in an even row on top, inside its footprint, and in the aim box. Its spout is off the right end over free counter, with room for a tall bottle under it and a tray wholly on the counter, and its lights are on the front. The hot plate and the ice bath are on the north counter, apart from each other, the hood, and the oven, and big enough to stand a flask on. The paint station is on the west counter, far from the sink, with a balloon hanging clear of the counter and the aim box holding the clamp and the bottom of the balloon. The cradle of the paint station is lower than a balloon hangs at any fill: the test settles the real soft body at the settings of the station for ten seconds at four fills, and checks that the bottom of it is above the top of the cradle with a centimetre to spare and that `PAINT_DROP` is at least as far as it hangs. The cradle is lower than the bottom of a balloon, clear of the counter, in the aim box of the station, and made of four walls. The incinerator is on the south counter, clear of the fill station and of every hook by their aim boxes, a hand's width past the last hook and short of the bottle wall, its mouth is in its aim box and over its body, its chimney is clear of the ceiling and behind the hopper, and its twelve boxes all stand on the counter. The palette has 16 different colors, and an index outside it counts as the end. The tablet is twice as wide as high, on the west counter, with its aim box holding the whole screen and apart from the aim box of the clamp, so each is aimed at alone, and clear of the clamp. Swatch 0 is pale, like the rubber. The rack has a hook for each slot over the south counter, with the aim boxes side by side and not overlapping, clear of the gauge, with room for balloons beside each other.

### `chem.odin`
**What it does:** Package `chem`, what the lab says about a chemical to the player and to the effects: `compound_name`, `compound_cname` (the same as a C string, for drawing text without a copy) and `compound_color`, from the compound pages. It used to be the placeholder table of ten stock liquids, ten classes and a matrix of 55 rules, and it is now only these three procedures and `hazard.odin`. A compound is the `u16` number it has in package `chemistry`, and what happens when compounds meet is decided there, by the pages.

**Decisions:**
- The names stayed in a package of their own so that the many places that draw a name or a colour kept their calls, and so that `hazard.odin` has somewhere to live.
- The matrix and its tests are gone, with the placeholder compounds. The same pairs do not react the same way: the pages decide.

**Tests:** `chem_test.odin`.

### `hazard.odin`
**What it does:** What a reaction does to the player. A volatility below 0.3 is calm, 0.3 up to 0.6 spatters, and 0.6 and over is a blast. A volatility is how violent the worst event of a reaction was, from `event_volatility` in `mixing.odin`. A spatter does up to 15 damage and a blast 30 to 100, the most at point blank and falling in a straight line to nothing at the edge: 1.5 m for a spatter, and 2 to 4 m for a blast, larger for a stronger one.

**Decisions:**
- A blast damages the player and breaks the container, as decided. A spatter only stings and throws 20% of the liquid out of the vessel.
- Mixing is done with the vessel in the hands, under a metre from the eye. At 0.8 m the worst blast does 80 damage, which hurts a lot and does not kill from full health, the acid blast does about 32, and a spatter does a few.
- What heat does to a reaction is in the pages, as windows of temperature and failure limits, and no longer a number added here: `heated` was removed, with its two constants.
- Every number here is a first guess to be tuned by playing.

### `chem_test.odin`
**What it does:** Names and colours come from the pages, with an empty name and white for none and for a number that is not a compound. The hazard levels start where they are documented. Damage falls with distance and grows with volatility, and the worst blast at arm's length hurts a lot but does not kill.

### `effects.odin`
**What it does:** Package `effects`, the look of a violent reaction as data. It holds the particles of a blast, a spatter, or a burst balloon, the rings that spread from it, the one flash of light it throws on the room, how hard it knocks the view, and how hard it wobbles the picture. It decides nothing about the game and has no raylib dependency, so it is tested without a window. `blast`, `spatter`, and `pop` make an effect, `pop_scaled` makes a burst balloon larger for a viewer far away, `vent` puffs steam from a vent, `steam` makes a wisp of it, `rumble` gives the view a small steady shake, `step` moves everything on, and `tint`, `opacity`, `ring_state`, `light_intensity`, and `look_shake` give the drawing code what it needs.

**Decisions:**
- A blast has five parts: fire that cools from white-yellow through orange to dark red, sparks that fall under gravity, smoke made dark from the colors of the two liquids that met, drops of those two liquids, and a ring. A spatter is drops of the liquid and a little mist, with a faint light and no ring. A burst balloon is drops in the color of its liquid, mist, and a small ring.
- The power of a blast sets its size: more particles, a ring from 1.5 to 4 m, which is the range of its damage, a harder knock, and a wider, brighter light.
- `open` runs from 1 in the open to 0 in the fume hood. A contained blast keeps 35 percent of the size and the rest follows `open`, so it is smaller, dimmer, and softer, and still seen.
- The pools are fixed, 220 particles and 6 rings, so nothing is allocated. When the particle pool is full a new particle takes the place of the one nearest the end of its life.
- Only one light is kept, the strongest of those still going, because the room shaders take one. A weaker light does not replace a stronger one that has not faded.
- The random numbers come from a small generator with a fixed start, so a given blast looks the same each time and the tests can be exact.
- Debris is wiped when it falls below the height of what it lands on, which the caller gives as `floor`. Smoke ignores the floor.
- `pop_scaled` is `pop` with a scale that multiplies the drops, the mist, the ring, the light, and how far from the middle each starts, and the drops fly out at the square root of the scale. At scale 1 it is exactly `pop`. Only a pop of scale 1 or less shakes the view, because one that is larger is one that happens across an arena, and a view that shook for a splash 20 m away would be wrong. A scale of nothing or less is a tenth, so nothing is ever turned inside out.
- `steam` is a single thin wisp, with no sparks, for a vessel of hot liquid, made a few times a second.
- `vent` is steam that rises, with now and then a spark, for a machine that is running. It throws no light and has no ring. `rumble` only ever raises the shake, so it cannot make a blast weaker.

**Tests:** `effects_test.odin`.

### `effects_test.odin`
**What it does:** A pop of scale 1 is exactly a plain pop. A larger pop has larger drops, mist, ring, and light, that start further out and fly faster, a scale of nothing is a tenth and never negative, and a larger pop does not shake the view. A blast makes fire, sparks, smoke, drops, a ring, a light, a knock, and a wobble. A stronger blast is bigger in each of those. A blast in the hood is smaller, dimmer, and softer, but not nothing. Everything ends, and the light, knock, and wobble reach zero. The pool never overflows, and when it is full the particle nearest its end is the one replaced. Liquid falls and is gone at the floor. The same start gives the same blast. A burst balloon is in the color of its liquid. A spatter has no ring and is fainter than the weakest blast. A weaker light does not replace a stronger one until the stronger has faded. Fire cools and fades as it ages. The knock is zero when idle and never more than the shake. A ring spreads and fades. A vent makes steam that rises and throws no light, and a wisp of steam is thin and has no sparks. A rumble only raises the shake.

### `carry.odin`
**What it does:** Package `carry`, the things in the lab room that the player can pick up, in metres. It has no raylib dependency, so it is tested without a window. A `Prop` is a vessel standing on a counter or the floor, holding a mixture: up to eight compounds, each with an amount in millilitres and a purity, at one temperature in degrees, with the unsafe meter that reactions raise. Each frame `update` finds the prop under the crosshair, puts the held prop at a hold point in front of the eyes, and lets every other prop fall until it stands on something. `grab` takes the prop under the crosshair when the hands are empty and `release` lets go. `state_of` says whether the hands are idle, reaching, or holding, and that drives the hands, the crosshair, and the grab button. `props_remove` takes a vessel out when it breaks and keeps the held and aimed indices right, `focus` names the vessel the contents label is about, and `far_to_near` orders the props for drawing see-through glass. The view follows the player's eye, so it rises with a jump. While the pour button is down the held vessel tips over, to 137 degrees, and comes back when it is released. `update` aims every frame, even while a vessel is held, so the crosshair can pick the vessel to pour into, and `pour_target` is that vessel when it is within 1.5 m and has room.

**Decisions:**
- The crosshair test is a ray from the eye against a box around each prop, padded by 5 cm, with a reach of 2 m. The padding makes small vessels easy to hit when aiming with a thumb. A counter between the eye and a prop hides it.
- One prop is held at a time. A held vessel is held by its middle and tips about it, and is kept above the counters by how far it reaches up and down at its tilt.
- The hold point is 0.55 m ahead, 0.17 m to the right, and 0.20 m below the eye. The held prop is kept inside the room and never lower than the counter top when any part of it is over a counter, so it rests on the counter instead of passing through it. This is a clamp and not a push, so it cannot jam.
- A released prop falls under gravity and stops on the counter top or the floor under any part of its footprint. Props do not collide with each other yet, and a vessel that is only partly over a counter edge stays up on the counter.
- A vessel holds a mixture, and an amount above what it can hold is cut down when it is added. `props_add` pours one compound in at room temperature and the purity it has out of the lab's bottles (`stock_purity`: tap water 0.25, every other chemical 1). A vessel with nothing in it holds nothing, and has no temperature.
- A vessel has the temperature of its liquid, in degrees, 20 for the room. An empty vessel has none.
- `Props.speed` is how many times faster than normal liquid runs, from the list in `stream.odin`. It is set to 1 when the props are set up, and a value that was never set counts as 1.
- Twenty-three vessels stand on the island in five rows along its near edge: one filled with each of the four chemicals the lab starts with (water, acetic acid, ethanol and sulfuric acid), and nineteen empty ones, some in a back row and some at the ends, to pour into and mix in. A test checks that no two overlap.

**Tests:** `carry_test.odin`.

**Vials and the equipment.** `Vial` is a fourth kind of vessel, a straight glass tube 1.6 cm in radius and 11 cm high that holds about 33 ml and lets out at most 25 ml a second. `standing_height` says where a prop stands: on the plate of the scale if its middle is over it, in the hole of a vial rack if it is a vial exactly in one, and otherwise on whatever `support_height` says. `vial_snap` draws a vial that has been let go of into the nearest free hole within 3 cm, and it runs every step for every prop that is not held. A vial gets `VIAL_AIM_PAD`, 0.8 cm, round it for the crosshair and not the 5 cm of the other vessels, so that two vials in neighbouring holes, 5 cm apart, do not have overlapping boxes. 24 empty vials start in the racks, in the row nearer the player. `MAX_PROPS` rose from 24 to 64.

**Decisions:**
- The holes draw a vial in by what is under it and not by a drop of the hand's height, so a vial let go of in the air over a hole falls into it.
- A vial in the row behind another is reached after the front one is taken out, as in a real rack, so the vials start in the near row.
**Moved stations:** The props carry `placed`, which says where the stations stand, and `standing_height` and `settle` take it, so that the plate of a scale lifts the vessels on it where the scale is now, turned as it is turned.

### `vessels.odin`
**What it does:** What a vessel is and what it holds. It has the outline of the space inside each kind of vessel and the maths that follows from that outline: how much a vessel holds, how high a given amount stands, and the height of the surface in the world. The compounds are in `chemistry`.

**Decisions:**
- Capacity comes from the shape, so the glass and the numbers cannot disagree. Each step of the inside outline is a slice of a cone, so the volume is exact, and the level for a given amount is found by halving the range. A beaker holds about 935 ml, a conical flask about 645 ml, and a bottle about 790 ml, which suits a balloon that holds 1000 ml in total.
- The glass is 6 mm thick, a little thicker than real glassware, so the rim reads on a phone screen.
- The level is worked out for an upright vessel. When pouring tilts a vessel, the surface stays flat in the world and its height has to come from the volume and the tilt, which is the next step.

**Tests:** `carry_test.odin`.
- A tipped vessel is cut by a level plane, because a liquid surface is level in the world, and the amount below the plane is found by adding up 32 slices across the inside. The capacity of a tipped vessel is what lies below the plane through its lowest rim point. The slices make the level right to within a few millilitres, which is enough to draw.

A vial has the inside of a beaker.

### `mixing.odin`
**What it does:** What happens when a drop falls into a container. `mix_into` puts a drop of a compound, an amount, a purity and a temperature into a container's `chemistry.Mixture`, up to its capacity, and then `react` lets the mixture react by the pages and says what happened as a `Mix_Result`: `kind` (nothing, mixed, spatter or blast), what the container mostly held and what was poured in, the first thing a reaction made, how violent the worst event was, the temperature after, the damage to the player, where it happened, and the steps for the book. A reaction that runs quietly is `Mixed`. A splash, fumes or fire is a `Spatter`, which loses a fifth of every ingredient and stings. A burst is a `Blast`, which breaks the container. The damage comes from the violence and the distance between the eye and the container, see `hazard.odin`. `apply_droplet` is `mix_into` for a vessel, standing on the station it is on (`station_of`: the hot plate is a hot bath and the ice bath a cold bath) and breaking it on a blast. `fill_with`, `ml_of`, `main_of` and `stock_purity` are the small things every other file asks of a container.

**Decisions:**
- The pages say what happens. Nothing here knows a compound: `chemistry.settle` finds the reaction by what is in the container, its purity, its shares, its catalyst, its station and its temperature, and runs it.
- How violent an event is, for the old three levels of hazard: a splash 0.45, fumes 0.4 and fire 0.55 are spatters, and a burst is 0.65 plus 0.35 of the unsafe meter, which is a blast. These are first guesses, and fire and fumes are spatters for now because the gear that the pages ask for (masks, extinguishers, shields) is not built.
- A reaction with no outputs, such as water and ethanol, is `Mixed` once, and stays done while its conditions hold, so a long pour does not warm the vessel with every drop. This replaced the old `Session`, which made a whole pour one meeting.
- A reaction that runs because of a pour is shown the moment it starts, which is when the shares first come within the tolerance of the page, so acid poured into water reacts when the acid is a tenth of the mix and not at the first drop. Water poured into acid splashes when the mix first comes to the right proportions, which is the wrong order.
- A drop into a full container is lost, and one that does not wholly fit is cut to the room there is.
- A drop brings its temperature, and the mixture takes the blend by volume. A drop into an empty container is the drop's own temperature.
- The vessel that was poured from is not touched by a blast, and stays in the hands.
- The rule lives in `mix_into`, which works on any container's contents, so a vessel, the balloon of the fill station and the tank of the oven react by the same rules. A result says where the reaction happened, which the hood and the look of a blast need.
- Gases that a reaction makes are kept in the container like the liquids, as millilitres, because phases are not modelled.

**Tests:** `carry_test.odin`, and `stations_test.odin` for the balloon.
**Moved stations:** `station_of` takes the stations the same way, and `apply_droplet` gives it those of the props, so a drop reacts by the station the vessel stands on now.

### `stream.odin`
**What it does:** Liquid in the air: poured from a vessel or let out of a tap, falling, splashing, and either landing in a vessel, which takes it, or on a surface, where it is wiped away after a moment. Each drop is a particle of the liquid simulation, standing for 3.4 ml, in a box of 44 cells of 3 cm that is set in the world when the first drop is made, with its floor on whatever is under it. `pour_flow` lets the held vessel pour, `pour_flow_to` does the same and aims at a given mouth when no vessel is under the crosshair, which is how a pour goes into the funnel of the fill station, `stream_step` runs the simulation, and `stream_capture` hands drops to the vessels they have fallen into. Each drop knows how much liquid it stands for. `stream_spawn_ml` makes one that stands for a given amount, and `stream_spawn` one that stands for 3.4 ml. `SPEEDS`, `flow_speed`, and `speed_cycle` are the speed setting. A drop is one compound, with its purity and its temperature in degrees: the temperature of the vessel it was poured from, and the room's from a tap. A pour from a mixture is made of drops drawn from it in the proportions of the mixture (`chemistry.mix_draw`), so what lands is what was poured. Each drop also has a `seq`, the order it was made in, which survives the swaps of removing one, and `stream_mouth` notes where liquid last came out (the lip of the vessel being poured, the tip of a tap, or the oven's spout), with `mouth_age` the seconds since, for the jets that `jet.odin` makes. A drop that has lain still for 0.08 s becomes liquid in a puddle (`spill.odin`), once, and so does a drop that falls out of the box over the edge of a counter, after the time it takes to fall to the floor under it. The stream keeps the puddles and the lab it was made in.

**Decisions:**
- The cell size comes from the first phone benchmark. At 4.3 microseconds a particle each step, a 3 cm cell lets a pour of about twenty drops in flight run in a few milliseconds, and a finer cell does not fit. A pour never has more than 96 drops in flight. When the stream is full, the liquid waits at the lip, so a pour slows down and the frame does not.
- A tipped vessel keeps what it can hold below its lowest rim point, found from the shape, and the rest runs over the lip, as fast as its neck allows: 150 ml a second for a beaker, 90 for a flask, 70 for a bottle. A vessel can tip to 137 degrees, because a narrow neck kept about 24 ml at 100 degrees.
- With the crosshair on a vessel close enough, the drops leave the lip with the velocity of an arc that ends at its mouth, so the stream goes in however the lip is placed. With no target they leave forward from the lip.
- A drop inside a column a little wider than a vessel, reaching 12 cm above its rim, goes in. That is the aim assist of a pour, and it makes a small mouth easy to hit with a thumb. A vessel being poured from does not take drops, and one held upright does, which is how a tap fills it.
- Drops let out in one frame are spread along their way, as if let out at different moments. Two made in one place push each other apart in the simulation, which sent half a pour to the wrong place until a test showed it.
- The liquid that is to leave over the lip is counted apart, and each drop is drawn from the mixture as it is made. Put upright again, what was waiting to leave stays in, and a vessel that runs dry is emptied.
- A speed of 2, 4, or 8 does not make more drops, it makes each drop stand for more liquid. A particle in the simulation does not care how much it stands for, so a faster pour costs the simulation nothing more, and a beaker that lets out 150 ml a second at normal speed lets out 1200 at 8. The capture uses the amount each drop carries. The last of a pour goes as one smaller drop, so none of it is lost.
- Puddles are not kept. A drop is wiped away after lying still for 1.2 s or after 8 s.
- When the floor is more than a metre below the lip, the box floor is in the air, and a drop that reaches it falls out.

**Tests:** `carry_test.odin`.

A vial lets out at most 25 ml a second, a narrow neck being slow.

### `station.odin`
**What it does:** The taps of the lab. The bottle wall has a mount for each of ten taps, and a tap gives liquid when a dispenser with a compound in it is mounted there (`station_sync`, in `stock.odin`). The lab starts with a dispenser of each of the chemicals it starts with except water on the first three mounts, in the order of their numbers (acetic acid, ethanol, sulfuric acid), and the other seven mounts empty. The faucet of the sink is one more tap, the eleventh, and it gives water. `dispenser_under` finds the tap the held vessel is near enough to be filled from: upright, with room in it, within half a metre of the nozzle sideways, and its top not more than 35 cm over the tip or 90 cm under it. When two taps are near, the nearer one is it. `station_flow_to` lets 110 ml a second out of the nozzle as drops, times the speed, aimed into the mouth of the vessel with `tap_mouth`, and `station_flow` is the same straight down at normal speed. `station_colors` gives the colors of the bottles, from the liquids in them, and grey for a tap with nothing in it.

**Decisions:**
- The supply is endless. Each tap has an `unlocked` flag that stops it giving anything, as the hook for the progression the lab is meant to have, where not everything is open from the start. The first three taps of the wall and the faucet are unlocked, and the rest have no compound and give nothing. Water from the faucet is tap water, at a purity of 0.25, and the chemicals of the wall come pure.
- Water has no tap on the bottle wall, as the locked design says: it comes from the sink. The lab still starts with a vessel of each of the four chemicals, water among them, so that every mix can be tried before the player has walked to the sink. The faucet is a tap like the others, so a vessel under it is found and filled in the same way, and the pour button reads fill there as well. It runs only into a held vessel: nothing runs into the basin with no vessel.
- The pour button fills the vessel near a tap, and tips the vessel over everywhere else, so one button does both. The scene works out which before the button is pressed, so the button shows fill when it can be used.
- A tap used to need the vessel within 12 cm of the point under the nozzle, which asked for the player to stand in the right place to within a hand, and the button only lit up once it was pressed, so the taps seemed not to work. A stream that is aimed into the mouth of the vessel does not need that.

**Tests:** `carry_test.odin`.

### `filler.odin`
**What it does:** The balloon fill station, in package `carry`. A `Filler` is a balloon held by its neck under a funnel. It holds a mixture, as a vessel does, and its fill is its amount over 1000 ml, so a fill of 1 is the natural size of the balloon. `filler_take_drop` takes a drop with the same rule as a vessel, `mix_into`: it joins, and the pages say whether it reacts. A violent reaction bursts the balloon, and so does a fill of 1.35. A burst balloon and its liquid are lost, and two seconds later a fresh balloon is clamped. `filler_capture` takes the drops that have fallen into the funnel column, `filler_aim` says whether the crosshair is on the station, `filler_pour_ready` whether the pour button is ready for it, and `filler_mouth` where a pour is aimed. `strain` runs from 0 at a fill of 1 to 1 at the limit, and `gauge_color` says what color each light of the gauge shows. The balloon has a temperature, like a vessel, and a hot balloon is as dangerous to pour into as a hot vessel. Tying a balloon off is in `loadout.odin`.

**Decisions:**
- The 1000 ml rest volume is the total balloon volume of the simulation crate, so a balloon filled here is a balloon the arena can hold. The limit of 1.35 is the middle of the 130 to 140 percent in the design notes.
- A balloon in the lab has no chambers. It is one mixture, and pouring two liquids into it makes them react on the spot if the pages say so.
- An overfill only bursts the balloon, with liquid flying, and hurts nobody. A reaction that is a blast hurts as it does in a vessel, from the distance of the eye. That is an assumption.
- A drop that falls into the funnel with no balloon there is lost, and the capture column stops above the clamp.
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
**What it does:** The reaction oven, in package `carry`. An `Oven` has four ports, each holding one liquid kept apart from the others with its purity, up to 500 ml, and a tank that is a mixture and holds up to 2000 ml. `oven_capture` takes the drops that fall into the funnel of a port. A port takes one liquid at a time, so a drop of another liquid is turned away, and the player is told which port holds what, at most once in 1.5 seconds. `oven_start` begins a run, which takes 6 seconds divided by the speed. `oven_update` ends it: `oven_fold` pours the ports in order into one mixture at the station of the oven, and lets it react by the pages after each. The ports are emptied, and what they made waits in the tank. A violent mix keeps all of what it made, and hurts no one, because the oven is shut. `oven_spout_under` finds a held vessel near the spout, by the rule of a tap, `oven_rest_under` finds a vessel that is standing on the tray under it and is not held, and `oven_flow` lets the product out of the spout as drops aimed into the mouth of either, 110 ml a second times the speed. `oven_aim` says whether the crosshair is on the oven and which port it points at, `oven_pour_ready` and `oven_run_ready` say when the pour and grab buttons are ready for it, and `oven_mouth` is where a pour is aimed.

**Decisions:**
- The oven is how a volatile product can be made at all. In a vessel a burst breaks the vessel and the liquid is lost. In the oven the same reaction ends as the product in the tank, and the run reports how violent the worst thing was, for the look of its end.
- The ports are poured in the order of the ports, empty ones skipped, and the order matters, because the pages know acid poured into water from water poured into acid. A liquid in two ports is simply added. One loaded port is moved to the tank unchanged, which is also how a port that was loaded by mistake is emptied. The order is an assumption.
- The mix starts at room temperature at the oven station. No reaction on the pages asks for the oven yet, so only the ones that work anywhere happen.
- Nothing is lost in a run, not even from a spatter or a blast. The client shows a violent run as a blast at the top of the oven that hurts no one.
- A port takes one liquid until a run empties it, because the ports are meant to be separate. A drop of another liquid is turned away and lost. Drops of one liquid with different purities blend by volume in the port.
- A run cannot start while the tank still holds a product, so a product is not mixed into the next run by accident. The tank is emptied at the spout, or poured away.
- While a run goes the ports are shut and take nothing.
- The run time is divided by the speed, and the flow of the spout is multiplied by it, so the speed setting covers the oven too.
- The tank holds as much as the four ports together, so a run always fits.
- A vessel can be filled at the spout two ways: held near it, or standing on the tray with the hands empty, which suits filling a large vessel or a few in a row. The pour button is lit and says fill in both.
- The player is told where the spout is when a run ends, when the crosshair is on the oven with product in the tank, and by a light at the tip of the spout in the color of the product.
- The port a pour is aimed at is the one under the line of the crosshair at the depth of the funnels, and not where the line first meets the oven, so a player looking along the oven from an angle does not get the neighbour.

**Tests:** `oven_test.odin`.

### `art.odin`
**What it does:** The drawings, in package `carry`. A `Canvas` is 256 by 256 pixels, each one of the 16 colors of the palette, as the wire format of the arena has it, and color 0 is no paint, the bare rubber. `canvas_dab` makes one round spot, `canvas_line` a line of them with no gaps, `canvas_blend_dab` and `canvas_blend_line` are the blending pen, and `canvas_clear` takes it all off. A canvas has a version and the rectangle that has changed, so what shows it can send only that. `Art_Store` holds 16 drawings: `art_new` makes a blank one and gives its id, from 1, and a balloon carries the id of its drawing, so a drawing goes with its balloon wherever it is put. `canvas_to_rgba` turns a rectangle of a drawing into pixels for the screen, and `canvas_update_for` says what a picture of a drawing needs to be brought up to date. `facing_turn` says how far to turn a picture round a balloon so that its middle faces a viewer. `Paint` is the state of drawing: the paint and brush chosen, the stroke in progress, and the last eight canvases to take strokes back with.

**Decisions:**
- The picture goes once round the balloon, left to right, and from the tip to the bottom, top to bottom, taken from the direction of each vertex from the middle of the balloon at rest. It stays on the rubber as the balloon stretches. The left and right edges are the same meridian, so a dab that runs off one comes in at the other.
- The way round the balloon is about twice the way from pole to pole, so a pixel is twice as wide as it is high. The tablet is twice as wide as high for that reason, so what is drawn looks the same on the balloon at its middle, and a round brush is twice as many pixels high as wide. Near the tip and the bottom the picture is pinched, under the clamps.
- Color 0 is no paint and is also the eraser, which leaves 15 paints. The wire format has 16 colors and nothing see-through, so this uses one for it. It is an assumption.
- There are three brushes, 2, 5, and 10 pixels wide, so 4, 10, and 20 high. The blending pen has the same three sizes.
- The blending pen is a smudge with dither, because a drawing of 16 colors has no smooth gradient. Each pixel under it looks at the pixels round it, five across and nine up and down, which is the same distance because a pixel is half as high, treating bare rubber as the color of the rubber. It takes the average, finds the two nearest colors of the palette, and uses the nearer or the other by a fixed pattern of dither, so two colors meeting become a speckle of the colors between: orange where red meets yellow, and paint fading into the rubber. It reads the canvas as it was before the dab, a flat color or empty canvas does not change, and it works across the seam. It lays down no paint of its own, so choosing a paint puts the pen back to the brush. It is an interpretation of what was asked for, a pen that blends.
- A picture of a drawing, a texture on a balloon, only needs the rectangle that changed if it has everything before it. When another picture has taken the rectangle, or it has been away, it is sent the whole drawing. The first version let a balloon in the hand show the old drawing after the drawing had been changed in the clamp.
- The picture is wrapped with its middle facing +x when it is not turned. A balloon in the hand does not turn with the player, so it is turned to face them, and the balloons on the hooks to face north, where the player stands, or the middle of the picture would be on the far side of them.
- Undo keeps eight canvases, 512 KB, and a clear is a stroke that can be taken back.
- Sixteen drawings can exist at once, a megabyte. A balloon gets its drawing at its first stroke, and the player is told when there is no room. Nothing frees a drawing yet, because a balloon is never thrown away.
- Drawings are saved with the loadout, see `loadout_save.odin`, in the byte layout of the codec of the arena, `tv_proto::art`, which `art_codec.odin` matches byte for byte. They are not sent anywhere yet.

**Tests:** `art_test.odin`.

### `paint_layout.odin`
**What it does:** Where everything is on the drawing screen, as rectangles, and what a touch is on, in package `carry`, with no raylib in it. `paint_layout` places the palette as two columns against the right edge, the tablet to the left of it, twice as wide as high and filling half the width or most of the height, the three brushes, undo, and clear under the tablet, a dark panel behind all of them, a done button at the top left, and the rest of the left side as the balloon. `paint_hit` says what a point is on, with the button of the blending pen among them, `canvas_texel` which pixel of the drawing is under a point, and `balloon_ndc` how far to the side the balloon area is, which is how far the camera has to look aside to put the balloon there.

**Decisions:**
- The buttons are tested first, so a button that is over another area is the one that is pressed.
- Everything is placed from the screen size and keeps its shape, so the same layout does for a phone and a desktop window.
- The done button is large and always there, as every screen must have a visible way out.
- The drawing controls are on the right and the balloon on the left because the owner asked for it that way round. The layout is mirrored as a block, so the swatches still read left to right as before, and the panel behind the tools is part of the layout so a test can say it covers the tools and not the balloon.
- The tablet gives way on a screen that is nearly square so the balloon keeps its room. The balloon is 0.525 of the height of the screen across at the distance the drawing view looks from, and the area is kept at 0.58 of it, which `selftest.odin` checks by projecting the balloon. A phone, twice as wide as it is high, never feels it. The tablet keeps at least 0.3 of the width so it cannot vanish.

**Tests:** `paint_layout_test.odin`.

### `art_codec.odin`
**What it does:** Encodes and decodes a drawing in the byte layout of `tv_proto::art`, in package `carry`, so the bytes saved on the phone are the bytes the server will take. A format byte, the 16 colors of the palette as three bytes each, then either the pixels two to a byte with the first in the low half, or runs of a color byte and two bytes of length, low first. `art_encode` uses run-length only when it is strictly shorter, as the Rust codec does. `art_decode` refuses what the Rust decoder refuses: another format byte, input too short, a run of nothing, a run past the end, a color outside the palette, anything left over, or a raw drawing of the wrong length. `hex_encode` and `hex_decode` turn bytes into text and back.

**Decisions:**
- The test vectors come from the Rust code: the encoding of a flat drawing in full, and the length and hash of a noisy one, made by a small program that uses `tv_proto` and set into the test, so a change on either side that breaks the agreement fails here.
- The palette written is that of the lab, and the palette read is skipped, because a drawing here is indices and the palette is the lab's. Color 0 is no paint, which is a convention of this client and not in the bytes, so another client has to draw index 0 as bare rubber.
- A drawing that does not decode leaves the canvas as it was.
- A decoded drawing counts as wholly changed, so what shows it sends the whole thing.

**Tests:** `art_codec_test.odin`.

### `loadout_save.odin`
**What it does:** Turns the balloons of the player into text and back, in package `carry`. `loadout_serialize` writes a header line and a line for each place that holds a balloon, the hand, the paint station, and each hook, with the place, what is in the balloon, and the drawing as the hexadecimal of its encoding or a dash. What is in the balloon is a list with no spaces, `number:millilitres:purity` for each compound, separated by commas, with whole millilitres and the purity as a whole percent. An ingredient that rounds to no millilitres is left out. `loadout_deserialize` reads it back and makes a drawing in the store for each balloon that had one. It skips what it cannot read, a line of the wrong shape, an unknown place, a number out of range, a drawing that does not decode, and a balloon whose drawing is bad comes back without one. Text without the header is not read at all, and the header is now `tvloadout 2`, so a file of the first version, whose numbers were other compounds, is not read.

**Decisions:**
- It is plain text, because the file functions of the client write text on every platform, the phone included.
- The temperature and the unsafe meter are not saved, because they do not last, and the drawing ids are not saved, because they are places in a store that is made again. Each drawing gets a new id.
- One bad line never stops the rest being read, and the game never fails to start for a damaged file.
- When the store has no room, a balloon comes back without its drawing and is told nothing, which is better than losing the balloon.

**Tests:** `loadout_save_test.odin`.

### `heat.odin`
**What it does:** The hot plate and the ice bath, in package `carry`. `station_heat` says what a vessel is standing on: 1 for the hot plate, -1 for the ice bath, 0 for anything else, when its middle is inside the footprint and it is resting near the counter top. `props_heat_update` moves the temperature of the liquid in every vessel on by a frame: on the plate it rises by 6 degrees a second toward 160, in the bath it falls by 6 a second toward 0, and anywhere else, in the hands too, it drifts back toward the room, 20, by 2 a second. A vessel with nothing in it has no temperature. A vessel whose temperature moved may react, because the pages have windows of temperature, so after moving it `props_heat_update` lets it react as a drop would, and returns the results as events for the scene to show. A vessel that bursts breaks. `loadout_heat_update` does the same cooling for the liquid in every tied balloon, and the balloon at the fill station cools the same way in `filler_update`. `heat_unit` gives how far from the room a temperature is, from -1 for 0 degrees and below, through 0 for the room, to 1 for 100 degrees and over, and `heat_word` gives a word for the line under the crosshair from it: warm and hot above 0.25 and 0.75, cool and cold below -0.25 and -0.75, and nothing near the room.

**Decisions:**
- The plate takes about 23 seconds to reach 160 degrees, and the liquid is back to the room in about a minute, so there is time to stop at a window of the pages, such as the 75 to 90 degrees of the ethyl acetate reaction, and it has to be done on purpose. 160 is enough for every window that asks for a hot bath. All of these are first guesses, and the vessel readout shows the temperature in degrees.
- The plate is always on. A switch can come later.
- Only a vessel that is resting heats. One in the hands does not, so the player cannot warm a vessel by holding it over the plate.
- A balloon cools at the same rate as a vessel, so a liquid that was made hot or cold by pouring a hot or cold liquid into the balloon does not stay that way.
- The temperature belongs to the liquid and not to the glass, so an empty vessel has none, and a vessel that is poured out and filled again starts at the temperature of the new liquid.
- How a temperature is blended on mixing, and what a reaction at a temperature does, is in `mixing.odin` and `chemistry.odin`.

**Tests:** `heat_test.odin`.
**Moved stations:** Where the hot plate and the ice bath are comes from the stations of the props, and not from fixed places. `station_heat` and `target_c` take the stations, and with none they use the starting ones, which are where the stations have always been. `props_heat_update` gives them those of the props. A station that is turned heats where its plate now lies.

### `loadout.odin`
**What it does:** The balloons the player has made, in package `carry`. An `Item` is a tied balloon: the whole mixture it carries, with its temperature in degrees, and an id for its drawing, which is 0 until there is drawing. A `Loadout` has the balloon in the hand, the one in the paint station, and a balloon for each hook of the rack, which is the set that goes into a match. `loadout_aim` finds what the crosshair is on among the fill clamp, the paint station, the hooks, and the incinerator, the nearest within reach and nearer than any vessel. `balloon_action` says what the grab button would do there: tie off and take at the fill clamp, clamp or take at the paint station, paint at the tablet when a balloon is clamped, store or take at a hook, burn at the incinerator when a balloon is in the hand, and nothing while a vessel is held. Painting moves nothing, the scene opens the drawing screen. `balloon_do` does it, and `filler_tie` is what happens at the fill clamp: the balloon is tied, its contents go to the hand, and the station makes another. `loadout_presets` gives what the server needs of each balloon on a hook: the mixture, the compound there is most of and the volume, which are all the wire carries until it carries a mixture, and the drawing id.

**Decisions:**
- The hands hold a vessel or a balloon, not both. With a balloon in the hand the grab button does not grab a vessel, and says so.
- A balloon that is stretched past full is let down to 1000 ml when it is tied, and the excess is lost, because a recipe is at most 1000 ml in total. The player is told how much.
- A balloon with nothing in it cannot be tied off and taken.
- Burning takes only the balloon in the hand. Whatever is in the paint station or on a hook stays where it is, so a balloon has to be taken before it can be burned, and aiming at the incinerator with empty hands does nothing. A burned balloon is gone for good, with no undo, because the owner asked for a way to get rid of balloons.
- The drawing is one per balloon, and its pixels are in `art.odin`. Each balloon carries its own id, so each can be painted differently, and the server is sent the drawing of each preset. That follows from the loadout holding balloons that are painted one by one. If the art is to be one per player instead, the id moves out of the item.
- The number of hooks is `LOADOUT_SLOTS` in the lab, set in one place because it is not decided. A preset is made for each hook that holds a balloon, in the order of the hooks.
- The loadout and the drawings live in `Game`, so they outlive a visit to another scene, and are saved to a file, see `loadout_save.odin`. Sending the presets to the server is not done.

**Tests:** `loadout_test.odin`.

### `art_view.odin`
**What it does:** The texture a drawing is shown with, in the client. An `Art_Texture` follows one drawing: 256 by 256 pixels, RGBA, with no alpha where there is no paint, made when it is first needed. `art_texture_sync` brings it up to date with a drawing of the store: a different drawing is sent whole, a change to the same one is sent as the rectangle that changed if this texture has everything before it and the whole drawing if it does not, and nothing is sent when nothing changed. It says whether there is a drawing to show.

**Decisions:**
- The texture has no mipmaps and repeats, so a drawing that wraps round the seam of the balloon has no line in it.
- Only the rectangle that changed is sent while drawing, so a stroke costs as much as the stroke is big.
- One buffer for turning a drawing into pixels is shared by every balloon.

### `paint_view.odin`
**What it does:** The drawing screen, in the client. `paint_touch_update` takes the fingers: a new finger on the tablet starts a stroke and keeps drawing as it moves, held to the edge of the tablet if it leaves it, a new finger on a swatch or a brush chooses it, on undo or clear does that, on done ends the drawing, and on the balloon turns it as it moves. The first stroke on a balloon makes its drawing. `paint_camera` puts the camera close to the balloon in the clamp, looking along the counter, turned aside so that the balloon is in the middle of the part of the screen left for it, which is the left. `draw_paint_ui` draws a dark panel behind the tools and then the tablet with the drawing on it, a button for the blending pen that is lit while it is on, the palette with the chosen paint marked and the first swatch crossed out as the eraser, the brushes as dots of their sizes, undo, clear, and the done button at the top left.

**Decisions:**
- The camera looks at the middle of the balloon as it hangs, 0.1 m below the clamp, and the self-test projects the balloon through it on five screen shapes to check that the whole of it is on the screen and in its part of it.
- The drawing is made on a flat picture of the tablet on the screen and not on the balloon, so a finger draws in a rectangle and there is no picking on a curved surface. The balloon wears it as it is drawn.
- A finger that was down when drawing began, or landed on a button, does nothing more, as in the walking controls.
- A drag across the balloon turns it so that the surface follows the finger, about a quarter of the screen height for a radian.
- The turn is only how the balloon is seen. The tablet and the drawing are not turned.

### `loadout_file.odin`
**What it does:** Reads and writes the file of balloons, in the client. `loadout_load` makes the store for drawings if there is none, and reads `tv_loadout.txt` into the loadout when the game starts. `loadout_save` writes it. The lab saves the frame after a balloon is moved, tied, taken, or stored, and after a drawing is finished, so a frame with several changes writes once, and again when the lab is left.

**Decisions:**
- A missing file is the first run, and a failure to write is a line on the error output and nothing more.
- A drawing that is half made when the game is stopped is not saved, only a finished one.
- The path is the one the file functions of the client use, which on the phone is the private storage of the game.

### `spill.odin`
**What it does:** The puddles of the lab: liquid that has landed, kept for the view. A puddle has a place on a surface, how much liquid is in it, how wide it has spread, how long ago it landed, and a delay for liquid that is still falling to a floor far below. `spill_add` lets liquid land: it joins a puddle of the same liquid that it lands within 0.9 of the radius of, on the same surface (within 3 cm of height), which makes that puddle larger, moves its middle towards the drop by the drop's share, and makes it fresh again; otherwise it makes a new puddle, and when all 24 are in use it takes the one that has lain longest. `spill_step` spreads puddles that have landed towards their size, the circle that holds their liquid at a thickness of 1.2 mm (kept between 1.2 and 35 cm), and removes those that have dissolved. A puddle lies for 4 s and then dissolves over 2.5 s (`puddle_dissolve` is 0 to 1). The stream makes puddles when a drop has lain still for 0.08 s (`PUDDLE_START`), and when a drop falls out of its box over the edge of a counter.

**Decisions:**
- Puddles are only for looking at: nothing reads them, so they do not make anything slippery or hurt, and a chemical that is dangerous on the floor looks the same as water. What a spill of acid should do is for the owner to say.
- A puddle spreads quickly, in a second or so, so that it looks like liquid spreading and not a disc that appears.
- Liquid of one kind joins a puddle and different liquids lie side by side, so a mix is not made on the floor.
- The time is real time, from the room, and not the substeps of the stream, which run slower than real time when a frame is late.
- The numbers are first guesses: the thickness, the 4 s and 2.5 s, the 24, and the reach of joining.

**Tests:** `spill_test.odin`.

### `spill_test.odin`
**What it does:** Tests the size of a puddle and its limits; a new puddle and its delay; joining, which needs the same liquid, the same surface and a place near, moves the middle by the share, and makes a puddle fresh without taking back its delay; taking the oldest when all are in use; spreading, which is only up to the size and not before landing, and not past it in one long step; the dissolve at the start, the middle and the end, counted from when it landed; the removal of one puddle keeping the others; and in the stream, that a drop lying on the island becomes one puddle once and that one falling off a counter lands on the floor after its fall, and that the flag of a drop that has landed goes with it when another is removed and is clear on a new drop.

**Decisions:** The drops are made over the island in the middle of the lab for the one that lies, and over bare floor for the one that falls, because the box of the stream gets its floor from what is under the first drop.

### `spill.vs`
**What it does:** Vertex shader for puddles and beads. It passes the texture coordinate and color on, and the position, which is already in the world because the batch renderer makes the quads there, so the fragment shader can use it for the grain of the dissolve.

**Decisions:** The GLES 2 version is kept in step with the desktop one by hand.

### `spill.fs`
**What it does:** Fragment shader for puddles and beads, which one file draws, switched by the texture coordinate: it runs from -1 to 1 across a quad, and a bead has 10 added to its x. A bead is a ball lit from above and to one side with a highlight and a brighter edge, cut off round. A puddle has an edge that wanders, by a pattern read off a circle so that it has no seam, and that is different where the puddle lies, since it is read from the world position. It is a little darker in the middle, with a bright line at the edge and a glint. Its alpha is how much of it is left: as that falls, specks are cut away, the edge first, by two layers of noise, and what remains is a little more see-through, until nothing is left. Both are cut round and soft at the edge.

**Decisions:**
- One shader for both, so that a puddle's alpha can be its life and a bead's its opacity without a uniform changing between them.
- Noise is a hash of a sine, which needs no texture. The highp precision is asked for where the device has it, since the hash loses itself in mediump.
- Written to compile as GLSL 330 and as GLSL ES 100, with no derivatives and no loops.

### `inventory.odin`
**What it does:** The containers that hold things, ported from the inventorizz package of unity-chem-sim in the parts the game needs now. An `Item` is a kind (only the dispenser so far) and an `arg`, which for a dispenser is the number of the compound in it, 0 for none; two stack only when both are the same, and a dispenser does not stack (`max_stack` 1). Items have tags (`Mountable`), and a container takes only items that have all the tags it asks for (`requires`): the wall asks for `Mountable`, the bag asks for none. A `Container` is up to 16 slots, can be locked, and has a `version` that goes up with every change, which the lab reads to know that the wall has changed. `add` puts as many as fit, on top of stacks and then into empty slots, and says how many; `remove` takes all or none; `take` and `put` work on one slot; `can_move` and `move` take the stack in one slot to a slot of another container, or the same, into an empty place or on top of the same item, and never swap; `transfer` moves wherever there is room, all or nothing, and leaves both as they were if it cannot. `serialize` and `deserialize` write and read containers by name as plain text, one line for each container and each stack.

**Decisions:**
- Weight limits and the four capacity kinds of inventorizz are not ported: no item has a weight yet. Slots and a lock are enough for the bag and the wall.
- Tags and `requires` are the inventorizz rule that decides what a container takes, so that a wall takes things that can be mounted and a later container could take other things.
- A move never swaps, as in inventorizz: dropping a dispenser on another does nothing, so nothing is lost by a slip of the thumb.
- Reading the text is forgiving: a line that is wrong is skipped, and a container named in the text is emptied first so that the text is what it holds. Text without the header is not read, so a file that is not ours cannot empty the wall.
- A move that puts a stack back where it came from counts as a success and changes nothing, not even the version.

**Tests:** `inventory_test.odin`.
**Stations:** The hot plate, the ice bath and the scale are items that have the tag `Benchable`, and a dispenser has `Mountable`, so a container that requires one of the tags does not take the other kind of item. The tag keeps the name it had when stations stood on a bench of spots, and today only the reading of a file from before reads a container that requires it. `move_to` moves a stack to the first slot of another container that takes it, all of it or nothing.

### `inventory_test.odin`
**What it does:** Tests the sizes; what a container takes by its tags; adding to empty slots, stopping when full, and not stacking identical dispensers; that adding to a full or locked container changes nothing, not even the version; removing all or nothing, from the first slots; `take` and `put` at their edges; moving into an empty place, between containers and within one, never swapping, from and to places that do not exist, and with either end locked; putting a stack back; transfers, which undo themselves; free room; and the text, which comes back as it was, leaves containers it does not name alone, skips every kind of bad line and keeps the rest, and is not read without its header.
The station tests check that stations go in a container that takes stations and in the bag and not on a wall, and a dispenser the other way round, that `move_to` takes the first place that takes the stack and does nothing when none does, and that text that puts a station on a wall is skipped.

### `dragdrop.odin`
**What it does:** One drag at a time, ported from the dragndrop package of unity-chem-sim as its controller, without the pointer and the pictures. `begin` starts a drag with a payload that the controller never looks at, `set_hover` says which target it is over (or none), and the target says whether it takes the payload, `end` says whether the drag ended over a target that takes it and which, and `cancel` ends it with nothing dropped. The owner makes the move.

**Decisions:** The controller does not know about the pointer or the screen. Whoever draws the places to drop finds the one under the pointer and passes it in, which is what makes the controller the same on a phone, with a mouse, and in a test.

**Tests:** `dragdrop_test.odin`.

### `dragdrop_test.odin`
**What it does:** Tests that it starts idle over nothing, that only one drag begins at a time, the hover with a rule, with no rule and with data, that hovering does nothing without a drag, ending over a place that takes it, over one that does not, over nothing and with no drag, and that a cancel leaves it ready for a new one.

### `stock.odin`
**What it does:** What the player has to put on the bottle wall: a `Stock` of the bag (12 slots) and the wall (a mount for each of the ten taps, taking only things that can be mounted). `wall_default` is the wall as the lab starts. `station_sync` sets the taps from the wall: a mounted dispenser with a compound in it that exists gives that compound, and every other mount, empty or with a dispenser with nothing in it, gives nothing; the faucet is left alone. `wall_look` gives the color of the bottle at each mount, from the liquid in its dispenser, and which mounts have a dispenser at all.

**Decisions:**
- The wall is the source of what the taps give, and the taps are never edited on their own, so the bottle that is drawn and the tap that works cannot disagree.
- A dispenser with nothing in it is drawn grey and gives nothing. Filling one, a gauge on it, and buying them are for the shop, which is not built.
- An unknown compound in a dispenser, from a damaged file, gives no tap.

**Tests:** `stock_test.odin`.
**Stations:** A `Stock` is the bag and the wall only. A station is in the bag or it stands on a counter, and where it stands is `Props.placed`. `station_item`, `item_station` and `station_name` turn kinds into items, items into kinds and kinds into words. `Pickup` is the station that the crosshair is on, within reach and with nothing nearer (`pickup_aim`), and which one it is among those that stand. `busy` says that a vessel that is not in the hands stands on its plate (`station_busy`, `prop_on_plate`: over the plate and resting on the counter or the plate, not in the air), and `pickup_ready` says whether picking it up would work: aimed at, hands empty, nothing on it. `placed_from_bench_file` reads a file from before stations could stand anywhere: its bench of six spots, with each station put at the middle of its spot on the north counter, and the starting stations when the file had no bench.

The tests of the stations are in `stock_test.odin`.

### `stock_test.odin`
**What it does:** Tests the wall as the lab starts, that the taps follow what is mounted when stacks are moved, that a dispenser with nothing in it or an unknown compound gives nothing, that syncing clears what was there, a wall with fewer mounts than taps, that the taps at the start are those of the default wall, and the look of the wall and its colors.
The station tests check that the stock is a bag and a wall, the two-way mapping of kinds, items and names, aiming at a station and not at bare counter (the nearer of two, two in one line of sight, and the turned box), that a station with a vessel on it is busy and cannot be picked up while a vessel in the air, in the hands, beside it or on the floor under it is not on it, the plate of the scale, and that a file from before stations could stand anywhere keeps the stations where its bench had them, is the starting lab when it had no bench, and reads only what a bench could hold.

### `blueprint.odin`
**What it does:** The station that is being carried, in package `carry`. A `Blueprint` is a see-through copy of a station that follows the crosshair. It is made by picking up a station that stands (`blueprint_pick_up`, which takes it off the counter) or by taking one from a slot of the bag (`blueprint_take_from_bag`), so that a station is in one place at a time. Each frame `blueprint_aim` follows the crosshair to the plane of the counter tops and fits the copy to the counter there (`lab.fit_to_zone`), and `station_problem` checks it: no room for another because eight stand, not on a counter, a fixture or a station in the way, or a vessel in the way (`vessel_in_way`: its middle is within a radius of the footprint, on the counter or higher, and not in the hands). Too far to reach (`REACH`) is a problem of its own and comes before the others. A crosshair that is level or up meets no plane, and the copy floats a metre in front of the player. `blueprint_place` puts the copy down if it can stand where it is, checked again at that moment. `blueprint_rotate` turns it a quarter. `blueprint_cancel` puts it back where it stood if that place is still free, otherwise in the bag, in the slot it came from if that is free, and if the bag is full it stays carried. `blueprint_words` is the line under the crosshair for each problem.

**Decisions:**
- The copy is carried by the crosshair and not placed with a cursor, so that a phone needs nothing new but three buttons: place, rotate and cancel.
- A station leaves the counter or the bag when it is picked up, so that it cannot be in two places, and cancel has to find it somewhere. A station with a vessel on it cannot be picked up (see `stock.odin`), so that the vessel does not fall into the footprint of the station that is carried or put back.
- The copy is fitted to the counter, moved in until the whole station is on it, because a counter is 0.7 m deep and a hot plate 0.5 m, and aiming within 20 cm with a thumb is hard.
- The numbers are first guesses: the metre that the copy floats in front, and the 6 m that the plane is looked for along the crosshair.

**Tests:** `blueprint_test.odin`.

### `blueprint_test.odin`
**What it does:** Tests that picking up a station takes it off the counter and keeps its place and turn, and that it is refused for no such station, full hands or a station already carried; that choosing a station in the bag takes it out of the bag, and is refused for an empty slot, a dispenser, full hands or a station already carried; the turns; that the copy follows the crosshair over a counter and is fine where there is room, and that the front edge and the wall are forgiven; that it is not fine on the floor, on the counter of the bottle wall, too far away, or with the crosshair level or up (the direction counts and not its length, a crosshair at the height of the counters meets no plane, and a counter beyond the limit is not followed past it); that a fixture, a station or a vessel in the way is named, a vessel in the hands is not in the way, too far comes before the others and a full lab before all; the radius of a vessel, floor level and turns for a vessel in the way; that a copy put down stands as a station and heats where it is, and one that cannot stand is not put down, not even when it was fine when last aimed and something has come in the way since, or when it is not carried; that a copy goes back where it came from, to the bag when that place is not free, to its slot or another in the bag, and stays carried with nowhere to go; and that every problem has words of its own.

### `stock_ui.odin`
**What it does:** The screen of the bag and the bottle wall, opened by the bag button, to the left of the book button, or B on a desktop. It is a panel over the lab, with a close button, like the book: the wall on the left as ten mounts in two rows of five, numbered, and the bag on the right as twelve slots in three rows of four. A slot that holds a dispenser shows a bottle in the color of its liquid with the name under it, or grey with "empty". A press on a dispenser starts a drag, a bottle follows the pointer, the slots that take it have a green edge, the one the pointer is over a brighter one, red if it does not take it, and the slot it came from is dimmed; letting go over a slot that takes it moves it there, and anywhere else cancels. The logic of the screen (`stock_update`, `stock_slot_box`, `stock_slot_at`) is plain procedures that `selftest_stock` runs without a window. While the screen is open the lab is paused, and when a stack has moved the room syncs the taps, makes the lab and its mesh again so that the bottles are where the dispensers are, and saves.

**Decisions:**
- Large tiles in two grids and not a free canvas, since the wall has ten mounts and a thumb has to hit one.
- The pointer is the mouse, which raylib makes of the first finger on a phone, as for the book, so a drag is one finger.
- A drag cannot start from a locked container, and a locked one takes nothing, though nothing locks either yet.
- Moving a dispenser to the bag takes its bottle off the wall and its tap stops. Mounting a dispenser from the bag, wherever there is an empty mount, brings it back with its liquid.
- Dispensers move between the bag and the wall by drag. Buying them, filling them, a gauge, and carrying a dispenser as a copy to a mount in the world are not built.
**Carrying a station:** A tap on a station of the bag, a press and a release on the same slot, asks the room to carry it (`carry_slot`) when the hands are free (`hands_free`, set by the room before each update), and the screen then closes. A drag moves it as before, and the wall does not take it. The line under the heading says so, and says when the hands are full. The pick up button is above the pour button. It is always there, bright when a station is aimed at with empty hands and nothing on it, dim when not, and it says rotate while a station is carried. The bag button is dim while a station is carried.

### `blueprint_view.odin`
**What it does:** Draws the station that is carried: a see-through box the size of the station's body and height, its footprint on the counter top, bright edges and a bar on the side that the front of the station is turned to. It is blue-green while the copy can be put down and red while it cannot. It is made of plain `rlgl` quads, like the rest of the drawing, without a raylib call that takes a struct of floats, and is drawn without writing depth, so that it never hides what is behind it, and with both faces, so that the order of the corners does not matter.

**Decisions:**
- The copy is a box and not a model of the station, because it has to show the footprint that is checked, and a box of a different size from what is checked would mislead.
- The edges are 8 mm thick so that they read at a metre on a phone screen; the number is a first guess.

### `stock_file.odin`
**What it does:** Reads and writes `tv_stock.txt`, the bag and the wall as text from `inventory.serialize`, followed by the `placedset` and `placed` lines of `lab.placed_serialize` that say where the stations stand, through the same file functions as the loadout. It is read when the lab is loaded and written when something is moved, picked up, put down or put back and when the lab is left, except while a station is carried: the file then keeps the station where it was picked up from, so that nothing that ends the game can lose it. A missing file is the first run, a damaged one gives back what could be read, a file from before stations could stand anywhere gives the stations at the places of its old bench, a station that cannot stand where the file says goes into the bag if there is room, and a failed write is a line on the error output.

### `sink.odin`
**What it does:** The soap by the sink, and washing hands. The soap is aimed at like the first aid cabinet, with the crosshair within reach and nothing nearer; with the hands empty the grab button begins washing, which takes 2.5 s, shows its progress as a line under the crosshair, and ends with the toast "hands washed".

**Decisions:** Washing hands has no effect on anything. The owner said the soap is for washing hands, just because. If it should do something, that is for him to say.

**Tests:** `sink_test.odin`.

### `sink_test.odin`
**What it does:** Tests that the soap is aimed at when the crosshair is on it within reach and not beside it, too far or looking away, that a vessel under the crosshair comes first, that it can be used only when aimed at with empty hands and not while washing, and that washing takes its time, ends once, and can be done again.

### `placed.odin`
**What it does:** The stations that can be picked up and put down, in package `lab`: the hot plate, the ice bath and the scale (`Station_Kind`). A `Placement` says what a station is, where its middle is and how many quarter turns it has been turned. A `Placed` holds up to eight (`MAX_PLACED`), the ones in use first and the rest zero, and `default_placed` has the three where they have always stood. What depends on a station reads where it stands: `on_station` asks whether a point is on the plate of a kind of station anywhere, `world_plate` and `world_body` give the plate (what the middle of a vessel has to be inside to stand on it) and the body (what the station takes up, rim and display included), turned and moved, and `station_aim_box` is the box the crosshair is tested against. `can_place` says whether a station of a kind, turned so far, may stand at a point: wholly on one counter (`place_zones`: the north, south and west counters and the island, and not the counter of the bottle wall), clear of every fixture (`fixture_keepouts`) and clear of the other stations, with touching edges allowed. `fit_to_zone` takes the point where the crosshair meets the counter plane and gives the middle of the station: rounded to a 5 cm grid, and moved in just far enough that the whole station is on the counter that the point is on. `placed_serialize` and `placed_deserialize` write and read the `placedset` and `placed` lines of the stock file, in whole millimetres. A line that cannot be read is dropped, and one that cannot stand where it says, given those before it, is handed back so that it can be put in the bag. `add_placed` builds each station where it stands and turned, using the `Xform` of `layout.odin`, and the builders of the three stations are here, moved from `bench.odin`.

**Decisions:**
- The counters, anywhere on them where there is room, in quarter turns. The owner said that stations go only on the counters and not anywhere, wherever there is space, with a check that shows red where a copy cannot be put down. He did not say whether "specified places" meant fixed spots or the counters. The counters with free positions on a grid is what was built, and he has not confirmed it.
- The keep-outs are worked out by hand from the fixtures, with a hand's width to spare, and a test checks them against what the lab builds: every box that sticks up from a counter where a station could be hit lies inside one. A fixture that is moved or added makes that test name the box. What is on a wall over the stations, the first aid cabinet and the shelves, takes up no counter and has no keep-out. The keep-out of the paint station reaches its palette and brushes, and that of the fill station its gauge.
- The body of a station is the same all round, so that turning it does not change which side the room is on, and the display of a scale does not need a bigger footprint on one side.
- The counter of the bottle wall is not a place for stations, because vessels stand there under the taps.
- Positions are whole millimetres, and what `fit_to_zone` gives is on the 5 cm grid, so a station comes back from the file exactly where it was put. The starting scale is at z -7.625, which is not on the grid, so that its plate is `SCALE_PLATE` as it always was.
- A station that the counters can no longer take is not lost on loading. It is handed back and the room puts it in the bag.
- The display of a scale faces +z when it is not turned. Whether it should face the player wherever it is put is for the owner to say.

**Tests:** `placed_test.odin`.

### `placed_test.odin`
**What it does:** Tests that the stations start where they have always stood and can each stand there, adding and taking away (the order kept, the place that was the last cleared, the limit of eight), the footprints turned and moved, whether a point is on a station (at the edges, for the other kinds, turned), the aim box, that stations go on the four counters and not on the bottle wall or the floor, the edges of the counters to the centimetre, that turning changes what a station takes up, each fixture in the way and free places beside them, that every box of the fixtures that stands on a counter lies inside a keep-out (checked against what the lab builds) and that every keep-out has an area and is on a counter, that stations may touch and not overlap, the grid, fitting to a counter at the edges and, for every kind and turn over a field of points, that what is fitted is on the counter, writing and reading back (the text exactly, and a moved and turned station), a file with no `placedset` line, lines that are dropped and lines that are set aside, a second `placedset` line and a full set, and the boxes that each station builds, turned, with the display of a scale on the side it faces, and room for eight of them.

### `jet.odin`
**What it does:** Turns the drops in the air into what the view draws. A drop's `seq` gives the order the drops were made in, oldest first (`jet_order`). Drops that follow one another in that order, are in the air and moving, go the same way, and are no further apart than the time between them allows (`jet_joined`) form a jet. `jet_build` makes a smooth curve through each (Catmull-Rom, with the ends carried on the way the line was going), as wide as the liquid in it (`jet_radius`: the width of a stream that would hold it, made 1.4 times thicker, kept between 5 mm and 2 cm) and drawn thinner at the ends. The newest end is joined to the mouth, the lip being poured from or the tip of a tap, while liquid has come out of it in the last 0.12 s and the newest drop is within 30 cm of it. Drops in no jet are marked loose, and the view draws them as beads. Nothing is allocated: a `Jet` has room for 193 points, which is 96 drops with a point between each pair and the mouth.

**Decisions:**
- The jet is built from the drops that the simulation really moves, and not from an arc of its own, so the stream goes where the liquid goes and the vessels still take what falls into them.
- Drops are one jet when they move together. A splash scatters drops every way, so they fail the test of going the same way and are drawn as beads, which is what spray looks like.
- The jet is joined to the mouth only while liquid leaves it, so that when a pour stops the tail breaks off from the lip and falls.
- The width is drawn thicker than the liquid would be, because a stream as thin as the liquid would be is hard to see on a phone. The 1.4 is a first guess, like the limits and the 0.7 of the ends.

**Tests:** `jet_test.odin`.

### `jet_test.odin`
**What it does:** Tests the order of the drops, which stays right after drops are removed, and the test of whether two drops are one jet at both edges of each limit (slow, resting, going another way, too far, the faster one setting the reach, made at the same moment, ages the wrong way round). It checks that a run of drops is one smooth jet from the oldest to the newest that never doubles back, thinner at the ends, with points halfway between drops on a line at both ends; that separate runs are separate jets and a lone drop is loose; that a splash is not a jet; that the mouth joins only the jet with the newest drop, only while liquid leaves and only when near; the widths; the curve; and that a pour, a tap and the oven's spout note their mouth, and a pour lets go of it when nothing leaves.

**Decisions:** The drops of a test are made 0.6 m over the island in the middle of the lab, because the box of the stream gets its floor from whatever is under the first drop, and a drop lower than the top of the island would be outside it.

### `stream_view.odin`
**What it does:** Draws the liquid in the air. Drops that are part of a stream (`carry.jet_build`) are drawn as one smooth tube through them, six sided, joined to the lip or the tap they came from, in the color of the liquid, with the lighting worked out for each vertex: lighter on the side to the light, a sharp highlight along it, and a glow at the edges, where clear liquid is brighter. It is a little see-through. The oldest end is rounded off, and so is the newest when no liquid is coming out. Liquid that has landed is drawn first, as flat puddles on the surface it lies on, each a quad that `spill.fs` makes into a wandering shape with a bright line at its edge and a glint, which spreads, joins the puddles near it, and after a few seconds dissolves away in specks, the edge first. Drops in no stream and not landed, such as the spray of a splash, are drawn as round beads: quads that face the camera, which `spill.fs` makes into lit balls with a highlight. The tubes are drawn by the batch renderer with no shader, and everything without back-face culling, so the winding does not matter. If the shader fails to compile, puddles are flat discs that only fade, and beads are small diamonds as before.

**Decisions:**
- A stream of 96 drops is at most 7000 vertices (a diamond is 24, a stretch of tube between two points 36, a cap 18), and the drawing stops at that, which the smallest batch of raylib holds. It is flushed before and after so that it does not mix with the rest.
- The tube is turned along the curve by carrying one side direction forward and taking out what lies along the curve, so that it does not twist.
- The eye is passed in for the highlight. The light is a fixed direction from above.
- Water is not refracted, and no spray is made where the stream hits a surface: the beads are the drops the simulation has, and a splash made of many small drops that are not simulated has not been tried. A screen-space surface, at half size, would be another step.
- Puddles and beads share one shader, switched by the texture coordinate, so that there is one file to keep in step for each GLSL version, and puddles can be one batch. A puddle's alpha is how much of it is left, so no uniform has to change between puddles.
- A puddle is drawn 3 mm over its surface, and is not an obstacle. It is only for looking at.

### `effects_view.odin`
**What it does:** Draws the effects and gives the room shaders the light of a blast. Two small textures, a soft dot and a ring, are made in code. Particles are squares that face the viewer. Smoke, liquid, and mist are blended over the picture first. Fire, sparks, and the rings are added to it afterwards, so they glow. Nothing writes depth, so particles overlap without cutting each other, and the room still hides them. `blast_light_set` gives a shader the place and reach of the flash, its color, and its brightness, which `lab.fs` and `vessel.fs` add to their lighting. With no blast going the reach and brightness are zero.

**Decisions:**
- The textures are made in code, so there is no image file to package into the APK.
- Squares are drawn as triangles through the batch renderer, as the drops are. A full pool is 220 squares, about 1300 vertices.
- The balloon shader does not take the flash, so a balloon is lit by the room only.
- The flash lights by distance to its point only, with no shadows. A blast behind a counter still lights the room beyond it.

### `filler_view.odin`
**What it does:** Everything on the screen about the balloons and stations that is not static. A `Balloon_Body` is one soft-body balloon at the size of the lab. It is simulated at the size it was tuned for, about one unit across, with its tip pinned at the origin, and drawn scaled down and moved to where it hangs. The scale is chosen so that the rest volume of the soft body takes the volume of 1000 ml, so how big the balloon looks is how full it is. `body_step` sets the fill, shifts the body when the point it hangs from has moved, and steps the simulation while it is still moving, and `body_draw` draws it. `Filler_View` is the body of the fill station. `Loadout_View` has the bodies of the balloon in the hand, the one in the paint station, and one for each hook of the rack, each made ready when an item arrives and costing nothing while its place is empty. A balloon in the hand hangs in front of the player, a little to the right, and swings as the player moves, with its drawing turned to face them. A body wears the drawing of its balloon, kept up to date by `body_art`. `tablet_draw` draws the screen of the tablet, with the drawing of the balloon in the clamp on it, or dark when there is none. `stations_draw` draws the ten lights of the gauge, a light over each hook in the color of what hangs on it, and the glass of the fume hood.

**Decisions:**
- The balloons have mesh detail 4 and 6 substeps, less than the balloon lab. A body sleeps 1.5 s after its fill last changed, so a balloon at rest costs nothing, and it is stepped at most once a frame. The balloon in the hand is always awake, because it is always moving.
- To make the balloon in the hand swing, the body is drawn at the hand, and each frame it is moved back by how far the hand has moved, so it stays where it is in the world and the pinned neck pulls it along. A move of more than 60 cm in a frame is a jump, as after a reset, and the balloon starts afresh. The neck of the hand body may follow the hand ten times as fast as the others may follow a clamp, or it would lag far behind a walking player.
- Every body but the one of the fill station shares its shader and does not unload it, so one shader is loaded for seven balloons.
- An empty balloon is drawn at 55 percent of its rest volume, so it looks limp. Squeezing the soft body to a fraction of its volume would make it crumple.
- The knot is hidden. A balloon being filled is open at the neck, and the collar covers its top. A tied balloon in the hand, the paint station, or a hook is drawn the same way, so none of them has a knot yet. That is a gap to fix when the tie is shown.
- Near the limit the rubber goes thin and pale, from a `strain` value in the balloon shader, and the red lights of the gauge blink.
- The gauge and the hood glass are drawn each frame because the fill changes. The glass is blended, comes last, and writes no depth.

### `oven_view.odin`
**What it does:** The parts of the reaction oven that change from frame to frame, drawn over its front: a light for each port in the color of the liquid in it, brighter the fuller the port, dark when empty; a light for the product in the tank; a light at the tip of the spout in the color of the product, while there is some; a glow in the window that pulses while a run goes; and a strip of ten lights that fills as the run goes on. The static box, funnels, and spout are in the room mesh.

**Decisions:**
- The lights are flat boxes drawn without lighting, as the gauge of the fill station is, so they read at any distance and in any light.
- The glow in the window is a sawtooth and not a smooth wave, because it is cheap and looks busy.

### `menu_ui.odin`
**What it does:** The book of reactions, opened from the book button under the sim test button, or R on a desktop. It is a panel over the lab with a red close button in the top right corner, and while it is open the lab is paused. Page 0 is the contents: a tile for each compound, six to a row, with its colour and its phase, and pressing a tile opens that compound's page. Each compound has a page of its own that lists every reaction that makes it, that makes it when it goes wrong, and that uses it as an input or as a catalyst, and every electrolysis that gives it or is done to it. A line has what it says about the compound on the left (made by, made if wrong, goes into, catalyst in, electrolysed), then what goes in and what comes out, with the purity band that an input is limited to (such as "Water (Distilled water or better)"), and under that the station, the temperature window and the catalyst, or the temperature that it goes wrong at. A line is green for a reaction that cannot go wrong, amber for one that can spatter or give off fumes, and red for one that can burst. A page holds eight lines, and a compound with more has a second spread: water with 13 and sulfuric acid with 11. The back, contents and next buttons along the bottom turn the pages, and each is bright when it can be used and dim when it cannot, so that its state is known before it is pressed. On a desktop the left and right arrows turn the pages. The layout, the page numbering and the turning of pages are plain procedures (`book_tile`, `book_at`, `book_first_page`, `book_press` and the rest) so that `selftest_book` can check them without a window.

**Decisions:**
- A reaction is written once, on the page of its first input, and the book shows it on the page of every compound in it. The book builds a page by asking `chemistry.page_of`, so what it says is what the game does, and no compound has an empty page: hydrogen, oxygen, chlorine, acetaldehyde, ethane, carbon dioxide and persulfate are made only by electrolysis, and their pages show it.
- Every line is shown from the start. Hiding what the player has not found yet belongs to the unlocks, and nothing here says which the player has found.
- The contents page is a grid of large tiles and not a strip of tabs, because 17 tabs would be too small for a thumb.
- Eight lines to a spread so that a line has room for two lines of text on a phone. The kind of line is a short tag on the line and not a heading, so that a heading never takes a line from a spread.
- The page number counts the contents as page 1, and a compound's second spread has its name with "(2 of 2)".
- The real name and formula of a compound are not shown: a page has the game's name, the phase, and how far the compound is from the base chemicals. Whether the book should explain more is open.
- The close button is large and red, and the panel has no other way out on a phone, so it cannot be missed.

**Tests:** `selftest_book` in `selftest.odin`, and for what a page lists, `chemistry_test.odin`.

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

A vial is drawn as a beaker is, a plain tube, in a slightly bluer glass.

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
**What it does:** Every shape, the glass, the liquid, the cap, and the box, faces outward, has unit normals, has the expected number of vertices, and stays inside its vessel's size. The view is a right-handed set and rises with a jump. The default props stand on the island without overlapping, hold no more than their capacity, include one of each of the four chemicals the lab starts with, and nineteen empty vessels. A disc is cut by a line at the right area. The geometry of a tipped vessel agrees with the upright one, holds the same liquid at the level it finds, and holds less the further it tips, nothing at full tilt. The lip is the lowest point of the rim. A tipped prop keeps a right-handed frame. The crosshair picks a second vessel while one is held, close enough and with room. A slightly tipped vessel lets nothing out. A stream goes into the vessel under the crosshair. A pour of water into spirit starts its quiet reaction once, however long the pour. Water poured into acid spatters and hurts, and water poured into the hot mix of spirit and acids bursts, hurts, and breaks the vessel. A drop starts a reaction only when the mix comes to its proportions, and after that only when it has stopped being them and become them again. A drop into a full vessel is lost, one that does not fit is cut, a spatter loses some liquid and hurts more the closer the player is, and a reaction says what it made and how hot it got. A vessel is found under a nozzle only in the right place, a tap fills it with its own liquid, a locked tap and one with nothing in it give nothing, and the bottles are the colors of their liquids. A drop lands and is wiped away, one outside the box or in a full stream is refused, and a pour from high over the floor falls out. Removing a vessel keeps the other indices right. Health drops, comes back, and ends at zero. A vessel cannot be filled past its capacity and holds nothing without a compound. Capacities are between 400 and 1000 ml, and a beaker's matches a hand calculation. The level never drops as the amount grows and matches the volume. See-through props are ordered far to near. The crosshair picks a prop it points at, and not one it points over or one out of reach. A counter hides what is behind it. Grabbing takes the aimed prop once. A sweep of positions and view directions near and far from the counters shows that a held prop never enters a counter or leaves the room. A vessel in open space sits at the hold point. Released props fall to a counter or the floor. The hands close and open again, every hand part is right-handed and stays near the eye, an unturned part follows the view, and a turned prop keeps a right-handed frame.

The defaults are the 23 vessels of the island and 24 vials in the racks, and the capacities test knows a vial holds about 33 ml. The tests of the racks and of the scale and the cabinet are in `gear_test.odin`.

### `stations_test.odin`
**What it does:** A balloon takes drops of water, keeping all of it, and drops that blend in their temperature and purity. Drops of water into spirit start the quiet reaction of the pages once, as the mix comes to the right shares, and warm it once and not with each drop. Spirit and the two acids at 160 degrees with water poured in is a blast: the balloon and its liquid are gone, it hurts, drops with no balloon are lost, and a fresh balloon is clamped after two seconds. Filling with water bursts it on the first drop over the limit, once, and no more than a drop past. Strain runs from 0 at a fill of 1 to 1 at the limit. A spatter, water poured into acid, loses a fifth. A reaction says where it was. The faucet of the sink gives water at a purity of 0.25, the bottle wall has no water and its chemicals come pure, a vessel held under the faucet is found and filled with sink water, and one at the wall is not under the faucet. The crosshair finds the funnel when looking at it, and not when looking away, too far, or with no balloon. A nearer vessel wins the aim. The pour button is ready for the station only with a vessel held, the station aimed at and close, and no vessel to pour into. A full pour from a held beaker into the funnel puts most of it in the balloon and makes nothing from nothing. Drops pass through the funnel with no balloon, and only drops inside its column are taken. The drain takes what falls in the basin near the counter top, and nothing else. The hood shields only what is inside it, and a blast in the hood hurts a fifth as much as the same blast outside. The gauge lights one after another, from the bottom, and goes from green through amber to red. Speed goes round 1, 2, 4, 8, and an unset speed is 1. A pour into the funnel at eight times normal speed empties the beaker more than three times sooner than at normal speed and delivers as much. A tap fills a vessel that is not under it, and a tap at four times normal speed gives more than two and a half times as much in the same time, and neither makes liquid from nothing. Each test was checked by changing the code on purpose and seeing it fail.

### `oven_test.odin`
**What it does:** A port takes one liquid and turns other liquids away, telling the player once, then again after a while, and the turned away drop is gone. Each port has its own funnel. A full port loses the rest, and only drops inside a funnel are taken. A shut oven takes nothing. A run needs something in a port and an empty tank, and cannot start twice. A run takes its time and then makes the product of the reaction matrix with the amounts added up. A violent mix, which is a blast in a vessel, is safe in the oven and gives its product, with none lost. The ports are mixed in order. The same liquid in two ports adds up, and one port moves over unchanged. Speed shortens a run. The crosshair finds the oven and the port it points at, for each of the four, and not when looking away, too far, or with a vessel nearer. The run and pour buttons are ready only when they should be. A vessel is found at the spout only when there is product, and not when it is too far to the side, far below, tipped, full, or not held. The spout fills a vessel that is off to one side with the product and loses none. A spout at eight times normal speed lets out drops of eight times the size, empties the tank in under a second, and has no more drops in flight than at normal speed. A vessel standing on the tray is found only when there is product, and not when it is off the tray, in the air, tipped, full, or held, and it is filled by the spout without being held. Each test was checked by changing the code on purpose and seeing it fail.

### `heat_test.odin`
**What it does:** A vessel on the hot plate warms by 6 degrees a second and reaches 160, and one in the ice bath cools the same way to 0, and neither goes past the ends. A hot vessel taken off cools slowly, 2 degrees a second, and a cold one warms the same way, and both stop at the room. An empty vessel, a held vessel, one in the air, and one beside the plate take no heat. The words and the numbers for the temperature change at the right places, down to a degree that is warm and one that is hot. A hot drop warms the liquid it joins by its share, and into an empty vessel it is the drop's own temperature. A vessel that is heated into the window of a reaction reacts, once, when it gets there, and one that is heated past a limit spatters, and one past a burst breaks. A pour carries the temperature of the vessel it comes from, and a hot or cold drop that lands in a vessel or the funnel brings its temperature and keeps its purity, and the drop that is left in the stream after one is taken out is the right one. A balloon takes the temperature of what is poured in, and loses it when it bursts. The liquid in the balloon of the fill station drifts back to the room at the rate of a vessel and stops there, one with nothing in it has no temperature, and tied balloons cool in the hand, the clamp, and on the hooks. Vessels stand on the station of the pages that the plate and the bath stand for.
The moved-station tests check that a plate and a bath that are moved heat and cool at their new places and not at the old, that a plate that is turned heats where its plate now lies, that the station a vessel is on follows where the stations stand, and that a drop is judged by the station where the vessel is now.

### `loadout_test.odin`
**What it does:** The crosshair finds the paint station, each hook, and the fill clamp, and nothing when looking away, when too far, or when a vessel is nearer. The grab button does the right thing at each place: tie and take only with empty hands and something in the balloon, clamp or take at the paint station, store or take at a hook, and nothing when the place or the hand is the wrong way round, or when a vessel is held. Tying takes what is in the balloon, the whole mixture with its temperature, and the station makes another. A stretched balloon is let down to full, and the excess is told. Balloons move between the hand, the paint station, and the hooks with every field unchanged. Burning needs a balloon in the hand and no vessel, takes the hand and nothing else, leaves the paint station and the hooks as they were, and does nothing with empty hands. The presets are what the server needs of the hooks that hold a balloon, with the volume rounded and held to a full balloon, and with the balloon in the hand and the paint station left out. Each test was checked by changing the code on purpose and seeing it fail.

### `art_test.odin`
**What it does:** A dab is a round spot, 5 across to each side and 10 down, with an empty corner. A dab at the seam comes in on the other side, and a dab at the top or bottom is cut off and nothing is outside the canvas. Everything that changed is in the dirty rectangle, the version goes up, and taking the rectangle forgets it. A line leaves no gaps, flat or slanted, and goes straight across the canvas and not the short way round the seam. The eraser takes paint off, and clear takes all of it. Pixels become RGBA with no paint see-through. The store gives out ids from 1, runs out, takes freed ids again, and a reused drawing is blank. A stroke paints with the chosen paint and brush, and moving without a stroke paints nothing. Blending red and yellow makes orange where they meet and changes nothing far from the pen or outside the dab, a flat color or empty canvas is left alone, it works up and down and across the seam, it puts down no paint, and it can be taken back. A picture is given the rectangle that changed only when it has everything before it, and the whole drawing when another picture has taken the rectangle or it is further behind. The middle of the picture faces the viewer from any side. Undo takes strokes back in order, to the eight it keeps, and a clear can be taken back. Each test was checked by changing the code on purpose and seeing it fail.

### `paint_layout_test.odin`
**What it does:** On six screen sizes, everything is on the screen, the tablet is twice as wide as high and big enough to draw on, and nothing covers anything else. A touch is on the thing under it: done, undo, clear, each brush, each swatch, the tablet, the balloon, and nothing in a corner. The edges of the tablet are the edges of the drawing, and a point outside it is not on it. Everything to draw with is down the right and the balloon and the done button are on the left with a gap, the panel backs the tablet, its buttons, the palette, and the brushes and neither the balloon nor the done button, the balloon area is at least 0.55 of the screen height wide, and the tablet stays at least 0.3 of the width and twice as wide as high, even on a square screen. The test of overlaps found that the row of brushes had been put halfway up the tablet instead of under it, before it was ever run on a screen.

### `art_codec_test.odin`
**What it does:** A flat drawing encodes to the same bytes as the Rust codec, in full, and a noisy one is raw and has the same length and hash. The bytes the Rust codec made decode to the drawing they were made from. Both formats round trip, and a blank drawing is a few bytes. Bad bytes are refused and the drawing is left alone: nothing, too short, a missing run, bytes left over, a format that is neither, a color outside the palette, a run of nothing even when the rest adds up, runs past the end, and a raw drawing that is short. A decoded drawing is marked as changed. The hexadecimal goes both ways and refuses an odd length and characters that are not digits. Each test was checked by changing the code on purpose and seeing it fail, and four gaps that found were closed.

### `loadout_save_test.odin`
**What it does:** A loadout survives being saved and read back: every field except the temperature and the unsafe meter, with a mixture of several compounds and their purities, and each drawing pixel for pixel, each with an id of its own. A trace that rounds to no millilitres is left out, a purity of 53 percent is not written as 52, and an ingredient list that is bad in any of its fields skips the line. An empty loadout is the header and reads back empty. Text without the header, or with another version, is not read at all. Bad lines are skipped and the good ones come back, and a balloon whose drawing is bad or does not decode comes back without it and leaves no drawing in use. When the store is full the balloons still come back. The amounts are rounded to the nearest millilitre. The places are named hand, paint, and one for each hook.

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
**What it does:** Reads every finger on the screen as a list of pointers with stable ids and hands them to the `touch` package, which turns them into movement, look and button controls. `Controls` keeps what the package says each frame: the walking stick (`stick`, with `stick_anchor` and `stick_knob` for drawing), the pixels the view should turn (`look_delta`), and two bit masks, `pressed` and `held`, with one bit for each button box a scene lists. `button_pressed` and `button_held` read them. On a phone, the first finger that lands on the left half of the screen becomes a floating walking stick wherever it lands, and the first finger that lands on the right half, off any button, turns the view by how far it moves. A button listed in the aim mask, such as the arena's throw pad, also turns the view by the movement of its finger. With a mouse there is no walking stick, a drag anywhere turns the view, and the keyboard walks. It also draws the walking stick and the scene-switch button.

**Decisions:**
- A finger is tracked by the id Android gives it and not by its index, because the index shifts when another finger lifts.
- The job a finger gets when it lands, a button, the walking stick or the look finger, is kept until it lifts. A look finger that slides over a button does not press it, and a button finger that wanders off its button keeps holding it.
- Any number of buttons can be held at once, one finger each. The old code kept one button finger, so a second button pressed while the throw button was held took the throw away, which made jumping while charging a throw drop the throw.
- A second finger for a job that already has one, such as a second finger on the left half while the stick is held, is a spare and does nothing. It used to become a second look finger.
- A finger that was already down when the scene started is a spare until it lifts, so the tap that switched scenes cannot press the button of the new one.
- Touch positions on Android come from the C wrapper in `android/entry.c`.
- `held` says which buttons a finger is still down on, for the pour and throw buttons, which do their work while held. `pressed` is only the frame a finger lands.
- The scenes find buttons by number, so the order of the list a scene gives `controls_update` matters. The arena names its numbers (`SWITCH_BUTTON`, `THROW_BUTTON`, `SLOT_BUTTON`, `JUMP_BUTTON`).

### `touch.odin`
**What it does:** Package `touch`, the finger-role state machine for the touch controls, with no raylib in it so it is tested without a window. It follows the design of `touch_controls.c` in the owner's Tower-Of-Babylon repository, which had been tried on the same phone. `init` starts it with the fingers already down as spares. `update` runs once a frame with every finger that is down: a finger that lifted gives up its job, a finger that landed is given one, and each finger with a job says what it is doing. A new finger gets, in order, the button box it landed in (the later box where two overlap), the walking stick if it landed in the left half (`STICK_SIDE` 0.5) and no finger holds the stick, or the look job if it landed anywhere else and no finger has it. A job that has a finger already makes the new one a spare, and so does a button that is held already.

The walking stick floats: its middle is where the finger landed, kept far enough in (`anchor_for`) that the whole ring stays on the screen and inside the left half, and it stays put while the finger moves. Its ring is 19 percent of the screen height (`stick_radius`), the same share as Tower-Of-Babylon's 87 of 450. The push is the finger's distance from the middle over the radius, clamped to 1, with a dead zone of 0.08 that is rescaled away, so the edge of the dead zone reads zero and the rim reads one. The look finger and any finger on an aim button add up how far they moved in the frame as pixels, and the total is cut to a fifth of the screen height (`look_cap`) so one late frame cannot throw the view across the arena. Buttons are one bit each in a `u32`, so a scene may list 32.

**Decisions:**
- The state machine is a copy of the idea and not of the code: Tower-Of-Babylon is C on a 800 by 450 canvas and this is Odin on the real screen, so the sizes are shares of the height and the layout stays in the scenes.
- Sprint, stamina and the context flags of Tower-Of-Babylon (locked, walk only, buttons that exist only when available) are not here. The match has no sprint, and the scenes already decide what they listen to.
- The look cap, the 0.19 radius and the 0.08 dead zone are Tower-Of-Babylon's numbers. None has been tried in this game.
- The left half starts the stick instead of the left 40 percent that the first version used, as in Tower-Of-Babylon, so the right half is the look half.
- A desktop (`stick_enabled` false) has no stick and the whole screen is the look half.

**Tests:** `touch_test.odin`.

### `touch_test.odin`
**What it does:** Checks the stick (it appears under the thumb, stays put, answers in a straight line after a dead zone that is rescaled away, stops at the ring, keeps the whole ring on five screen shapes, and gives itself up when its finger lifts), the look finger (it turns by exactly how far it moves, is capped in a frame, and a spare finger does nothing), the buttons (a look finger over a button does not press it, a button finger keeps its button when it leaves, two buttons are held at once, a second finger on a held button is a spare, buttons beat the stick, only the aim button turns the view and the aim finger adds to the look finger), where buttons overlap the later one wins, two buttons that land in the same frame are both pressed, fingers that were down at the start (also more of them than there are slots), a desktop where the left side looks, the limit of eight fingers, a screen with no height, and an empty list. The pixel offsets in the stick tests are shares of the radius, so retuning the radius does not break them, and one test pins where the ring's middle is pulled in to by numbers for a 1600 by 720 screen, so the pull-in is checked as it is and not as the code computes it.

### `chemistry.odin`
**What it does:** Package `chemistry`, the compound pages of `data/chem` as tables, and the rules of `docs/REACTIONS.md` for reading a mixture against them. It has no raylib in it and does not know about vessels, balloons or the world: a caller keeps a `Mixture` and asks what happens. The record types (`Compound`, which now also has the damage, status effect and death effect of its page, `Form`, `Behavior`, `Part`, `Product`, `Reaction`, `Electrolysis`, each list a `Span` into a table) are here, and the tables are in `pages_data.odin`. Lookups: `compound_of`, `id_of`, `reaction_index`, `form_of` (the purity band of a compound, such as distilled water), `electrolysis_of`. A `Mixture` holds up to eight ingredients (compound, amount in millilitres, purity, and whether a reaction made it) in the order they went in, one temperature, the unsafe meter from 0 to 1, and two bit sets of the reactions that have already acted. `mix_add` pours (the temperature becomes the volume-weighted mean). `settle(m, station, unlocked)` lets the mixture react as far as it will and returns what happened as a list of steps (the reaction, the event for the world such as a splash or a burst, whether it failed, whether it was the wrong order). `harm_of` says what a balloon of a mixture does to a player (damage, up to two statuses, the death effect). `mix_draw` takes a drop out of a mixture in the proportions of the mixture, `mix_scale` keeps a share of everything, `dominant` names the main compound, and `name_of`, `cname_of` and `color_of` give a compound's name and colour. `mix_color`, `mix_seed` and `mix_clarity` give what the liquid shader and the vessel colour will need: the colours blend by volume, and the seed of a mix is made from its ingredients' seeds without depending on the order they went in, while a compound alone keeps its own.

**Decisions:**
- `harm_of` says what a balloon of a mixture does to the player it hits: damage, up to two status effects, and the death effect. It is the compounds' own numbers from their pages, read by volume. The server will need the same numbers, and the same function in Rust, when a balloon goes over the wire as a mixture, and that is the next step.
- The engine is a separate package that the lab uses through `mixing.odin`: vessels, the balloon, the oven tank and the tied balloons all hold a `Mixture` and react by `settle`. The wire and the Rust server do not know it yet: a throw sends the main compound and the whole volume.
- How it reads the rules where the rules are silent is listed in `docs/REACTIONS.md`, under "What the engine does with them". The ones that matter most: bands and windows include their floor and not their ceiling, the reaction with the most inputs wins (then a station of its own, then the one listed first), a reaction stays done while its conditions hold and can act again once they have stopped holding and come back, a compound that a reaction made is never the wrong order, and a failure with nothing to make leaves the vessel as it is.
- Reactions are numbered by their place in the table, which is why there are at most 64: the bit sets are `u64`.
- The unlocked list is one bit per reaction, all set by default (`ALL_UNLOCKED`), because how the player earns them is not decided.
- Nothing is allocated, so it can be called every frame.
- `page_of` lists what a compound's page says, for the book: the reactions that make it, that make it when they go wrong, and the electrolyses that give it, then the reactions it goes into, the ones it helps as a catalyst, and the electrolyses done to it. A reaction is still written once, on the page of its first input, and the lookup finds it for every compound in it. `bands_of` and `label_of` name purity bands, so that a line can say "Distilled water or better".

**Tests:** `chemistry_test.odin`.

### `pages_data.odin`
**What it does:** The compound pages as constant tables, written by `scripts/gen_chem.py`: the `Id` of each compound (its number is its place in `data/chem/index.mdix`, from 1, with 0 for none), the vocabulary enums (`Phase`, `Station`, `Event`, `Liquid_Effect`, `Gear_Kind`), and the tables of compounds, purity bands, behaviours, inputs, products, reactions and electrolyses. It is not written by hand: a change to a page is made on the page and the script is run again, and the `chemistry-pages` job of CI fails if the file is not what the pages make. The tables are `@(rodata)` variables so they can be indexed with a variable.

**Decisions:**
- Generated and checked in, and not read from the pages while the game runs, because the client's binding of the DixScript library cannot read decimals or lists or follow imports. See `docs/CI.md`, section `gen_chem.py`.
- The names of the enums are the page vocabulary with the case changed, so `HOT_BATH` is `Hot_Bath`. The page's `Outcome` is `Event` here, because `chem` already has a type called `Outcome`.

### `chemistry_test.odin`
**What it does (the first lines are the harm, the rest are below):** A balloon of one compound does what its page says, an empty one nothing, the damage of a mixture is the mean by volume, a status needs a tenth of the mixture and is full at a half, two compounds with the same status add up to at most 1 and the longer time counts, a hit carries two statuses and the strongest win, the compound that does most of the damage decides how the player goes and a tie goes to the first, and every page has a harm within the limits.

**What else it does:** Runs the rules against the real pages: the numbering of the compounds, what the pages hold (11 reactions, 9 electrolyses, 9 purity bands), purity bands at their edges, pouring, the eight-compound limit, acid into water in clean and in sink water, water into acid, a mixture off its ratio, the boiling limit, a reaction with no outputs that runs once, the reaction with most inputs, the failure outputs of the hot four-way mix, a catalyst that is needed and not used up, station, window and purity, the three things that ethanol and the acid make at three temperatures, what is not unlocked, made compounds and the order of pouring, the unsafe meter inside and outside a window and its stop at 1, ties, colour, seed and clarity of a mix, and electrolysis by band.

**Decisions:** The tests read the real pages, so a page edit that changes a number they pin has to change the tests in the same delivery. The owner reworks the chemistry, so this will happen, and the tests are the list of what the engine promises for the pages as they are.

**The pages of the book:** `page_of` has a line for every reaction on the page of every compound in it, as an input, an output, a failure output or a catalyst, and for every electrolysis on the page of the compound it is done to and of each it gives. Each line is about the compound it is on, appears once, and comes in the order of the kinds. Every compound has a page, none is cut short, and sulfur dioxide is made only when something goes wrong. A short buffer keeps the first lines, and `.None` has none. `bands_of` names the bands that a range of purity covers, at the edges and past them, and `label_of` names a band by its id.

### `scene_room.odin`
**What it does:** The lab room scene. It owns the layout, the player, the room mesh, the controls, the props, the hands, the stream of liquid, the bottle wall, and the health. Each frame it reads the pointers, turns the view by the look drag, and walks by the joystick or the keyboard. The pour button held down either fills the held vessel from the tap it is under or tips it over to pour. The liquid is let out, simulated, and taken by the vessels it falls into, and a reaction that a pour starts is shown and takes its damage. The grab button, or E on a desktop, grabs or releases, and the jump button, or space, jumps. The book button, or R, opens the book of reactions and pauses the lab until it is closed. The room is drawn first, then the hands and the bottle caps, then the liquid in the air, then the liquid in the vessels, then the glass blended over it all. The camera is at eye height, 1.6 m, with a 70 degree field of view. It also owns the effects, the fill station, the reaction oven, and the views of the balloons in the hand, the paint station, and the rack; the balloons themselves are in the loadout in `Game`. The grab button does the balloon action under the crosshair first, then the oven run, and otherwise grabs and lets go, and with a balloon in the hand it refuses to grab and says so. Every vessel is warmed or cooled by what it stands on each frame, and a hot one gives off steam. While drawing, the lab waits: the fingers draw, choose, and turn the balloon, and the camera is close to the balloon in the clamp, turned to put it on the right of the screen, with the hands left out. The drawing screen replaces the usual buttons. The pour is aimed at the funnel when the crosshair is on the station. A reaction in a vessel or the balloon is shown with the effects, takes its damage less what the hood stops, and a burst balloon sends liquid flying. The blast light is given to the room and vessel shaders before drawing, the camera is knocked by the shake, and the wobble of the picture follows the blast. The balloon is drawn after the liquid and before the glass, then the gauge, the hood glass, and the lights of the oven, then the effects. The pour chain is: a tap or the spout of the oven when the held vessel is near one, or a vessel stands on the tray under the spout with the hands empty, and the button is down, then the vessel under the crosshair, then the funnel of the fill station, then a port of the oven, and then a plain pour. A run of the oven puffs steam and rumbles the view a little, and its end shows as a blast at the top of the oven that hurts no one, or a spatter, or just a line, by how violent the worst reaction was. At the incinerator the grab button burns the balloon in the hand: a flash of fire in the hopper in the colours of what was in the balloon, then smoke from the chimney for two and a half seconds, with a low rumble if the player is near. The last button under the scene switch opens the arena. At zero health the player is knocked out and the lab is put back as it was.

**Decisions:**
- Burning is the blast of the effects package, contained as the hood's is, at a small power for the flash, and the vent for the smoke, so the incinerator has no effects code of its own. The balloon is gone from the hand at once, and the loadout is saved the frame after, like any balloon action.
- First person with a joystick, so the room can be crossed without a pointer tap on a floor spot and so stations can be reached by walking.
- The clip planes are 0.08 to 70 for the room. The default far plane of 4000 gives a 16-bit depth buffer almost no precision.
- The button in the corner changes scenes, so the balloon lab stays reachable on a phone.
- The liquid takes as many substeps as a real-time frame needs, or fewer if they would take more than 5 ms, going by how long a step took lately. Then the liquid runs a little slower than real time and the frame is not late.
- The view is knocked by turning the point it looks at a little to the side and up, so the world shakes and the hands do not.
- With the book open nothing in the lab moves and only the book's own buttons work, and the finger that closes it is ignored until it lifts, so closing the book does not start the player walking. The page it is open at is kept in the room, so it opens again where it was closed. Vessels that heat into a reaction while the player looks on show it as a drop would (`room_heat_events`).

The room holds a `First_Aid` and a `Scale`, and `room_reset` clears both. They are aimed at every frame after the vessels are. The grab button heals at the cabinet and zeroes the scale, in the order of the cases after the one for hands full, so a vessel in the hands, or a balloon in them, comes first. The shelves are added with colours from `carry.shelf_colors()`. A line under the crosshair says whether the cabinet is ready, or how long it has to rest, and what is on the scale. The buttons are read with `button_pressed` and `button_held`, so the pour button can stay held while the jump button is pressed.
**Moved stations:** The pick up button picks up the station that the crosshair is on, and it becomes a see-through copy that follows the crosshair (see `blueprint.odin`). While it is carried, the grab button reads place and is bright when the copy can be put down, the button above it rotates the copy a quarter, the pour button reads cancel and pours nothing, and on a desktop E, Q and X do the same. The bag button is dim, and nothing is saved while the station is carried. A tap on a station in the bag carries it too. When a station is put down or put back, the lab and its mesh are built again with the stations where they stand and the scale starts at nothing. A knock-out and leaving the lab put a carried station back first, in the bag if its place is not free. Where the stations stand is saved with the bag and the wall.

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
**What it does:** The 2D pieces of carrying, pouring, and jumping: the crosshair dot with a hand icon under it, lines about the vessel in view or in hand, the grab button in the bottom right corner, the jump button above it, and the pour button to its left. The icon is an open hand in white while nothing is in reach, in teal when something is, and a closed fist while holding. The lines name the liquid and say how full the vessel is, and with a vessel held and another under the crosshair, close enough, they add what is in that one. The grab button says grab, and release while holding, and is dimmer when nothing is in reach. The pour button is held down. It says mix and is bright when there is a vessel to pour into, fill under a tap, and pour and dim when it would only spill. The jump button is dimmer in the air. At the top are a health bar and, for a moment after a hit, a red flash over the whole screen, a white-hot one for a blast or spatter, and a message saying what a mix made. A small button under the scene switch opens the liquid sim test. With the crosshair on the fill station, a line says what the balloon holds and how full it is, in teal turning to red as it nears bursting, and the pour button says balloon. At the incinerator a line says whether a balloon in the hand can be burned, and the grab button says burn.

**Decisions:**
- Grabbing on a phone is a button that turns into the release button while holding, as decided in the design discussion.
- Pouring is a held button. The target is the vessel under the crosshair within 1.5 m, and that is what makes the button bright. The first version asked for the held vessel to be directly over the target, which was hard to line up and gave no hint, so it was changed.
- Buttons have a dark backing, a bright edge, and a shadowed label, so they read on the light floor and walls as well as on the dark counters.
- The icons are drawn from rounded rectangles in code, so no image files have to be packaged into the APK.
- The icons are opaque with a dark outline, so overlapping pieces do not blend twice and the icon reads on light and dark surfaces.
- The contents lines are built in a buffer on the stack, so nothing is allocated each frame.
- The balloon line is not shown when a vessel is the pour target, so two lines never overlap. The oven line shows what each port holds, with the one the crosshair points at in brackets.
- The balloon actions have the grab button too, and it is lit and labelled for what it does here: tie & take, clamp, take, store. A balloon in the hand is told on a line near the bottom of the screen, and a line under the crosshair says what is on the paint station or a hook.
- The contents line adds warm, hot, cool, or cold when the liquid is far from the room, and so does the line for a balloon at the fill station.
- The oven line says where the spout is when there is product in the tank.
- Billboards, which the blasts and steam are, are turned to face the camera and not the player, so they are right when the view is shaken and while drawing.
- The speed button is lit when the speed is not normal, and says which. The grab button becomes the run button when the crosshair is on the oven with nothing held and a run could start.

`draw_station_button` is the grab button for equipment: bright when it would do something and dim when not, so the player knows before pressing. At the cabinet it says heal, wait or healthy, and at the scale zero. `draw_first_aid_readout` and `draw_scale_readout` draw the lines under the crosshair, the scale's in grams with one decimal and marked when it has been zeroed.
**Moved stations:** `draw_pickup_readout` says that a station can be picked up, on the line under the crosshair, for a station that the crosshair is on.

**Stations:** The line under the crosshair for a station that can be picked up names it and says to pick it up, or to take the vessel off it first when one stands on it. While a station is carried the line names it and says whether it can be put down where it is or why not (`carry.blueprint_words`), in blue-green when it can and red when it cannot.

### `mix_label.odin`
**What it does:** `mix_label` says what a mixture is called in a line of text, written into a buffer the caller owns so that nothing is allocated and it can be used every frame: "empty", the name of the one compound, or the name of the compound there is most of followed by how many others there are, such as "Water +2". The readouts under the crosshair use it for vessels, the balloon, the tank, the paint station, the hooks and the balloon in the hand.

**Decisions:**
- The purity is not in the label. The pages make the purity of water matter, but the lab has no way yet to make any water but tap water, and a place to show purity belongs with the sink and the distilling mini-game, which are not built.
- A mix of several compounds is named for its main part and a count, because a reaction can leave a vessel with a product, the water it made and a catalyst, and a name for each would not fit on a line.

**Tests:** none: it has no window in it, but it is in the main package, whose tests are the selftest, and the selftest does not call it. This is a gap.

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
**What it does:** Odin declarations for `tv.h`, with compile-time `#assert`s on struct sizes. ABI version 2 added `TvPlayerView`, `tv_world_join`, `tv_encode_input`, `tv_snapshot_decode_players`, `tv_arena_radius_mm`, and the slot in `tv_encode_throw`. Version 3 adds the buttons byte to `tv_encode_input` and `TV_BUTTON_JUMP`.

**Decisions:**
- The library path is the `TV_LIB` config value, so other targets can point at a different build with `-define:TV_LIB=...`.
- The system libraries listed are the ones `rustc --print native-static-libs` reports for Linux. Other operating systems are not set up yet.

ABI version 4 renames the reserved byte of `TvPlayerView` to `hp`, the hit points left, and adds `tv_max_health`. The struct keeps its 20 bytes.

### `selftest.odin`
**What it does:** Windowless check. It compares the ABI version and struct sizes with the Rust side, plays one balloon from throw to detonation through the C ABI, decodes the snapshot and event bytes, and steps the soft-body ring. It also drops the 3D balloon, then lifts it by the tip, and checks the volume, the resting position, and the teardrop shape. Last it plays a short match through the local host: the player starts on its spawn point facing the middle, walks at walking speed, keeps the heading it is sent, throws a balloon that carries its slot, compound, and owner and flies at the speed its power gives, and sees it burst once on the sand where it was last seen, with the next balloon getting the next id. Frames that are not whole ticks move the player smoothly, and a client that is another player starts at that player's spawn and owns its balloons. A match with the stand-in bot is played for eleven seconds: the bot is a second player on its own spawn point facing the middle, it walks, jumps, and throws twice, its balloons are marked as its own and the two burst, all inside the arena, and the player who sent nothing has not moved. A jump through the local host goes up about 46 cm and comes down in about 0.6 s, with the walk going on in the air. It also checks the drawing screen on five screen shapes by projecting the balloon through the paint camera with plain matrix arithmetic: the middle of it is inside the balloon area, on the left half, the whole of it fits across the area, and from its tip to its bottom it is on the screen.

Three arena checks were added with hit points. The first checks that the starting hit points match the simulation. The second throws one balloon, aimed by the bot's own solver, at a second player who stands still 10.7 m away, and checks that exactly 20 hit points come off them and none off the thrower, all the way through the Rust world, the C ABI and the decoders. The third plays forty seconds against the bot while the player stands still, and checks that the bot turns to face the player, walks, jumps, throws at least eight balloons, that every balloon it throws bursts (bar one that may still be in the air), and that some of them hurt the player, with some of them thrown faster than the weakest throw, which shows the power the bot chose reaches the world. A match seed starts the bot the same way every time, and another seed does not. A fourth check, `selftest_arena_layout`, puts the fire stick, the jump button, the three slot squares, the lab button and the hit point bar on six screen shapes and checks that all are on the screen and none lies on another.

A fifth check, `selftest_arena_bots`, starts a match with the number of bots the arena scene starts, which it pins at three, and plays thirty seconds. It checks that there are four players on spawn points more than 8 m apart, that the bots have different ids and different random numbers, that each bot throws at least three balloons, that their balloons are marked as theirs and the player who threw nothing has none, that at least six balloons burst, that somebody loses hit points, and that nobody leaves the arena. The single-bot checks read the first bot through `bots[0]`.

A sixth check, `selftest_book`, puts the book's close button, its three bar buttons and the 17 tiles of the contents page on six screen shapes and checks that all are on the screen, inside the panel, and none lies on another. Then it checks the pages as they are: 19 pages after the contents, water and sulfuric acid taking two each, the first page of each compound, the back and next buttons stopping at the ends, every tile reaching its compound, and a press on nothing turning nothing.

A seventh check, `selftest_stock`, puts the close button and the 22 slots of the bag and the bottle wall on six screen shapes and checks that all are on the screen, inside the panel, at least 44 pixels across and none lies on another or on a button. Then it drags stacks to and from the wall and checks that the taps follow, that a locked container gives nothing and takes nothing, and the taps on stations: a tap on a station of the bag asks for it to be carried and moves nothing, a drag to another slot is not a tap, a station is not taken by a mount of the wall, a tap with the hands full, on a dispenser, on the wall or after letting go over no slot carries nothing, and a release with no drag is not a tap.

### `main.odin`
**What it does:** Entry point, argument handling, and the frame loop. Each frame it updates the current scene, renders the scene into an off-screen texture, copies that through the heat shader, and then draws the scene's overlay.

**Decisions:**
- The scene renders to an off-screen texture and is drawn through the heat shader, so post effects can cover the whole frame.
- Layout comes from the real screen size, so the same code fits a 1280 by 720 desktop window and a phone.
- The 4x multisampling hint is skipped on Android.
- A missing `os.args` is handled, because it is empty on Android.
- The first scene is the lab room, and `--scene` can pick any of the others.
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
- `load_arena_shader` pairs the same vertex shader with `arena.fs`, and the coliseum falls back to raylib's default shader if it fails to compile.
- `load_spill_shader` loads `spill.vs` and `spill.fs` for puddles and beads of liquid. If they fail to compile, puddles are flat discs that only fade and beads are small diamonds.

### `heat_distort.fs`
**What it does:** A small screen-space ripple. There are two versions, `shaders/glsl330/` for desktop and `shaders/glsl100/` for OpenGL ES 2 and the browser.

**Decisions:**
- The two files are kept in step by hand. Both pass `glslangValidator`, and the desktop one compiled and ran on a software OpenGL context in a headless test.
- The output alpha is forced to 1. The scene is opaque on screen, and the translucent balloon would otherwise leave a lower alpha in the scene texture.

### `arena.odin`
**What it does:** Package `arena`, the match as the client sees it, as data. A `Match_View` holds the tick, the players (id, feet position in metres, heading in radians), the balloons in flight (id, owner, slot, compound, position, velocity), and the bursts since the last step. An `Input` is a stick, a heading, and whether the jump button is held, and a `Throw` is a slot, what is in it, an aim, and a power. A `Host` is a table of four procedures, submit an input, submit a throw, step by a time, and give the view, which is all a scene may use to talk to a match. `Look` is where the player looks, with the pitch held short of straight up or down, and `look_dir` turns it into a direction, with yaw 0 looking toward -z as in the lab. `dir_wire` scales an aim so its longest side is 1000, the form the wire carries. `charge_step` and `charge_power` turn how long the throw button is held into a power, and `Thrower` runs the button: holding charges, letting go throws at the power reached, a tap is the weakest throw, and a throw has to wait out a short cooldown. `slots_from_loadout` makes the three slots of the arena out of the three hooks of the lab, `view_blend` and `lerp_angle` draw the players and balloons between two ticks, and `thrown_by` says whether a player has just thrown, from two views of the match one after the other. It has no raylib dependency, so it is tested without a window.

**Decisions:**
- The owner's words were that the arena only uses the data and does not simulate. So nothing here moves a player or a balloon: positions come from the match and are only placed. The one thing the client keeps is where the player looks, so the view turns the moment a finger moves, and only the heading is sent.
- The host is a table of procedures, so the first host, which runs the Rust world in this process, can be replaced by a network client without the scene changing, and the tests use a fake that only records what it is told.
- The simulation ticks at 60 Hz and the frames do not line up with it, so the view is drawn between the last two ticks, which keeps it smooth at any frame rate and costs up to one tick, 17 ms, of delay. A player or balloon that was not in the earlier tick is placed where it is, and headings turn the short way round.
- The power runs from 60 to 180, which is 6 to 18 m/s, over 1.2 s of holding, with 0.5 s before the next throw can start. These are first guesses to tune by feel. A tap is a gentle lob, and a throw level from 1.5 m up lands about 3 m away at the weakest and 10 m away at the strongest.
- Slot 0, 1, and 2 are hook 0, 1, and 2. A slot with no balloon cannot be chosen, and the throw button says so. With no balloon on any hook, the first slot is a plain water balloon of 500 ml, marked as practice, so the arena can be tried before anything is made. That was not asked for, and is an assumption.
- A throw does not use up the balloon. Nothing says how many a player has in a match, so it stays in the slot, and the hand shows it again when the cooldown is over.
- The fill is rounded to whole millilitres and kept between 1 and what a balloon holds, because the wire carries whole millilitres and the simulation refuses a recipe of nothing.
- A jump is the button held, sent with every input, and the match turns it into a jump only on the floor, so holding the button hops and a tap is one jump. The client does not know how high or how long a jump is. It reads the height of the player from the match and the eye goes up with the feet, so a jump looks the same whatever the numbers become.

**Tests:** `arena_test.odin`.

**Hit points.** A `Player_View` now carries `hp`, the hit points left, and `knocked_out` says a player has none. The zero value of the field is knocked out, so anything that builds a player by hand has to set it, and the tests do. `MAX_HEALTH` is 100 and the self-test checks it against the simulation. The blend between ticks shows the hit points of the later tick, with no blending, because a number of hit points halfway between two is not a thing a player has.

**The throw pad.** `thrower_cancel` lets go of a charge without throwing it, for a player who is knocked out with a balloon in the hand. The fire stick maths that this file once held, `fire_push` and `fire_turn`, a rate stick whose push set how fast the view turned, was taken out: the throw pad now turns the view by how far its finger moves, as the look finger does (see `touch.odin`), so there was nothing left for it to do.

**Decisions:**
- Hit points are shown, never worked out: the client does not know how much a balloon hurts.

### `arena_test.odin`
**What it does:** Looking follows the lab's headings, and the pitch stops short of straight up and down. The direction on the wire keeps its heading and is scaled to 1000. A throw charges over the set time and stops at full, and the power runs from the weakest to the strongest and never falls as the charge grows. Slots follow the hooks one for one, the fill is rounded and kept inside what a balloon holds, and an empty loadout offers one practice balloon while any other loadout gets none. The thrower starts on the first balloon it has, only a slot with a balloon can be chosen, and choosing another drops a throw in progress. Holding charges and letting go throws at the power reached, a full charge is the strongest however long it is held, a tap is a weak throw and not no throw, the cooldown has to be waited out and shows before the button is pressed, nothing is thrown from an empty slot or without a press, and a balloon that goes while it is being charged is not thrown. Players are found by id, the eye is above the feet and goes up with them, and a player is on the floor within 2 cm of it. A host is driven only through its table. Headings turn the short way round, drawing between ticks lies between them with the ends where they should be and the alpha kept inside 0 to 1, things that are new appear where they are, things that are gone do not, and balloons are matched by id and not by place in the list.

Hit points: a player with none is knocked out and one with one is not, the blend shows the later tick's hit points, also for a player the earlier tick did not have, and cancelling a charge throws nothing, costs no cooldown, and lets a new charge start at once.

### `coliseum.odin`
**What it does:** The shape of the coliseum, as a list of boxes that may be turned about the vertical axis, built by `coliseum_build`. The sand is one slab with two rings drawn on it, 2 cm up. The podium wall stands where the floor of 20 m radius ends, 2.4 m high. Five tiers of seats rise outward from it, each 1.8 m deep and 1 m higher than the one before, in 72 boxes a ring, with a stair every ninth box, a little lower and darker, so the seats read as blocks. An outer wall 12 m high stands behind them with a ledge on top, dark openings and columns along its inside, and a banner over each of four gates, red and blue in turn. The four gates are in the podium wall at the compass points, a door between two pillars under a lintel. It comes to about 800 boxes. `piece_distance` measures from the middle of the arena to the nearest point of a box, `piece_corner` and `radial_yaw` spell out the turn, and `ring_chord` is how wide a box in a ring has to be to meet its neighbours.

**Decisions:**
- Boxes that can be turned are enough for a round building. A ring of 72 boxes, each 6 percent wider than the gap it covers, has no cracks and no visible corners at the distances it is seen from.
- Nothing of the building stands inside the 20 m of the floor, except the gates, which stand 8 cm out of the wall. The simulation stops players 0.3 m from the wall, so a door that far out is only a lump in the corner of the eye, and there is no collision in the client at all. The tests check this for every box.
- The numbers are the radius of the arena, which the simulation owns, and a few sizes chosen by eye. The building has not been seen, only built and measured.
- A mesh with 16-bit indices holds 2730 boxes, and the coliseum stops at 1200 so there is room to grow.

**Tests:** `coliseum_test.odin`.

### `coliseum_test.odin`
**What it does:** The coliseum is hundreds of boxes and stays under the limit of its mesh. Every box has volume and is opaque. Nothing tall stands on the sand, and what lies on it lies flat and inside the arena. The distance to a turned box is measured along its own axes, ring boxes meet their neighbours, are on the ring, and face outward, and the corners of a turned box are a rectangle of the right size round its middle. The tiers rise as they go out, there are stairs in every tier, four gates stand at the compass points, the whole building is within about 31 m of the middle, and building twice gives the same coliseum.

### `host_local.odin`
**What it does:** The match host that runs the Rust world in this process through the C ABI. `local_host_new` makes a world and puts the player in it. The input is sent again every tick, with the jump button as it is held, because the simulation stops a player whose client goes quiet and a button held must not be lost with one packet. Each step runs as many ticks as the frame time holds, up to eight, reads the snapshot back through the Rust decoders, collects what burst, and gives out the players and balloons between the last two ticks. A throw is encoded by the Rust library with one chamber, the compound there is most of in the slot and the whole amount of it: the wire carries one compound until it carries a mixture, so a balloon of a mixture is thrown as its main part for now, and the slot, the hand and the save file keep the whole mixture. If it is started with bots, the next players, up to `MAX_BOTS`, are stand-ins that the host drives as clients would: each tick each one sends an input and now and then a throw of 300 ml of water straight ahead and a little up, both from `bot.odin`. The arena starts three. A bot goes for the nearest player who is standing, so the bots also throw at each other.

**Decisions:**
- Everything the scene knows comes back through the wire format, the same bytes a network client would get, so what is seen here is what a server would show. No position, heading, or velocity is read from the simulation's own structures.
- The player joins by `tv_world_join` before the first frame, so the scene can read where it starts and face the middle. If it joined by sending an input, the heading in the input would replace the spawn heading before the scene could see it.
- Only eight ticks are run for one frame, so a slow frame cannot make the next one slower still.
- The simulation's volatility is a placeholder zero until the compound database is shared, so every burst is a plain splash and the field is read, passed on, and never seen to be anything else. The self-test cannot check it for that reason.

Each player's hit points are read from the snapshot into the view. The bot looks at the match as of the last tick, with `bot_step(&bot, &curr, id, dt)`, and sends what comes back as a client would: an input every tick and a throw when it throws, a water balloon of the practice size with the aim and power the bot chose. Each match seed gives each bot its own random numbers, and the first bot has the numbers a match with a single bot always had.

### `arena_view.odin`
**What it does:** The coliseum mesh and the balloons. `arena_mesh_init` builds the mesh the way the lab's is built, a colour for each vertex, from boxes that may be turned, into a `Lab_Mesh`, so it is drawn and freed with the lab's own procedures. `Arena_View` holds a balloon body for the hand, one for each slot to draw its balloons in flight, and a plain one for everybody else's. Only the one in the hand is simulated, and swings from the hand as the lab's does. The others are posed once, hanging, and drawn wherever the match says a balloon is. The player's own balloons wear the drawing of the slot they came from, and the picture goes slowly round them as they fly.

**Decisions:**
- A balloon in flight is drawn three times life size. At life size it is 15 cm across and a speck across 20 m of sand.
- The balloons in flight have no soft body of their own, so any number cost the same as one: a mesh drawn again with another matrix. A balloon is posed again only when its slot changes.
- The balloon in the hand is hidden while the throw is cooling down, which is how the player sees that the balloon has left.
- The balloon of another player is drawn plain, at 500 ml, because the snapshot does not say how full it is or what drawing it wears. Drawings are meant to travel once, when a player joins, and that is not built.

### `arena_ui.odin`
**What it does:** The overlay of the arena. The throw button sits where the grab button does in the lab, a row of three slot squares sits just left of it, and the arena button of the lab sits under the speed button. A slot square shows the colour of what is in it, its number, and its amount, is outlined brighter when chosen, and is dim and says empty when it has no balloon. The throw button says throw, release while charging, wait during the cooldown, or no balloon, is bright when it would throw and dim when it would not, and a bar along the bottom of it fills as the throw charges, inside the button because the jump button is just above it. A small cross marks the middle of the screen.

**Decisions:**
- A button shows whether it can be used before it is pressed, as the other buttons do.
- Text is formatted into buffers the caller owns, and not into the temporary allocator, so a frame costs no allocation.

**The throw pad.** The throw button is a round pad in the bottom right corner, of radius 12 percent of the shorter side of the screen but never under 60 px. A finger that lands anywhere in its square box holds it. While a finger is down the throw charges, the view turns by how far the finger moves (the scene lists the pad as an aim button, see `touch.odin`), and letting go throws. The pad is bright and says throw when it would start a throw, dim and says wait during the cooldown or no balloon without one, says release while charging, and says knocked out and is dim for a player who is down. A gold ring round it fills clockwise from the top as the throw charges. The three slot squares sit to its left level with its bottom, and the jump button above it, a little narrower. The hit point bar sits at the top left under the three lines of text, green, then gold at half, then red at a quarter. A red cross round the crosshair shows for a moment when a balloon hurts somebody. The floating stick that the first throw pad drew under the thumb is gone, because the pad no longer works as a stick. The procedures keep their old names (`fire_stick`, `fire_radius`).

### `scene_arena.odin`
**What it does:** The arena scene. On load it builds the coliseum, starts the local match, takes the three slots from the loadout, and faces the player toward the middle. Each frame it reads the pointers, chooses a slot from a slot square or the keys 1, 2, and 3, turns the look by the drag, and sends the stick and the heading to the match. The match has three bots. It runs the throw button and sends a throw where the player looks when the button is let go, steps the match, and shows each burst as a splash four times the size of a lab pop, or as a blast and a flash of the screen if the simulation ever says the burst was violent. The camera is at the eye of the player as the match places it, with the view knocked by a blast. The coliseum is drawn first, then the balloon in the hand and the balloons in flight, then the other players, then the effects. A desktop walks with WASD or the arrows, drags the mouse to look, jumps with space, holds E and lets go to throw, and chooses with 1, 2, and 3. A phone walks with the left thumb and looks with the right, and has a jump button above the throw button, as the lab has, that is dim in the air.

**Decisions:**
- The scene does not move anything. It sends and draws. The player's look is the one thing it keeps.
- The clip planes are 0.08 to 70 as in the lab. The outer wall is 31 m from the middle, so from the far side of the sand it is about 51 m away, and fits.
- E throws and space jumps, as E is the action key and space the jump key in the lab. The first arena had space for the throw, which was the wrong key to give away once there was a jump.
- The balloons are the loadout, hook for hook. Nothing here changes the loadout, so nothing is saved on leaving.
- A throw does not use the balloon up, and the practice balloon is a guess, see `arena.odin`.

A finger on the throw pad charges the throw and turns the view by how far the finger moves, the same way as a finger anywhere else on the right half, and a thumb on the pad and a finger on the jump button work at the same time. The scene watches each player's hit points from frame to frame: a loss for the local player flashes the screen red, scaled by how much was lost, a loss for anybody else shows the red cross, and a knock-out is said in a line of text. A player who is knocked out cannot throw, a charge in progress is let go of without throwing, and the screen says knocked out and back in a moment until the match brings them back. Who threw is not in the view, so with one other player in the match the cross means the local player's balloon hit.

### `arena.fs`
**What it does:** The fragment shader of the coliseum. There are two versions, `shaders/glsl330/` for desktop and `shaders/glsl100/` for OpenGL ES 2 and the browser, and both use the lab's vertex shader. It is the lab's shading, a ground and sky ambient term, a key light, full brightness for anything emissive, a sheen on glossy surfaces, and the light of a blast, in a sunlit setting: the ambient is warmer from below, the key light is stronger and from a lower angle, and the haze is the colour of the sky and starts at 45 m instead of 10.

**Decisions:**
- It is a copy of the lab shader with changed numbers, and not a new uniform on the lab shader, so no scene of the lab can change by it. The lab's haze would have put the far stands in fog.
- The sky colour is the colour the screen is cleared to, so the far wall fades into it. It is `ARENA_SKY` in `scene_arena.odin`, as 8-bit values.
- The two versions are kept in step by hand, and both pass `glslangValidator`.

### `character.odin`
**What it does:** Package `character`, a temporary player character built in code, after the owner's low-poly lab-coat design. This file is the maths and the shapes it is built from. A `Mat` is a 4 by 4 matrix, row-major with the move in the last column like raylib's, and there are the usual moves and turns about each axis. A `Soup` is triangles with a flat normal, a colour, and a glow for each vertex, wound counter-clockwise from outside, and `soup_box`, `soup_ellipsoid`, and `soup_cylinder` add a box, a faceted ellipsoid, and a closed cylinder to one, placed by a matrix. It has no raylib dependency, so it is tested without a window.

**Decisions:**
- The shapes are flat-shaded and low-poly on purpose, as the design is, and a mesh of triangles with no indices is enough for them, so there is nothing to index or share.
- The turn about the vertical axis is the one the boxes of the coliseum use, so a character and a building turned by the same yaw turn the same way. A turn about x that is positive swings the end of a hanging part toward -z, which is forward for a character that faces -z, as a player at yaw 0 does.
- A sliver of a triangle with no face is dropped, and a soup that is full stops taking triangles and does not run over.
- This is a stand-in. The owner wants a soft character that goes limp and can be blown up or melted, which stiff parts moved by a pose cannot be. See `model.odin`.

**Tests:** `character_test.odin`.

### `character_test.odin`
**What it does:** The identity changes nothing, and a product of matrices applies the right one first. A turn about y is the turn the coliseum's boxes use, a positive swing about x takes the end of a hanging part forward, and a character at yaw 0 faces -z and at a quarter turn faces +x. A triangle has a unit normal that follows its winding, a sliver is dropped, and a full soup stops. A box is twelve triangles that wrap exactly its volume, with every normal pointing out, turned or not. An ellipsoid is closed, wound outward, a little smaller than the true one and closer to it when finer, with its corners on the surface and its poles at the ends. A cylinder wraps the volume of its polygon, with its caps facing up and down, and has the same volume on its side.

### `model.odin`
**What it does:** The six parts of the character that move, `Body`, `Head`, `Arm_L`, `Arm_R`, `Leg_L`, and `Leg_R`, each a soup built round its own pivot, and the palettes that colour them. The body is a round coat, wider than it is deep, with a vest down the front, lapels and pockets in the trim colour, a collar, a badge on a strap, and a pen. The head is round with goggles, a mask over the lower face with a round filter, and a quiff of three boxes. The arms hang from the shoulders with a sleeve, a cuff, and a round hand, and the legs from the hips with a trouser leg and a flat shoe. The character is 1.94 m to the top of the quiff, stands with its feet at the origin, and faces -z. `palette_for` gives eight different trims, and the hair is the trim darkened, so players can be told apart, and `root_matrix` puts the whole character on the floor at a position and a heading. It comes to 668 triangles.

**Decisions:**
- The eyes are at about 1.62 m, which is where the first-person camera of the arena is, so another player's goggles are where they would be looking from.
- Each part is written in the space of the character and moved to its pivot, so a part turns about its shoulder, hip, or neck as it is.
- The details sit a little into the surface of the body, because the facets of a low-poly ellipsoid are inside the true one by up to a few centimetres.
- Eight players cost under 8000 triangles, which a phone draws without noticing. Nothing here has been seen on a phone.
- The design is a T-pose with the arms straight out. In the game the arms hang a little out from the sides, as a body at rest would.
- The owner asked for a soft and ragdollable character with weird physics when blown up or melted. This one is the temporary stand-in he agreed to while he works out the game loop. It has no softness: its parts are stiff and moved by a pose. The balloon's soft body, the limbs as chains of particles with distance constraints, and a stiffness that falls as it melts are the likely way to the real one.

**Tests:** `model_test.odin`.

### `model_test.odin`
**What it does:** Every part has a body and is not full, the whole is under 1000 triangles, and every triangle has a unit normal and an opaque colour. Each part is closed and wound outward. The character stands on the floor and is as tall as it is said to be, its goggles are at the height of the first-person eye, and its front is -z: the mask and lenses are in front of the head and the vest and collar are all in front of the body. The left side is -x and the two sides are the same shape. The arms and legs hang from their pivots, the shoulders are on the body and the hips at the bottom of it, and the head sits on the neck. Eight palettes are different and wrap, the hair is darker than the trim, a palette changes the colours and not the shape, and building again gives the same model.

### `pose.odin`
**What it does:** How the character moves. An `Anim` follows what the match says of a player: how fast it moved, whether it is in the air, and whether it has just thrown. Walking swings the legs against each other by up to 0.7 radians, the arms against the legs by up to 0.5, and bobs the body by up to 3 cm, all scaled by how fast it goes up to walking speed, with a stride of 2.2 radians for each metre a second. In the air the swing stops, the legs are drawn up and the arms go out and forward. A throw takes half a second: the right arm winds back 1.3 radians, goes up and forward to 2.4 over the head, and comes down. `part_matrix` gives the matrix of each part from the one of the whole character and the pose, turning it about its pivot.

**Decisions:**
- The speed and the air are smoothed, so stopping and landing are not snaps, and a long frame cannot throw the smoothing past where it is going.
- The speed is worked out by the caller from how far the player moved between frames, because the snapshot carries a position and not a speed.
- A throw is seen when a balloon of the player appears, because the snapshot carries no event for it. It owns the right arm for its half second, whatever the walk was doing.
- The numbers are first guesses, as the walk speed and jump of the match are.

**Tests:** `pose_test.odin`.

### `pose_test.odin`
**What it does:** A character standing still is not swung or lifted. At full speed the legs swing against each other and the arms against the legs, to the full swing and no further, and slower walking swings less, up to walking speed. The cycle goes round at the speed of the stride and the phase stays inside one turn. Stopping slows down and does not snap, a big frame does not throw the smoothing past its target, and the air is eased into and out of. In the air the legs are drawn up, the arms are out and forward, and the walk stops. A throw winds back, goes up and forward, and comes down, at 0.2 s and 0.35 s, with no jump bigger than a few hundredths of a radian in a millisecond. It runs its course and ends, moves the right arm only, and wins over the walk. The body and head are lifted by the walk and the legs are not, a part swings about its pivot and stays on it, the arms are held a little out and further in the air, and placing a character puts its parts at the feet facing the heading.

### `bot.odin`
**What it does:** A stand-in for another player, so there is somebody to fight while the match has only one human. `bot_step` looks at the match like a client would and gives what a client gives: an input and, now and then, a throw with its aim and power. Each step it picks the nearest player still standing, and keeps its idea of how fast they walk from how far they moved. It turns, at no more than 3.2 rad/s, to face the heading a throw has to go in to meet them (`bot_aim`, which leads a walking target and solves the arc for the simulation's gravity and the hand's height and reach), and throws when it faces that heading within 0.12 rad, the target is between 3 and 18 m away, it has been after them for 0.35 s, and 2.2 to 4 s have passed since its last throw. Between throws it keeps a range: it closes in beyond 11 m, backs away inside 6 m, and circles at a good range, changing direction every 1 to 2.5 s with a chance of 0.7. It sidesteps the path of a balloon of somebody else's that is coming its way within 7 m and passing within 1.8 m, steers in from the wall beyond 16.5 m, taps jump now and then, and with nobody left to fight walks back to the middle and waits. Wounded, at 30 hit points or fewer, it wants to be between 10 and 15 m away. A bot that is knocked out does nothing.

**Decisions:**
- The bot gets only what any client gets, the match as the view shows it, so a network client can take its place and a person could play the same part. It is driven by the host and not by the scene, so the scene does not know the other player is not a person.
- Its aim error is a random amount of up to 0.012 rad plus 0.005 rad for each metre to the target, drawn from its own random numbers, so two runs with the same seed play alike. `sloppy` scales it, and the tests set it to 0 to test the solver apart from the error.
- Measured with a flight model of the simulation's own rules (see the tests), a throw from a bot with that error hits the body of a player who stands still every time at 6 m, about two in three at 10 m, and about one in three at 14 m. The splash of a balloon reaches 1 m or more, so more of its balloons hurt than hit.
- It picks a speed that gives a flat arc, which forgives a small error in the distance, and throws at full power only when that falls short.
- It aims at 1.1 m above the target's feet, the middle of the chest, and ignores how fast the target moves up and down.
- Every number at the top of the file is a first guess. None has been tried against a person.

**Tests:** `bot_test.odin`.

### `bot_test.odin`
**What it does:** The maths: the flat arc matches the textbook, an arc passes through the point it is asked for at several speeds and heights, launches are whole tenths of a metre a second inside the power range, and `bot_aim` sends a balloon into the body of a player standing at every range from 3.5 to 17.5 m and every heading, leads a walking player (and misses one if it does not lead). The behaviour, each part against a fixed view: it turns at its rate and no faster, and the short way round; it picks the nearest player standing and turns to the next when they are knocked out; with nobody to fight it goes to the middle and waits, and a bot that is knocked out does nothing; it keeps its range with the right push at too far, too close, a good range and half way, and keeps a longer one when wounded; it circles and changes its mind within bounds; it waits to notice a target; it lets go only when it faces its aim; it spaces its throws; it throws only within reach; what it throws is a unit vector with a power a player could throw with; its throws hit a standing player often but not always; it sidesteps a balloon coming at it to the right side and in the right amount and ignores its own, one that has passed, one that is far, one that passes wide and one that is slow; it comes in from the wall; it taps jump; it plays the same for the same seed; it starts afresh on a player who was knocked out and came back; and the stick it gives walks where it wants to go. Flights are worked out by a small model of the simulation's own rules, written in the test file.

### `character_view.odin`
**What it does:** Draws the other players of the match as the temporary character. The first time a player is seen, meshes are made for each of its six parts in the colours of its id. Each frame, each player's animation is moved on by how fast it moved since the frame before, whether it is in the air, and whether a balloon of its own has just appeared, and each part is drawn with its own matrix, with the material of the coliseum and so its shader. The local player is not drawn, because the camera is in their head.

**Decisions:**
- The coliseum's shader already moves a mesh by the matrix it is drawn with, so the character needs no shader of its own.
- Meshes are made when a player is first seen and not for all eight at the start, because a match has few players, and each costs 668 triangles and a few allocations.
- The glow and sheen of each vertex ride in the texture coordinates, as the coliseum's do.

A player who is knocked out is not drawn. Over the head of every other player who is standing a bar of hit points faces the camera: a dark back and the part left in front of it, from the left, green, then gold at half, then red at a quarter. It is made of two flat rectangles, each of two triangles, drawn in the same pass as the characters.

## CI and Workflows

- `.github/workflows/ci.yml` job `odin` downloads a pinned Odin release, runs `odin check`, the soft-body, balloon, lab, carry, and effects tests, validates all the shader files, builds and runs `--selftest`, and renders headless screenshots of the lab resting and held by its tip, which are kept as an artifact.
- `.github/workflows/bench.yml` runs the Odin benchmark and merges it into the result file.
- `scripts/build_client.sh` is described in `docs/CI.md`.

### `equipment.odin`
**What it does:** The smaller equipment of the lab, in package `lab`: where it is, and the boxes of what is static. Four racks of vials, two on the north counter at its west end and two on the south counter, each with two rows of six holes 5 cm apart; a first aid cabinet on the north wall; a scale on the north counter between the ice bath and the oven; and two shelves of twenty bottles each on the south wall over the south counter. `vial_slot` says where the foot of the vial in a hole stands, the first six holes being the row nearer the player. `add_equipment` builds the racks, the cabinet and the scale, and `add_apparatus` calls it, and `add_shelves` builds the shelves from a list of bottle colours given by the caller, as `add_dispensers` is. None of them adds a collider: a counter blocks the player and these stand on counters or hang on a wall.

**Decisions:**
- A vial stands with its foot on the lower plate of its rack, 3 cm over the counter, and a deck 6 cm over it holds it upright. The holes are dark squares on the deck, and the vial passes through the deck as a box, which is not a hole. A vial in a rack therefore shows the deck cutting across it, which is as far as the look has been taken.
- The scale's plate is 40 by 35 cm and its top is 7 cm over the counter, and a vessel on it stands there (see `standing_height` in `carry.odin`).
- The bottles of the shelves are glass in the colours of the compounds, a dark cap, and a pale label on the side toward the room. The labels carry no writing, and nothing says what is in a shelf bottle: they are for the look of the room, and the colour of each is the colour of a compound in turn.
- The numbers are first guesses, to be moved by looking at the room. `MAX_BOXES` was 256 and is 640: the room with all of this takes about half of it, and one mesh holds 2730 boxes.

**Tests:** `equipment_test.odin`.
**Moved stations:** The scale is built by `add_placed`, where it stands, and not by `add_equipment`.

### `equipment_test.odin`
**What it does:** The racks, the cabinet, the scale and the shelves add the boxes they should and no collider. The whole room, shelves and all, fits the list with room to spare and one mesh. Every rack stands wholly on a counter and clear of the other racks, the sink, hood, oven, hot plate, ice bath, incinerator, filler and scale. The scale stands on the north counter clear of the rest, with an aim box that takes in its plate. The cabinet is flat against the north wall over the counter, away from the hood, with a red cross on the side toward the room. The shelves are against the south wall over the counter, clear of the filler and the loadout rack, with bottles a hand apart inside the boards, and each bottle is a coloured body, a narrower cap on top and a pale narrower label on the side toward the room, on its board. The racks face the player who stands at their counter, and the first six holes are the row nearer them. The documented numbers are pinned.

### `gear.odin`
**What it does:** What the first aid cabinet and the scale do, in package `carry`. The cabinet puts a hurt player back at full health at once and then has to rest for 30 seconds. It is ready when the player is more than half a hit point short and it is not resting, and the grab button uses it when it is aimed at, the hands are empty and it is ready. The scale weighs every vessel standing on its plate, each one that is not held, whose middle is over the plate and which is resting on it, as the glass and what is in it, with a glass weight for each kind, and shows the sum less a tare. The grab button zeroes it when it is aimed at, the hands are empty and the reading is not already zero. Taking everything off clears the tare, and taking one of several off leaves it, so that the display can read less than nothing, as a real scale does. A vessel under the crosshair is aimed at before the cabinet or the scale. `shelf_colors` gives the shelf bottles the colours of the compound table in turn.

**Decisions:**
- Every compound weighs a gram a millilitre until the pages have a density, and `compound_density` is the one place to change when they do. A vessel with a mixture weighs what all its compounds weigh. The colours of the shelf bottles are those of the compounds in turn.
- The glass weights, 60, 85, 110 and 8 g, the 30 second rest and the half hit point are first guesses.
- The cabinet gives back all the health. The slow healing of the lab is unchanged and goes on, so the cabinet is for being in a hurry.
- The reading is in grams with one decimal, which the interface shows. The scale is not a way of knowing which compound is in a vessel.
- The scale used to read only the first vessel it found on the plate, so a second one put beside it was not weighed. It adds them all now. The plate is 40 by 35 cm, so two or three vessels fit side by side. A vessel that is not resting on the plate, such as one in the air, does not count.

**Tests:** `gear_test.odin`.
**Moved stations:** The scale is where the stations of the props have it, turned as it is turned. A vessel is on the plate when it stands on the plate of a scale anywhere on the counters, and aiming at the scale is aiming at the body of any scale. With two scales the one tare is shared, and the room clears it whenever the stock or the stations change.

### `gear_test.odin`
**What it does:** The racks: every hole is over a counter, evenly spaced, and a vial is narrower than the spacing; the vials start empty, in the near row of each rack, each exactly in a hole and standing on the lower plate, and stay there when the system runs. A vial let go near a free hole is drawn into it and falls in; it is not drawn into a hole that is taken, one more than 3 cm away, or by something that is not a vial, and a vial that is held is not; two vials over one hole do not share it, and the nearer of two free holes is the one; a vial taken out of a rack by aiming at it and put back goes into the same hole, and the crosshair is on the vial it looks to be on along a full row. The scale: a vessel on the plate stands on it, 7 cm up, and is weighed with its glass for each kind; one beside the plate, held or in the air is not; several on the plate are weighed together, a held or a faraway one is left out of the sum, a stale copy past the end of the list is not on it, and zeroing takes the whole load off the display, a vessel added reads alone, taking one of two off keeps the tare and taking both off clears it; zeroing takes what is on it off the display until it is taken off, and only when aimed at with empty hands and the reading not already zero; the scale and the cabinet are aimed at within reach and a vessel under the crosshair comes first. The cabinet gives back all the health, then rests for 30 seconds, and the grab button uses it only when aimed at, with empty hands, ready. A vessel weighs its glass and its contents, and every compound weighs a gram a millilitre. The shelf bottles are coloured by the compounds in turn.

## Fixes and Problems
The moved-scale tests check that a scale weighs what is on it where it stands now, that its plate lifts vessels there and not at the old place, that it is aimed at where it stands now, and that a scale that is turned has its plate and its aim box turned.

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
- ABI version 3 added the buttons byte to the input encoder, which changes the call, so the selftest and the local host were changed with the header.
- ABI version 2 changed the throw encoder, so the selftest and the local host were updated together with the header, and the header test in `ffi_tests.rs` checks every exported function is declared.
- Odin rejects an absolute path in a foreign import ("Invalid import path"), so the Android build passes `TV_LIB` as a path relative to `client/src`.

- Nothing went wrong with the rename of the reserved byte. The selftest checks the new ABI version and size.

### `android_entry.odin`
- The first installed Android build crashed on launch. Odin's ABI lowering for 32-bit ARM returns an 8-byte float struct in registers, but the NDK uses a hidden return pointer, so the per-frame call to `GetMousePosition` made raylib write through a garbage pointer. All other raylib calls matched. Fixed with a C wrapper, and `scripts/check_android_abi.py` now guards against the same mistake. Confirmed on the device: the app runs.
- Odin's default CPU for 32-bit ARM is an ARMv6 `arm1176jzf-s`, which is why the build now passes `-microarch:cortex-a7`.
- Odin dev-2026-10 crashes inside LLVM when compiling for 32-bit ARM Android with `-o:speed` or `-o:aggressive`. `-o:minimal` and `-o:size` work. The Android build uses `-o:minimal` unless `TV_OPT` says otherwise.
- `-build-mode:executable` is rejected for the Android subtarget, and `-build-mode:shared` defines a `main` that does nothing, which would stop raylib from starting the game. Hence plain objects plus the C shim.
- Every raylib and rlgl function the 3D client calls on Android (50 of them) was compared with how clang compiles the C prototype for 32-bit ARM. 43 are identical, including `BeginMode3D`, `DrawMesh`, `UploadMesh`, `UpdateMeshBuffer`, `UnloadMesh`, and the rlgl calls that take doubles. The other 7 differ only in names for the same layout: arrays of floats versus integers of the same size, `i1` versus `i8` for a returned bool, and extra attributes on a hidden return pointer. All 7 were already in use by the working 2D build.

### `layout.odin`
- None recorded yet. The box limit was raised from 96 to 160 for the workstations.

- None recorded yet for the vial and the equipment.
- `Xform`, `turn_xz` and `counter_areas` are new, and `build` takes its five counters from `counter_areas`. Tested in `lab_test.odin`, and by the deliberate changes listed under `placed.odin`.

### `player.odin`
- A jump changes only the height of the view, and has not been tried on a phone yet.

### `lab_test.odin`
- None recorded yet.
- Four tests were added for the transform and the counters.

### `chem.odin`
- The placeholder compounds, classes and matrix were removed when the lab moved to the compound pages. The damage numbers of `hazard.odin` have not been played with the new events.

### `hazard.odin`
- All the numbers are first guesses.

### `chem_test.odin`
- The tests of the matrix and of heat on volatility were removed with what they tested. Nine of the thirteen tests went; the two on damage were kept, and two on names and hazard levels were written.

### `carry.odin`
- Props do not collide with each other, so two vessels let go at the same spot overlap. A vessel only partly over a counter edge stays up on the counter instead of tipping off.

- The first aim test of the racks failed because the crosshair, with 5 cm of pad round every vial, was on three vials at once in a row of holes 5 cm apart and took the first of them. Vials have a pad of 0.8 cm now.
- The vials first started in the first eight holes of the first rack, which put two in the row behind others, out of reach of the crosshair. They start in the near row, and the first holes are the near row.
- A vial is drawn into a hole by `vial_snap` and not at the moment it is let go, so for a frame it is where it was let go.
- `standing_height` and `settle` take the stations that stand, so that a moved scale lifts the vessels on it.

### `vessels.odin`
- The stock liquid table is a stand-in with fictional names. The compound database will replace it, and the level is only right for an upright vessel until pouring is added.

- None recorded yet for the vial and the equipment.

### `mixing.odin`
- Rewritten for the compound pages. The old rule, a table of classes with one product for each pair and a `Session` that made a whole pour one meeting, is gone. The first version of the new one let every drop of a pour start the reactions again, which warmed a vessel by 2 degrees for each drop of water poured into spirit. A test of a pour found it, and a reaction now stays done while its conditions hold (see `chemistry.odin`).
- Fumes and fire are spatters for now, because the gear the pages ask for does not exist. The event strengths (0.45, 0.4, 0.55, 0.65) are guesses.
- Tested with 58 deliberate changes, one at a time, in a copy of the carry package, with the rest of the tree beside it. The first run let eighteen through, which showed missing tests for what a reaction reports as made, for the heat it ends at, for a drop cut to the room there is, for the ice bath standing for a cold bath, for the closeness of the player to a spatter, for purity kept when a drop lands and when another is removed, for the purity of tap water, for taps past the four, for the oven's port blending purity, for a trace of an ingredient in the save file, and for a purity that truncates one too low (53 percent). Five lines were removed as doing nothing the next line did not already do: a check that a container has room, a check of a compound number before pouring it, the first-drop case of a port's purity, a limit of eight in the parser that the pour already enforces, and a mark that the flow counts. The runner is not kept in the repo.
- Not seen in the game. Whether the numbers feel right, and how the pages' reactions read when poured by hand, has not been tried on a phone.
- The first version mixed with a button press and wanted the held vessel exactly over the target, which was hard to do and never showed it was ready. It was replaced by the pour, aimed with the crosshair. A blast removes the vessel with no shards or spill.
- The rule was moved into `mix_into` so the balloon of the fill station uses the same one. The earlier tests passed unchanged, and a result now says where the reaction happened.
- A drop is judged by the station where the vessel is now, from the stations that stand.

### `health.odin`
- The knock-out rule, which resets the lab, is an assumption.

### `stream.odin`
- A drop is one compound, so a pour from a mixture is a sequence of drops of its ingredients drawn in proportion. It is made of drops of 3.4 ml, so an ingredient that is a few millilitres in a vessel pours out as one drop. Pending liquid is counted as part of the vessel until its drops are made, so the level that is drawn falls as the drops leave and not when they are queued.
- The first pours lost most of their liquid. Drops let out in the same frame were made in the same place and pushed each other apart in the simulation, and the vessel was allowed to tip so far that its lip was inside the counter. Both were found with a test that pours into a vessel and counts what arrives.
- Nothing has run on a phone yet. The drops use the liquid simulation at 3 cm cells, which the benchmark said fits.
- The first speed setting would have meant more drops, and the liquid simulation is the most expensive thing in the lab, so the drops carry more liquid instead. A drop at speed 8 is 27 ml, a big drop to look at, and how that looks has not been seen.

- None recorded yet for the vial and the equipment.
- The drops got a `seq` and the stream a mouth, so that the view can join the drops of a pour into one stream and join it to the lip. The mouth is noted by the pour, by a tap and by the oven's spout, each only while liquid comes out, and tested with deliberate changes together with `jet.odin`.
- Drops that lie still, or fall off a counter, now make puddles, so that the view does not draw them as dots. `spill_step` is not called by `stream_step`, because the room only steps the stream while drops are in the air, and puddles have to age when there are none. The room calls it every frame.

### `station.odin`
- The bottle wall has four stocked taps and six empty ones, where it had ten liquids. The empty ones are locked and grey. The six bottles above them look empty, and what the wall is for after the shop comes is not decided.
- The taps did not work for the first player to try them. They needed the held vessel within about 12 cm of the point under the nozzle, which at a normal standing place is a band of about 19 cm for the player to stand in, and the button did not light until it was pressed. A probe that stood a player at the counter and moved sideways found the band. The window is now half a metre and the stream is aimed into the vessel.
- Every tap that has a dispenser is unlocked, and nothing takes a cost for the liquid.
- Water was the first tap of the bottle wall, which is not what the design says. The wall has three taps now and the faucet of the sink has the water. The tests that took tap 0 for water, tap 2 for ethanol and tap 3 for sulfuric acid were moved to the new places. Twelve deliberate changes to the taps and the faucet were made one at a time, in a copy of the tree, and all twelve were caught: the faucet not found, not unlocked, giving the wrong liquid or not a tap, water back on the wall, the wall one tap short or its bottles coloured from the old numbers, and the faucet too low, off the basin or counted wrongly. The faucet has not been seen or used on a phone.
- The taps used to be set from the number of the chemicals the lab starts with, and the empty ones had grey bottles. They are now set from the wall (`station_init` makes the wall as the lab starts and syncs from it, and `station_colors` is its colors), so that moving a dispenser moves the tap. The empty mounts are drawn as dark plates, not grey bottles.

### `spill.odin`
- New, and not seen on a phone. Tested with 20 deliberate changes, one at a time, in a copy of the tree, and all 20 were caught in the end. One was not at first: the dissolve tests read the puddle after it had been removed, and a removed puddle's data stays in the array, so a puddle taken away too early passed. The tests now check that it is still counted. One change did not compile, because it left the math import unused, and was written again.

### `spill_test.odin`
- None recorded yet. The first drafts passed at once, which the deliberate changes then checked.

### `spill.vs`
- None recorded yet. Validated with glslang for both GLSL versions, and compiled and run on desktop OpenGL under a virtual display. The GLES 2 version has not run on a phone.

### `spill.fs`
- None recorded yet. Validated with glslang for both GLSL versions, and the desktop version drew puddles in a headless run. How it looks, the lobes, the glint and the dissolve grain, has not been seen on a screen, and the GLES 2 version has not run on a phone.

### `inventory.odin`
- New. Tested with 34 deliberate changes to it, the drag and drop controller, the wall and the soap, one at a time, in a copy of the tree. Thirty-two were caught in the end. One was not at first, a wall read from slots past its end, because no test had a dispenser in such a slot, and a test was written. Two make no difference while the dispenser is the only kind of item: the check that a container takes an item when reading text, since every item is mountable and a kind that is not an item fails the stack limit as well, and an empty slot counted as holding a dispenser, since an empty slot is of no kind. Three did not compile at first and were written again.
- Stations are items now, and `move_to` is new. Tested together with the rest.

### `inventory_test.odin`
- None recorded yet for the stations.

### `dragdrop.odin`
- New, and tested with the deliberate changes of `inventory.odin`.

### `dragdrop_test.odin`
- None recorded yet.

### `stock.odin`
- New. The look of the wall is not seen on a phone.
- Picking up stations is new, and not seen on a phone.
- The bench is gone from `Stock`. Stations stand in `Props.placed`, and a file from before is read by `placed_from_bench_file`, which keeps each station at the middle of its old spot. That reading is tested with files that the earlier version wrote, and has not been tried on the owner's own file.
- A station with a vessel on it cannot be picked up. Without that the vessel would drop to the counter inside the footprint of the station that is carried, and the station could not be put back where it was.
- Picking up stations into the bag, which the bench delivery did, is replaced: a station that is picked up is carried as a copy, and goes into the bag only by cancelling when its old place is not free.

### `stock_test.odin`
- The first drafts of the aim tests looked at the stations from 30 cm over the counter, which is above the box of the hot plate, and found nothing. The view is at 4 cm.
- The tests of the bench were replaced by the tests of the stations. Two of the new ones were weak the first time: a vessel at floor level inside a plate, and two stations in one line of sight, were not tried until a deliberate change got past the tests.

### `blueprint.odin`
- New, and not seen on a phone. Tested with 59 deliberate changes to it and to what reads the stations (the pick up, the bag, the turns, the vessel check, each problem, the aim and its limits, place and cancel, the kind each reader looks for, the heat, the plate height, the scale and what a drop sees), one at a time, in a copy of the tree. 51 were caught at once. Six were not and showed weak tests: a crosshair at exactly the height of the counters, a counter further than the limit that the plane is looked for, a direction that is not a unit length, a copy that has a kind and a good flag and is not carried (the first version of that test stood on a place that was taken, so it passed for the wrong reason, which the second run showed), a vessel at floor level in a plate, and two stations in one line of sight (the first test had them in opposite directions and could not tell which was nearer). Each now has a test and is caught. One more did not compile and was written again.
- One change is an equivalent mutant and is kept: dropping the check that a station came from a counter before it is put back there. A station from the bag has no place, and a place for a station of no kind is always refused, so the result is the same. The check says what is meant, and is left.
- Two conditions that no change could matter to were found by the same runs and removed: the count of a slot in `blueprint_take_from_bag` (an empty slot holds no station) and in `placed_from_bench_file`.

### `blueprint_test.odin`
- The first run found a test helper with the name of one in `carry_test.odin`, which was renamed, and a loop whose limit was worked out from a count that the loop changes, so it stopped short. The limit is worked out first.

### `stock_ui.odin`
- New, and not seen on a phone or a screen. The layout and the drags are checked by `selftest_stock` (every slot and the close button on the screen, inside the panel, at least 44 pixels across and not on one another, on six screen shapes; picking up, carrying, dropping, not swapping, cancelling, locked containers and the taps following the wall). How it looks and how a drag feels under a thumb are for the owner to judge. A drag is one finger and the screen has no scrolling. Eight deliberate changes to it were each built and run through the self-test, in a copy of the tree, and all eight were caught: a drag starting on an empty slot, dropping without letting go, every slot taking everything, the target container misread, columns overlapping, the bag out of reach of the pointer, tiles too big, and a locked container that could be dragged from.
- The row of the bench was taken out when stations became movable on the counters, and the screen is two grids again, with larger tiles. A tap on a station of the bag carries it. `selftest_stock` has the taps in place of the drags along the bench, and 9 deliberate changes to the tap, the slot it began on, the container, the hands and the layout were all caught in the end. Three got past the first checks and showed weak ones: a tap on a mount of the wall (the bag had to hold a station under the same number), a release over no slot when the drag began on slot 0, and a flag that could not be false where it was read, which was removed.

### `blueprint_view.odin`
- New, and not seen on a phone. A headless run under a virtual display, with a copy of the room that scripted the buttons, carried a station and compared the picture with a run that did not (counting the pixels that changed and which way their colors went, without looking at the pictures): while the copy could be put down the colors shifted toward blue-green, and where it could not (aimed at the sink, with a bath that is wider than the counter) toward red. How it looks on the screen of the A13, how thick the edges are at a distance, and what it costs a frame are not known.
- The first plan was `DrawCubeV` and `DrawCubeWiresV` from raylib, which take structs of floats by value. The lab already avoids that (see `scene_lab.odin`), so the box is drawn with `rlgl` vertices.

### `stock_file.odin`
- New. The file has not been written or read on a phone.
- The placing of stations is new in this file, and the file has not been written or read on a phone. The reading of a file from before and of damaged lines is tested in `lab` and `carry`, and a headless run wrote the file after a station was put down and after one was put back, with the places that were expected.

### `sink.odin`
- New, and not seen on a phone. The soap bottle's place beside the basin and its size are a first guess.

### `sink_test.odin`
- None recorded yet.

### `placed.odin`
- New, and not seen on a phone. Tested with 76 deliberate changes to it and to `layout.odin`, one at a time, in a copy of the tree: the size of each plate, body and height, the turn of a rectangle and of a point, the transform with its swap of width and depth, the keep-out of each fixture, the zones, touching and overlapping, snapping and the grid, fitting (the reach past an edge, each clamp, a counter too narrow, the turn), every limit of reading a line of the file, the limit of eight, taking a station away without moving the rest or leaving a stale slot, the starting places and the display on the back. All 76 were caught in the end. Two did not compile at first, because the change left a name unused, and were written again.
- The first drafts of three tests had wrong sums, not wrong code: a plate may stand 4.7 m from the middle of the island and not 4.69, a bath at 0.5 m from the middle of the island sticks over its edge, and the grid rounds -11.63 to -11.60. The tests were corrected.

### `placed_test.odin`
- The test of every box of the fixtures against the keep-outs is the one that would find a fixture that was moved or forgotten. It found none in the lab as it stands.
- The box count of the lab with the starting stations is 14 more than without them: the hot plate 2, the bath 8 and the scale 4. The bare spots of the old bench are not built any more, three boxes fewer.

### `jet.odin`
- New, and not seen on a phone or a screen. How the stream looks, its width, its shading and the highlight along it, is for the owner to judge. A throwaway build that made a scripted jet in front of the player drew it without a crash at 1600 by 720 and changed thousands of pixels against a control, which shows only that something was drawn.
- Tested with 30 deliberate changes, one at a time, in a copy of the tree. Twenty-nine were caught in the end. Four were not at first: the faster of two drops setting the reach, which a test had put exactly on both limits; the free end being drawn thinner, which a comparison passed by rounding; the last stretch of a jet leaning on a drop that is not there; and the oldest end. The tests were tightened for each. The thirtieth, taking away the guard against drops on top of each other, makes no difference, because the clamp on the width gives the same answer.

### `jet_test.odin`
- The first drafts of the tests made drops at 1.0 m, which is under the top of the island in the middle of the lab, so none could be made. They are made 0.6 m higher.

### `stream_view.odin`
- The owner looked at the jets and said the pouring was much better but the spill was all dots. Drops lying on a surface were still drawn as diamonds. They are now puddles that spread, join and dissolve, and the spray is round beads. Not seen on a phone. A throwaway headless build with a scripted spill showed the puddle land in view, stay for about four seconds and be gone about nine seconds after it landed, by counting changed pixels against a control. The first run showed nothing, for two reasons that were mine: the scripted spill landed below the bottom of the picture, and the puddles never aged, because the room only steps the stream while drops are in the air. The room now steps the spill every frame.
- The diamonds were replaced by the jets after the owner said the pouring looked bad and the liquid sitting in vessels did not. Not seen on a phone or a screen: the shading numbers (0.55 and 0.45 for the light, 24 and 0.6 for the highlight, 3 and 0.3 for the edges, 225 of 255 for how solid it is) are first guesses.
- The frame cost of the tube has not been measured on a phone. It is at most 7000 vertices and no allocation, and the simulation has not changed.

### `menu_ui.odin`
- The matrix of ten liquids is now a list of reactions. It was rewritten without being seen: only the size of the text and the fit of 11 rows were reasoned about, and a row's text may be too long for a narrow phone screen, which `draw_text_fit` shrinks.
- The list of 11 reactions was replaced by the book after the owner said that each compound should have its own reaction page, and that he meant the page in the game. The first reading was of the data files, where a reaction is written once on the page of its first input, which gives the water page six of the 11 reactions. That reading was wrong, and the menu was not looked at until he said so.
- Not seen on a screen or a phone. The layout and the turning of pages are checked by `selftest_book`: every button and tile on the screen, inside the panel and not on another, on six screen shapes. How the text fits is reasoned and not looked at: `draw_text_left` shrinks text down to 10 pixels and then lets it run on, and the longest line, the four-way mix with the purity bands of its inputs, was not measured.
- A first design gave each kind of line a heading row, which would have put water's 13 lines and its headings on one spread with room for fewer. The kind is now a tag on each line, and a spread holds eight.
- A first `page_of` knew only reactions, and left seven of the 17 compounds with an empty page, because they are made only by electrolysis. Electrolysis was added to the lookup, and a test now requires that every compound has a page.

### `shapes.odin`
- The vessels were opaque pastel solids at first. They are now see-through glass with liquid, as asked after the first test on the phone.

- None recorded yet for the vial and the equipment.

### `mpm.odin`
- On a desktop, the version with the active block and the unrolled loops is 2.3 times faster per particle than the first, and the grid cost is gone. Only a box of liquid so far: no walls thinner than a cell, no cohesion, and no coupling to the vessels. None of it has run on a phone yet, and the cost there is what the sim test is for.

### `scenario.odin`
- None recorded yet.

### `mpm_test.odin`
- The first version of the tests did not notice a wrong affine matrix scale. Checking it by changing the scale on purpose showed that, and the spin test was added, which does fail.

### `hands.odin`
- The pose numbers were set from the geometry and have not been seen on a screen or a device. Expect to tune the wrist spots and the curl angles after the first look on the phone.

### `carry_test.odin`
- Several tests of the old matrix (acid and base making foam, the oxidizer and the oil, a spatter at a drop of the base) were rewritten for water and spirit, water into acid and the hot four, because the pairs they used are not on the pages. The hot four are put in a vessel directly rather than reached by pouring, because pouring gives the pair reactions their turn first.
- None recorded yet.

- Two checks of the old tests were widened for the vials: the count of vessels, and the range a capacity can be in.

### `scene_bench.odin`
- First phone run, built with `-o:minimal` on a Galaxy A13: 10.1 us for each particle and 3.0 ms for the grid, each step, so a 125 ml splash cost 736 ms a frame at 1 cm cells, 46 ms at 2 cm, and 9 ms at 3 cm. That led to the grid being limited to the block in use. The estimate rows assume the grid cost falls with the cube of the cell size. A run built with `TV_OPT=size` has not been seen yet.

### `mpm_bench.odin`
- None recorded yet.

### `prop_mesh.odin`
- The glass is blended without writing depth and sorted by the distance to the base of each vessel, which is right for vessels standing apart and may be wrong for vessels touching. A hand can poke into a counter when the player looks steeply down close to it, because the hands are depth tested with the room.

### `interact_ui.odin`
- The grab button was hard to see over the light counter tops. It now has a dark backing and the counter tops are dark teal.

- None recorded yet for the equipment buttons.
- The pick up readout and the line about the carried station are new and not seen on a phone.

### `lab_mesh.odin`
- None recorded yet.

### `input.odin`
- The controls were rewritten on the `touch` package after the owner pointed at Tower-Of-Babylon and said aiming and movement needed work. Reading its notes and code showed three differences from this file: the old code kept only one button finger, so pressing jump while holding the throw button took the throw away, a second finger on the left half became a second look finger, and the ring was 14 percent of the shorter side with no dead zone. These are changed. Nothing has been tried on a phone.
- Odin accepts `&&=` and shifts of a `u32` by 32 or more give zero, which is why a button numbered 32 or more is held but never reported. No scene has that many buttons.
- The controls took one button box and now take a list. The scene-switch button is index 0 and the grab button is index 1 in the lab room.
- Tapping the button in the balloon scene loaded the lab room and then immediately returned to the balloon scene. The finger was still down when the room started, the room's controls had not seen it before, and it sat on the same corner where the room draws its own button, so it counted as a new press. The controls now start knowing which fingers are already down.

### `scene_room.odin`
- The toasts say what was made, `mixed` when nothing was made, and, for a spatter, what went wrong: a splash, fumes, a fire, or that water went into the acid. The heat events are shown by `room_heat_events`. None of it has been seen.
- The burn was checked by counting pixels in a headless run, with a control that looked the other way. Looking at the incinerator, with the burn forced at frame 40 by the same procedure the grab button uses: the balloon was gone from the hand, the picture changed over most of the screen at the flash and kept changing for as long as the smoke rose, and looking away it changed by a few hundred pixels at most. How it looks and sounds on a phone has not been seen. There is no sound.
- The arena button is the eighth button of the lab, and a press of it is index 7. Only the button list and the handler changed.
- The room has the bag and the wall: the bag button (index 8 of the lab's buttons), the screen with its drag, and `room_stock_changed`, which syncs the taps, builds the lab again with `room_build_layout`, makes the mesh again and saves. The lab is built from the wall as it is, so loading it builds the same way. The soap is aimed at with the crosshair, washes hands with the grab button and says so with a toast. Not seen on a phone.
- The room loads the shader of puddles and beads, steps the puddles every frame in real time, even with no drops in the air, and passes the camera view to the stream's drawing. Not seen on a phone.
- The reactions menu became the book: the room keeps the page it is open at, the press goes to `book_press`, and the arrows turn pages on a desktop. The button list is the same size, and the old matrix button is now the book button at the same place. Not seen on a phone.
- A first check that forced blasts, oven runs, and balloons into the scene put the forcing in the loading code and not the update, because the two have the same lines, so it never ran those paths. It was redone in the update, with a control run that had no drawing and no blasts: that had no red pixels on the screen where the run with the drawing had tens of thousands.
- The carrying, hands, crosshair, and grab button were written and compile for desktop and Android, but have not been seen running on a phone yet.
- The effects, the fill station, the hood, and the sink compile for desktop and for Android with `-o:minimal` and `-o:size`, and the ABI check passes, but none of it has been seen running on a phone.

- The cabinet and the scale have not been used with a thumb on a phone, and the readout lines have not been seen there. The frame rate with 47 vessels in the room, where there were 23, has not been measured.
- Picking up and placing stations is new and not seen on a phone. The spot a station goes to is chosen on the bag screen.
- The placing of stations was run headless under a virtual display, with a copy of the room that scripted the buttons: picking up and showing the copy, showing it where it cannot be put down, putting it down, and putting it back. Against a run that did nothing, the picture of a put back station differed only in the line of text at the top, the picture of a copy that could be put down shifted toward blue-green and one that could not toward red, and the file that was written had the station at its new place after it was put down and at its old place when the game ended while it was carried. None of it has been seen on a phone, and how it feels to aim a station with a thumb is for the owner to say.
- A knock-out puts the vessels back at their starting places even where a station now stands. That is not handled.
- The code that picks up, places and cancels in the room is covered by that headless run and not by tests: it is a few calls into `blueprint.odin`, which is tested.

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
- `selftest_book` was tested with 12 deliberate changes to `menu_ui.odin`, one at a time, in a copy of the tree, each built and run: the next and back buttons not stopping at the ends, the contents button doing nothing, the tiles being live on every page, the first page counting its own compound, the spreads not rounded up, tile columns, tile rows and bar buttons overlapping, the next button being the back button, the second spread of a compound being the first, and the close button moved off the panel. All 12 were caught. The numbers it pins (19 pages, the first pages of four compounds) are the pages as they are and change with them.
- The three-bot check and the host were tested with seven deliberate changes, one at a time, in a copy of the tree, each built and run: the host not counting its bots, only the first bot playing, every bot sharing one set of random numbers, every bot sharing an id, a cap of two bots, bots sending as the local player, and the scene starting one bot. Six were caught at once. The seventh, the scene's bot count, got through because the check started its own match with a literal 3, so the check now starts its match with the scene's constant and pins that constant at 3. A change to five bots is caught too. The runner is not kept in the repo.
- The bounds of the three-bot check (three throws a bot, six bursts, 8 m between spawn points) are guesses from the design and not measured limits: each check passed on its first run, and the number of throws and bursts the seed gives was not looked at.
- The projection check of the drawing screen failed on its first run, on a screen of 800 by 600, and was right: see `paint_layout.odin`. It prints the screen it fails on, and by how much.
- The first match through the local host passed checks that deliberate changes then showed were weak: a speed ten times too large still passed a test that asked only for the balloon to be going the right way, and only player 0 was ever played, so a wrong owner or spawn heading was invisible. The checks are tighter and a second match is played as player 3.

- The earlier bot checks named a constant that the new bot no longer has, and counted exactly two bursts in eleven seconds, which were true of a bot that threw on a clock. They were replaced by checks that fit a bot that plays: forty seconds, a player who stands still, at least eight throws.
- The first layout of the arena buttons put the hit point bar over the slot squares at 1280 by 720. It was found by working out the boxes by hand and the check was written after, so it would find the next one.
- Deliberate changes to the host and to the layout were made one at a time, with the selftest as the judge. Two got through the first selftest: the bot's power ignored, because a bot with weak balloons walks up close and hurts the player anyway, and the bot not seeded for each match. Checks for both were added and the changes now fail them.
- Nothing here has been seen on a phone.
- The checks of the bench were replaced by the checks of the taps. There are still 142 checks, and the hash of the state is the same as before.

### `softbody_bench.odin`
- None recorded yet.

### `balloon_test.odin`
- The first zero-gravity test expected the balloon to be perfectly still after one second. It is still easing back from its pre-stretched rest shape, and turns very slowly. The test now allows a small speed and drift after two seconds.
- The full suite took 26 seconds in an unoptimized build with every combination in the parameter sweep. The sweep was trimmed to 24 combinations that still cover each mesh size, substep count, step size, and fill range, and the faster solver loops cut the rest.

### `effects.odin`
- None recorded yet. The size, count, and timing of every part are first guesses. Nothing has been seen on a phone.
- A pop at the size of the lab is a few centimetres across, and from 20 m away in the arena it was too small to see. `pop_scaled` was added, and the first checks of it with deliberate changes found that the growth of the mist and the distance the drops start from were not tested, so the tests now check each part.

### `effects_test.odin`
- The first test of the full pool could not tell the particle nearest its end from any other. Changing the code to replace a fixed one, and then to replace the youngest, still passed. The test now marks one particle nearest its end and one young one, and checks which is replaced.
- The first run of the check that changes the code on purpose used a script with its arguments shifted, so no change was applied and every run counted as a pass. It was redone with a check that the change was applied, and then every change made a test fail.

### `effects_view.odin`
- None recorded yet. Not seen on a phone: how the blended and added particles look together, how large they are on a small screen, and whether the room hides them as it should.

### `apparatus.odin`
- The cradle under the balloon of the paint station cut into the balloon, which the owner saw as the clamp clipping through it. It had been placed 1 cm under a balloon taken to be 15 cm long, which is how far the soft body reaches the moment it is made. Once it has sagged it reaches 17.6 to 19.2 cm. A test now settles the real soft body at four fills and checks the clearance, and it caught the first fix as well: 0.19 was less than the 0.192 m of the slackest balloon, so `PAINT_DROP` is 0.20.
- The incinerator has been checked by counting pixels in a headless run of the lab scene, standing in front of it: 8910 orange pixels looking at it and 374 looking away. Its look and where it stands have not been seen on a phone.
- None recorded yet. Nothing has been seen on a phone. The distance from the player's usual place to the funnel and to the sink was worked out from the hold point and not tried by hand.
- The faucet is new: it stands 42 cm over the counter, over the middle of the basin, so that a flask fits under it and the tip is within reach. Where it stands and how it looks have not been seen on a phone.

- None recorded yet for the vial and the equipment.
- The hot plate and the ice bath are not built here any more. See `placed.odin`.

### `apparatus_test.odin`
- The first test of the incinerator counted its boxes as 14, and it has 12. The test was wrong. The test of the cradle settles the soft body for ten seconds at each of four fills, which takes about a second, and has to repeat the mesh detail and substeps of the station, which the main package owns, so a change there has to be made here by hand too.
- None recorded yet.

### `filler.odin`
- The balloon holds a mixture and a temperature in degrees. The pour session is gone.
- None recorded yet. The limit of 1.35, the two second wait for a new balloon, and the 1000 ml rest volume are assumptions to tune by playing. A filled balloon cannot be taken off the clamp yet.

### `workstation.odin`
- None recorded yet. The fifth that gets out of the hood is a first guess.

### `stations_test.odin`
- The balloon tests that used the oxidizer and the oil use water into acid for a spatter and the hot four for a burst. A shared `burst_mix` makes the hot four.
- The full pour into the funnel passed the first time it ran, which is a reason to doubt it. Turning off the aim at the funnel made it fail, so it does check the aim.
- The first run of the change-on-purpose check applied nothing, as in `effects_test.odin`, and was redone. All twelve changes made at least one test fail.

### `filler_view.odin`
- None recorded yet. Not seen on a phone: the scale of the balloon, how it hangs, how limp it looks empty, how it swells, and what its soft body costs on the old phone. If it is too slow, the mesh detail and the substeps at the top of the file are the first things to lower.
- A balloon in the hand kept the orientation it had in the world, so its drawing showed only when the player was looking from the side it was made for, and not otherwise. It is now turned to face the player, and the balloons on the hooks to face north.

### `oven.odin`
- The ports keep their purity and the tank is a mixture. A run pours the ports in order into one mixture and lets it react at the oven station after each. No reaction on the pages asks for the oven, so a run only does what works anywhere. The oven has no temperature of its own yet.
- None recorded yet. The run time, the sizes of the ports and the tank, and the order in which the ports are mixed are first guesses to tune by playing. A liquid in a port cannot be taken out except by a run.

### `oven_test.odin`
- The oven tests use water and sulfuric acid in the right order and the wrong order, and a `port` helper to fill the ports with a purity.
- The spout was first on the front of the oven, flush with the edge of the counter, so no vessel could stand under it, and nothing showed that there was product to pour. It worked when a vessel was held right at it, which a test and a run of the real scene both showed, so the fault was in how it was built, and it was moved to the right end over free counter with a tray, a light, and a hint on the screen.
- A first test put drops over all four ports at once and found ports 3 and 4 empty. The simulation box is set by the first drop and is a metre and a third wide, which does not hold the whole oven, so a drop outside it is refused. The test now does one port at a time. A pour from a vessel stays near one port, so the game does not meet this.
- The first test of the speed let out no drop in its first frame, because a drop of eight times the size takes two frames of flow to gather. The test now runs two frames before it looks.
- All nineteen deliberate changes to the oven, taps, and speed made at least one test fail.

### `oven_view.odin`
- None recorded yet. The lights have not been seen on a phone.

### `heat.odin`
- Rewritten in degrees. The old scale, -1 to 1 with a fifth of a unit a second, is gone, and `heat_unit` keeps it for the words and the steam. The plate reaches 160 in 23 seconds, which is slow enough to stop at a window of the pages and which nobody has tried. A vessel that reacts while it heats is reported as an event, which is new.
- There is no thermometer except the number in the readout under the crosshair.
- None recorded yet. The rates are first guesses, and the plate is always on. Nothing has been seen on a phone, including the steam.
- The hot plate and the ice bath were fixed places, and are where the stations stand. The starting stations are the old places, so the tests that use them are as they were.

### `heat_test.odin`
- Rewritten for degrees. Two of its tests set a vessel to just under a limit and mark a reaction as already run, as if it had been held there, to reach a spatter and a burst by heating, because a vessel heated up from the room would have reacted at the first window it passed.
- The first run of the change-on-purpose check found four gaps in the tests. Changing where a word for the temperature starts, leaving the temperature out of what a drop brings into a vessel, leaving it out of what the funnel takes, and leaving it in a burst balloon, all still passed. Tests for each were added.
- None recorded yet for the moved stations.

### `loadout.odin`
- A balloon in the hand, the clamp and on the hooks carries the whole mixture. `loadout_presets` has the whole mixture, but the wire still takes one compound and an amount, so a throw sends the compound there is most of with the whole volume. A balloon of spirit with a little water in it is thrown as spirit. Sending the mixture is the next step, and it changes the protocol and the C ABI.
- None recorded yet. The drawing is one per balloon by assumption, and nothing is saved or sent anywhere yet. The knot is not shown on a tied balloon.

### `loadout_test.odin`
- The balloon helper builds a mixture and the tests check that the whole mixture goes into the presets, not only the main part.
- Every deliberate change to the heat and loadout code made at least one test fail, after the four gaps in the tests were closed.

### `art.odin`
- The first version of `canvas_dab` had code for a dab over the seam that did nothing the rest did not already do, and the change-on-purpose check showed it, because taking it out failed no test. It was taken out.
- Every other deliberate change to the drawing code made at least one test fail.

### `art_test.odin`
- The test of what is outside the canvas first expected less than half of each dab to be left at the edge, and a dab one pixel from the top keeps a little more than half, so it was wrong and not the code.

### `paint_layout.odin`
- The mirrored layout passed its own tests. The self-test that projects the balloon through the camera then found that on a screen of 4 by 3 the balloon is wider than the area left for it. The old layout did the same, and it was never noticed because a phone is twice as wide as it is high. The tablet now gives way on such a screen.
- None recorded yet. The sizes are first guesses, and nothing has been seen on a phone.

### `paint_layout_test.odin`
- A check with deliberate changes found that the tests let a balloon area touch the panel and the palette touch the tablet, because touching rectangles do not overlap. They now ask for a gap. It also found that no test screen ever made the tablet reach its smallest width, so one that is square was added.
- See above: the first run found a real mistake, the brushes under the middle of the tablet.

### `art_view.odin`
- None recorded yet. The cost of sending a rectangle of the drawing on the old phone is not measured.

### `paint_view.odin`
- Nothing checked the height of the camera until the projection test was written. A camera at the height of the clamp put the bottom of the balloon off the screen, and the test now fails for it.
- None recorded yet. The camera numbers, the size of the swatches, the speed of turning, and how it feels with a thumb have not been tried.

### `art_view.odin`
- A balloon in the hand showed the old drawing after the drawing had been changed in the clamp. Each balloon had its own texture and all of them took the same rectangle of what had changed, so whichever updated first left the others with nothing to update from. It was found by running the real flow, a drawing taken from the clamp to the hand, back, changed, and taken again, and counting the colors on the screen. A texture now takes the rectangle only if it has everything before it.

### `art_codec.odin`
- None recorded yet. The palette of the bytes is not read, so a drawing made with another palette would come back with the lab's colors.

### `art_codec_test.odin`
- The first vectors were made by the Rust code with a made-up palette, and the pixel data matched but the palette bytes did not, because the encoder writes the palette of the lab. The vectors were made again with the palette of the lab. The change-on-purpose check found four gaps in these tests and the save tests: a run of nothing that the rest makes up for, the mark that a decoded drawing changed, the header check, and the rounding of the amount. Each has a test now.

### `loadout_save.odin`
- The format changed to version 2. A balloon's line has a list of `number:millilitres:purity`, and an old file is not read, which loses the balloons of anyone who had saved some under the first version. There are no such players yet.
- None recorded yet. The file is read once, when the game starts, and written on changes. A round trip was run on the real client twice: the first run wrote a balloon with a drawing and the second read it back with the same pixels.

### `loadout_save_test.odin`
- Rewritten for version 2, with a mixture, a purity, a trace and a list of bad lines for the ingredient list.
- None recorded yet.

### `loadout_file.odin`
- None recorded yet. Not tried on the phone, where the file is in the private storage of the game. Writing a file of a few hundred kilobytes at the worst, with five drawings, has not been timed on the old phone.

### `arena.odin`
- `Slot` has the whole mixture and the two fields the wire needs. The practice balloon is 300 ml of tap water.
- `fire_push`, `fire_turn` and their three constants were taken out, with their three tests, when the throw pad began to turn the view by how far its finger moves. The arena tests went from 74 to 71.
- The jump is a button held and not a separate command. The first test of the hash in the simulation could not tell the height from the buttons, and a check with deliberate changes found the vertical speed was redundant there, see `world.rs` in the simulation's notes.
- The first test of the throw button could not tell a release of an empty slot from a release of a full one: changing the check to always throw still passed, because the slot never changed while charging. A test now takes the balloon away mid-charge and checks nothing is thrown and no cooldown starts.
- A check with deliberate changes, 36 of them, found one more weak spot: a charge let go after the balloon had gone from its slot still threw, and no test noticed. The test above covers it. A change to the power range first did not compile because it left a variable unused, and a change that does not compile is not a result, so it was made again.
- Nothing here has been tried on a phone: how long 1.2 s of holding feels, whether 0.5 s between throws is too slow, and whether 6 to 18 m/s is the right range are all first guesses.

- The zero value of a player's hit points is knocked out, so a test that built a player with no `hp` would have a bot that ignores him. The bot tests build players through a helper that sets it.
- The fire stick was first considered as a drag on the whole screen that fires on release. A round stick was built instead, because the owner asked for the kind used to move the camera, and its rates are guesses.

- The first fire stick was too sensitive to aim with, and turned only when dragged all the way out. Its middle was the middle of the button, so a thumb that landed off-centre began with a push already, and its response was a square after a dead zone of 0.15, so small pushes did almost nothing while the edge turned at 150 degrees a second. It now floats with the thumb, answers in a straight line, and tops out at 1.8 and 1.2 rad/s. How it feels has not been tried.

### `arena_test.odin`
- None recorded yet.

- None recorded yet.

### `coliseum.odin`
- The first door and pillars stood 0.03 m inside the line of the arena wall, and the test that nothing stands on the sand failed. They now stand 0.08 m out, a limit the test knows about, and a door flush with the wall would have drawn the same face twice. The look of the building has not been seen, only measured.

### `coliseum_test.odin`
- Two of the first tests were wrong and not the code. One asked for every box to be above the floor when the slab of sand has its top at the floor, and one expected two turns of a box to give different distances when they happen to give the same one. Both were rewritten with answers worked out by hand.
- A check with deliberate changes found that the size of the ledge could change from half a metre of depth to three without a test failing, because the test only asked for the building to be under 33 m. It now asks for between 31.0 and 31.2 m.

### `host_local.odin`
- The slot of a balloon holds its mixture and the throw sends the main compound and the whole volume. See `loadout.odin`.
- The three-bot match was run for thirty seconds in the selftest with one seed only. Whether it holds up over longer matches, other seeds and a player who moves has not been tried.
- The host held one bot in three fields. It now holds up to `MAX_BOTS` of them, each with an id and its own random numbers, and the arena starts three. The first bot's numbers are the same as before, so the single-bot selftest is unchanged. Bots go for the nearest standing player, so the bots throw at each other too, which nothing asked for either way. How three bots feel to play against has not been tried.
- The first self-test checked that the player stands on the spawn point with an exact comparison of floats, which failed on the last digit after converting millimetres to metres. It compares within a millimetre now.
- A check of a heading sent to the match failed the first time because the view is drawn between the last two ticks, so it is one tick behind the world. The test steps one more tick, and the delay is written in `arena.odin`.
- A check with deliberate changes found that seven of the conversions were not seen by the first self-test: the owner, the speed, the heading both ways, the power, and the balloon and place of a burst. The test now starts a second match as another player, fires two balloons, and compares the speed and the place a balloon burst against where it was last seen. The volatility of a burst is still not checked, because the simulation says zero for everything until the compound database is shared.

- The bot's wiring was checked by the selftest, which now plays forty seconds with it against a player who stands still, and by a throw with the bot's own aim through the real world, which has to take exactly 20 hit points off.

### `arena_view.odin`
- A pixel check of the drawing of the arena counted the colours that differ between a run and a control. The balloon in the hand differed from nothing by about 13000 pixels, the balloon in flight by about 4800 when near and a hundred when across the sand, and nothing differed before the balloon was thrown. With a saturated drawing on slot 0, the purple pixels were 7700 on the balloon in the hand and a further 2300 on the one in flight, and none without the drawing.
- The look of the balloons, how large three times life size is on a phone, and the cost of five soft bodies in this scene have not been seen or timed on a phone.

### `arena_ui.odin`
- The first slot square formatted its number and amount with `ctprintf`, which allocates from the temporary allocator, and the client avoids allocating each frame on Android. They are formatted into buffers on the stack.
- The layout of the three squares beside the throw button was worked out and not tried with a thumb.

- The slot squares were first made as tall as the fire stick, which is 172 px on a screen 720 px high and 240 px on one 1000 by 1000, and that pushed them off the screen on the square one. They are 0.55 of the box's width now, and the layout check covers six screen shapes.
- The fire stick, the ring and the bar of hit points were drawn once in a headless run and counted against controls: 2231 gold pixels of the charge ring against none without it, and 190 pixels more of the bar's green with the bar of another player on than off. How they look on a phone has not been seen.

### `scene_arena.odin`
- The buttons are now found by named numbers (`THROW_BUTTON` and the others) and not by bare numbers, because the list the scene gives the controls is in a fixed order and a mistaken number would press the wrong button.
- The throw pad did not work together with the jump button in the first version, see `input.odin`. How aiming with the pad feels has not been tried.
- The first headless run of the scene only showed that it starts. A check was written that throws one balloon at a frame it picks, in the update and not in the loading code, with a control that draws the same frame without the balloons, the hand, and the effects: the burst at about 19 m from the player was 18 pixels when drawn as a lab pop, and from about 190 to over 1300 pixels when drawn at four times the size. That is why `pop_scaled` exists.
- A balloon that bursts is seen. Whether it is seen well enough on a phone, how the coliseum looks, whether the controls feel right, and the frame rate have not been checked on a phone.
- The view is drawn a tick behind the world, 17 ms. How that feels on a phone is not known.

- The controls have not been tried with a thumb. The dead zone and the turn rates are guesses.

- The fire stick takes its middle from where the finger lands, which is taken from the frame on which the button was pressed. Dragging the finger before that frame is not possible.

### `arena.fs`
- None recorded yet. Both versions pass `glslangValidator` and the desktop one compiled and ran on a software OpenGL context in a headless test, and neither has been seen on a device.

### `character.odin`
- The first ellipsoid was wound the wrong way round: worked out from where a viewer stands, the next slice is to the left, and the first guess had the faces inside out. The test that sums the signed volume of each shape is what shows it, and it passed once the winding was corrected. A check with deliberate changes then turned each face of the box, the cylinder, and the ellipsoid inside out and the tests caught every one.

### `model.odin`
- Three of the first tests were wrong and not the model: a limit of 600 triangles that I made up, which the character is over at 668 and is nowhere near a problem for a phone, the height of the quiff, which is 1.94 m and not the 1.9 m written down first, and a test that asked for something behind the body when everything is in front. The height and the limit were changed to what is true.
- The character has not been seen by the owner. A pixel check counted what the character adds to the picture against a control that leaves it out: 1300 to 2100 pixels at about 11 m, which is about what a figure 1.9 m tall covers at that distance. How it looks has not been seen on a phone, and the proportions are from the sketches and a reading of the renders.

### `pose.odin`
- None recorded yet. The swing, the bob, and the throw are first guesses.

### `bot.odin`
- The first tests of the wander and of the radius let two changes through: with the wander taken out, or with the bot steered toward the middle all the time, the bot still stayed on the sand. Tests now check the heading's drift over a quarter and a whole period, and that a bot inside its radius keeps its heading.
- The test of the wander first unwrapped an angle wrongly and failed on code that was right.

- The first tests of the new bot had three mistakes of their own and none of the bot: a test case that asked for 25 m at 7 m/s, which cannot be reached, a check of the stick that forgot to give the input its heading, and a check of the random seed that forgot that making the bot had already drawn from it. The code was right each time.
- The bot's own estimate of the target's up and down speed was set to zero and never used. A deliberate change that left it out changed nothing, so the line was taken out.
- Deliberate changes were made to the bot and the fire stick maths, one at a time, in a copy of the tree, and the tests were run on each. What survived at first was fixed by a test or by taking out redundant code. The runner is not kept in the repo.
- At 10.7 m from a standing player, with the selftest's seed, it threw twelve balloons in forty seconds and knocked the player out once. How it feels to a player who moves has not been tried.

### `host_local.odin`
- The bot's wiring was checked by deliberate changes to the host, one at a time, with the selftest, which plays eleven seconds with it.

### `character_view.odin`
- None recorded yet.

- None recorded yet. The bars are drawn in the world and not on the screen, so they need no projection, which the Android build of raylib cannot return as a float struct.

### `equipment.odin`
- The shelf boards were first put 2 cm off the wall. A test that the boards are flat against it found that, and `SHELF_Z` was moved.
- The check with deliberate changes moved a rack to the wrong side of the counter, turned the rows round, moved the scale's plate onto the oven and put the cabinet on the hood. Two got through at first, because the tests used the racks' own facing in their own check and measured the plate with a rectangle that the change had turned inside out, so the facing and the size of the plate are now pinned by numbers.
- Nothing about the look has been seen on a phone. In a headless run, each piece changed the picture against a copy of the room without it: 4035 pixels for the cabinet, 4616 for the racks, 54507 for the shelves, 7350 for the scale, and 1384 red pixels for the cross against none.
- The scale is not built here any more. See `placed.odin`.

### `equipment_test.odin`
- None recorded yet.

### `gear.odin`
- A check of whether the vessel was on the scale before the reading was asked for turned out to be redundant: an empty plate reads zero and zero cannot be zeroed. It was taken out.
- Deliberate changes were made to the cabinet and the scale one at a time, in a copy of the tree: 52 in all with those of the racks. The survivors at first were an aim test that never put a vessel under the crosshair at the cabinet, and the pieces named under `equipment.odin`. Each was fixed by a test or by taking out the code.
- The scale's density is a stand-in, and so is the weight of the glass. Nothing has been tried by a player.
- The scale weighed only the first vessel on the plate. It now weighs all of them, and the tare is the whole load when it is zeroed. Ten deliberate changes were made to it, one at a time, in a copy of the tree: nine were caught at once, and the tenth, letting the slot just past the end of the list count as a vessel, was not, because the slot beside it was empty in the test. A vessel taken out of the list leaves a stale copy of the last one in that slot, so a test now removes one with two on the plate, and the change is caught. Not tried on a phone.
- The scale was at one place and is where the stations of the props have it, and its plate and its aim box turn with it.

### `gear_test.odin`
- Two mistakes of the tests, not of the code: a vial that was meant to be too far from a hole was only a hole's width from the next one, and a vial that was let go of at the end of a test was drawn into the hole beside it, as it should be.
- None recorded yet for the moved scale.

### `touch.odin`
- Tested with 36 deliberate changes, one at a time, in a copy of the package: 35 were caught and one change survived, which swaps `>` for `>=` at the exact edge of the dead zone, where both give zero, so it is the same code. Survivors before that were a clamp that no test pinned by numbers, an aim finger whose movement was never added after another finger's, and two lines that did nothing and were taken out (a second cap on the number of fingers inside `update`, which the slot check already does, and a check that the turn was above zero before cutting it, which the comparison with the cap already covers). The runner is not kept in the repo.
- The first version of the corner test only checked that the ring stayed on the screen, which a wrong right-hand limit also does, so the limits are pinned by numbers.
- Nothing here has been seen on a phone.

### `touch_test.odin`
- None recorded yet.

### `chemistry.odin`
- `harm_of` and the harm of each compound were added after the lab was wired. The damage, status and death of the 17 compounds are drafts written by Claude to the vocabulary Claude proposed (five statuses, six deaths), after the owner said that each compound has its own damage, that some have status effects, and that the death of a player depends on the compound. The owner's own word for damage in the message was read as damage. The 82 deliberate changes of the engine, including `harm_of`, were all caught after one more test was written (the death goes by damage done and not by volume); the first run let that one through. Nothing reads `harm_of` yet.
- Changed for the lab: a reaction now stays done while its conditions hold and is cleared when they stop holding, and pouring no longer clears anything. The first version cleared everything at each pour, and a test of a 20-drop pour of water into spirit found that it warmed the mix by 2 degrees at every drop. `mix_draw`, `mix_scale`, `dominant`, `name_of`, `cname_of` and `color_of` were added with tests. The 65 deliberate changes of the engine, which now include the re-arming, the draw and the scale, were all caught after two more tests were written: one for a failure that can fail again, one for a share over 1 or under 0.
- The first run of the tests found a loop: a reaction that had been penalised for the wrong order was picked again at once, eight times, because only reactions that leave their inputs were remembered as done. Penalised reactions are now remembered too.
- Tested with 51 deliberate changes, one at a time, in a copy of the package: 51 were caught (see the next entry for the later 65). The first run let eight through, which showed tests missing for the unsafe meter (its failure inside a window, its being ignored outside one, its stop at 1), for made compounds counted in the order of pouring, for the most-inputs rule beside a reaction with its own station, for a mix having the seed of a compound, and for the tie between two reactions with their own station. A rule that clears the remembered reactions after a conversion was removed: it would have let a reaction that leaves its inputs run a second time after an unrelated reaction, and no scenario in the pages needs it. A rule that put a running reaction over a failing one at a tie was removed too, because no pair of reactions in the pages could show it. The runner is not kept in the repo.
- The `Run` over `Fail` rule and the clearing in `convert` were removed rather than tested, as the pages cannot make either happen. If a page ever needs them they will come back with a test.
- Wired into the lab by `mixing.odin`, and not seen running in a game.
- It builds as an Android arm32 object with `-o:minimal` and with `-o:size`, alone, as nothing imports it yet. It uses no raylib and does not allocate. It has not run on a phone.
- `page_of`, `page_count`, `bands_of` and `label_of` were added for the book. Tested with 16 deliberate changes, one at a time, in a copy of the package: 14 were caught. Of the two that were not, one was a guard on `has_failure` that the pages cannot make matter, because a reaction with failure outputs always has a failure, and one was the check that only the first band is taken as the top of a range, which makes no difference while the bands do not overlap. A third survivor was a real gap, a range that has a bottom band and no top one, and a test was written for it. One change did not compile and was written again.

### `pages_data.odin`
- Written by the script from the 17 pages: the three product pages for ethylene, sulfur dioxide and hydrogen were drafted by Claude because they were missing, so the tables hold three compounds whose numbers are drafts.

### `chemistry_test.odin`
- The tests of the pages of the book were pinned to the pages as they are (water 13 lines, sulfuric acid 11, ethanol 8, hydrogen 7), so a page edit that changes how many reactions a compound is in will change them, as the other pinned numbers do.
- A first draft of the eight-compound test used enum arithmetic that Odin rejects, a first draft of the ratio test had a share of acid that was just below the tolerance, and two tests shadowed a name that `-vet` refuses. All were fixed before the tests were used to judge the engine.

### `mix_label.odin`
- New, with no test, as above.

