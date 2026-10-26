# client

## Overview

The Odin client: window, input, rendering, scenes, and the crafting-lab prototype. It links the Rust simulation through the C ABI in `tv_ffi`. Raylib comes from the `vendor:raylib` package that ships with the Odin compiler (raylib 6.0 in the release used here).

The game is arranged in scenes, as in Unity. There are two scenes. The lab room is the chemistry lab, walked around in first person: a large open room with long counters along the walls and one in the middle. Glass vessels with colored liquid in them stand on the middle counter, ten with one of each stock liquid and the rest empty, and can be picked up, carried in the player's hands, and poured into each other, which makes the liquids react: the held vessel tips over and its liquid runs out as a stream of drops, simulated, into the vessel under the crosshair. A bottle wall along the east side fills a held vessel from a tap for each stock liquid. Some reactions are violent enough to hurt the player and break the vessel, and a menu shows every reaction and which are volatile. The player can also jump. The balloon lab is the balloon on its own: a 3D water balloon that can be grabbed and dragged. Lifting it by its tied tip makes it hang as a teardrop, and dropping it makes it squash and wobble. The lab overlay also shows the result of a start-up check of the local database, which reads and writes DixScript through its C library. The balloon editing menu, the arena, networking, and balloon painting are not started.

Commands, run from the repository root with `cargo` and `odin` on the path:

- `bash scripts/build_client.sh` builds the Rust library and the client into `build/`.
- `build/tv_client --selftest` runs without a window and checks the ABI, the simulation, and the 3D balloon.
- `odin test client/src/lab` runs the lab layout, player, and collision tests.
- `odin test client/src/chem` runs the compound and reaction matrix tests.
- `odin test client/src/mpm` runs the liquid simulation tests.
- `odin test client/src/carry` runs the tests for picking up, carrying, and dropping vessels, what a vessel holds, mixing and its blasts, health, the vessel and hand shapes, and the hand poses.
- `odin test client/src/balloon` runs the balloon tests, and `odin test client/src/softbody` runs the older 2D ring tests.
- `odin test client/src/store` runs the local-database tests. Three of them need a DixScript library and skip themselves without one. `TV_MDIX_FAKE_LIB` points at the stand-in built with `cc -shared -fPIC -o libfake_mdix.so client/src/store/testdata/fake_mdix_ffi.c`, and `TV_MDIX_LIB` points at the real DixScript library.
- `odin run client/bench -o:speed` runs the soft-body, balloon, and liquid simulation benchmarks.
- From `build/`, `./tv_client --fixed-step --frames 240 --screenshot lab.png` runs the lab for a fixed number of frames and saves a screenshot. The screenshot path is relative to the working directory. Under a virtual display this works in CI: `xvfb-run -a ./tv_client ...`.
- `--demo hang` and `--demo swing` script the pointer: after 90 frames the tip is grabbed and lifted, and `swing` then sways it side to side. `--fixed-step` advances the game by exactly 1/60 s per frame, so a given frame count always shows the same picture. `--size 1600x720` opens a window of that size, which is handy for trying a phone's wide screen. `--scene room`, `--scene balloon`, or `--scene bench` picks the scene to start in, and the demos only act in the balloon scene. In the lab room a desktop walks with WASD or the arrow keys and looks by dragging the mouse. A small button in the top right corner switches scenes, a button in the bottom right corner grabs the vessel under the crosshair or lets go of the one held, and a jump button sits above it. A pour button sits left of the grab button: held down it tips the held vessel over to pour into the vessel under the crosshair, and it says mix when there is one close enough, fill under a tap, and pour otherwise. On a desktop E grabs, M held pours, R opens the reaction matrix, and space jumps. A button under the sim test button opens the reaction matrix, a menu with a close button that shows which mixes are volatile. A button under the scene switch opens the liquid sim test.

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
- The balloon is not placed yet. Its physics runs at a scale where the balloon is 2 units across, and when it is placed in the lab it will be drawn scaled down.

**Tests:** `lab_test.odin`.
- A counter along the east wall carries the bottle wall, with a way round it at each end. `add_dispensers` adds its rack: a backboard and, for each of ten taps, a bottle in the color of its liquid, an arm, and a nozzle. The colors are passed in, so the bottles match what comes out. `dispenser_nozzle` says where a nozzle tip is, and the carrying code uses it.

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
**What it does:** What a reaction does to the player. A volatility below 0.3 is calm, 0.3 up to 0.6 spatters, and 0.6 and over is a blast. A spatter does up to 15 damage and a blast 30 to 100, the most at point blank and falling in a straight line to nothing at the edge: 1.5 m for a spatter, and 2 to 4 m for a blast, larger for a stronger one.

**Decisions:**
- A blast damages the player and breaks the container, as decided. A spatter only stings and throws 20% of the liquid out of the vessel.
- Mixing is done with the vessel in the hands, under a metre from the eye. At 0.8 m the worst blast does 80 damage, which hurts a lot and does not kill from full health, the acid blast does about 32, and a spatter does a few.
- Every number here is a first guess to be tuned by playing.

### `chem_test.odin`
**What it does:** The ids and the table agree, and names are unique. Every pair of classes has exactly one rule, and every product is a known compound. The outcome does not depend on the order. Nothing reacts with itself or with nothing. A reaction always makes a real compound. Water thins acids, bases, oxidizers, and dyes. The known recipes make what they should. Only the planned pairs are dangerous, two blasts and two spatters, all around the oxidizer. Damage falls with distance and grows with volatility, and the worst blast at arm's length hurts a lot but does not kill.

### `carry.odin`
**What it does:** Package `carry`, the things in the lab room that the player can pick up, in metres. It has no raylib dependency, so it is tested without a window. A `Prop` is a vessel standing on a counter or the floor, holding one compound as an id and an amount in millilitres. Each frame `update` finds the prop under the crosshair, puts the held prop at a hold point in front of the eyes, and lets every other prop fall until it stands on something. `grab` takes the prop under the crosshair when the hands are empty and `release` lets go. `state_of` says whether the hands are idle, reaching, or holding, and that drives the hands, the crosshair, and the grab button. `props_remove` takes a vessel out when it breaks and keeps the held and aimed indices right, `focus` names the vessel the contents label is about, and `far_to_near` orders the props for drawing see-through glass. The view follows the player's eye, so it rises with a jump. While the pour button is down the held vessel tips over, to 137 degrees, and comes back when it is released. `update` aims every frame, even while a vessel is held, so the crosshair can pick the vessel to pour into, and `pour_target` is that vessel when it is within 1.5 m and has room.

**Decisions:**
- The crosshair test is a ray from the eye against a box around each prop, padded by 5 cm, with a reach of 2 m. The padding makes small vessels easy to hit when aiming with a thumb. A counter between the eye and a prop hides it.
- One prop is held at a time. A held vessel is held by its middle and tips about it, and is kept above the counters by how far it reaches up and down at its tilt.
- The hold point is 0.55 m ahead, 0.17 m to the right, and 0.20 m below the eye. The held prop is kept inside the room and never lower than the counter top when any part of it is over a counter, so it rests on the counter instead of passing through it. This is a clamp and not a push, so it cannot jam.
- A released prop falls under gravity and stops on the counter top or the floor under any part of its footprint. Props do not collide with each other yet, and a vessel that is only partly over a counter edge stays up on the counter.
- A vessel holds one compound, and an amount above what it can hold is cut down when it is added. A vessel with no compound holds nothing.
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
**What it does:** What happens when a drop of one liquid falls into a vessel. `apply_droplet` adds the drop. When two different liquids meet, they react once for the whole pour: a `Session` remembers the vessel and what is being poured into it, until the drops stop for 0.6 s, and the contents become the product, with the drops that follow in the same pour joining the product as it is. A calm reaction leaves the product, a spatter loses 20% of it and stings, and a blast breaks the vessel and takes the liquid with it. The first drop of a meeting gives a `Mix_Result` saying what happened and how much damage the player takes, from the distance between the eye and the vessel.

**Decisions:**
- A dangerous pair reacts on the first drop that touches it, as it would on contact, so a blast cannot be avoided by pouring slowly, and the damage does not depend on how much is poured.
- A whole pour is one meeting, so the amount poured sets how much product there is and not how many reactions happen. Acid poured into base makes foam, and not foam turned back into acid by the next drop.
- A second pour after a pause is a new meeting, with the product as what is in the vessel.
- A drop into an empty vessel, or one with the same liquid, simply joins it. A drop into a full vessel is lost.
- The vessel that was poured from is not touched by a blast, and stays in the hands.

**Tests:** `carry_test.odin`.

### `stream.odin`
**What it does:** Liquid in the air: poured from a vessel or let out of a tap, falling, splashing, and either landing in a vessel, which takes it, or on a surface, where it is wiped away after a moment. Each drop is a particle of the liquid simulation, standing for 3.4 ml, in a box of 44 cells of 3 cm that is set in the world when the first drop is made, with its floor on whatever is under it. `pour_flow` lets the held vessel pour, `stream_step` runs the simulation, and `stream_capture` hands drops to the vessels they have fallen into.

**Decisions:**
- The cell size comes from the first phone benchmark. At 4.3 microseconds a particle each step, a 3 cm cell lets a pour of about twenty drops in flight run in a few milliseconds, and a finer cell does not fit. A pour never has more than 96 drops in flight. When the stream is full, the liquid waits at the lip, so a pour slows down and the frame does not.
- A tipped vessel keeps what it can hold below its lowest rim point, found from the shape, and the rest runs over the lip, as fast as its neck allows: 150 ml a second for a beaker, 90 for a flask, 70 for a bottle. A vessel can tip to 137 degrees, because a narrow neck kept about 24 ml at 100 degrees.
- With the crosshair on a vessel close enough, the drops leave the lip with the velocity of an arc that ends at its mouth, so the stream goes in however the lip is placed. With no target they leave forward from the lip.
- A drop inside a column a little wider than a vessel, reaching 12 cm above its rim, goes in. That is the aim assist of a pour, and it makes a small mouth easy to hit with a thumb. A vessel being poured from does not take drops, and one held upright does, which is how a tap fills it.
- Drops let out in one frame are spread along their way, as if let out at different moments. Two made in one place push each other apart in the simulation, which sent half a pour to the wrong place until a test showed it.
- Liquid at the lip when the vessel is put upright runs back in, and a vessel that runs dry is emptied.
- Puddles are not kept. A drop is wiped away after lying still for 1.2 s or after 8 s.
- When the floor is more than a metre below the lip, the box floor is in the air, and a drop that reaches it falls out.

**Tests:** `carry_test.odin`.

### `station.odin`
**What it does:** The bottle wall: a tap for each of the ten stock liquids, in the order of their ids. `dispenser_under` finds the tap the held vessel is under: roughly centered below the nozzle, upright, with room in it, and its top 0 to 55 cm below the tip. `station_flow` lets 110 ml a second out of the nozzle as drops, which fall into the vessel. `station_colors` gives the colors of the bottles, from the liquids in them.

**Decisions:**
- The supply is endless. Each tap has an `unlocked` flag that stops it giving anything, as the hook for the progression the lab is meant to have, where not everything is open from the start. Every tap is unlocked for now.
- The pour button fills the vessel under a tap, and tips the vessel over everywhere else, so one button does both.

**Tests:** `carry_test.odin`.

### `stream_view.odin`
**What it does:** Draws the liquid in the air as small diamonds in the color of the liquid, lighter on top and darker underneath. They are drawn by the batch renderer with no lighting, without back-face culling.

**Decisions:** A diamond is eight triangles, so a full stream of 96 is under 2300 vertices, which is cheap on a phone. Spheres drawn one at a time would not be.

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
**What it does:** The lab room scene. It owns the layout, the player, the room mesh, the controls, the props, the hands, the stream of liquid, the bottle wall, and the health. Each frame it reads the pointers, turns the view by the look drag, and walks by the joystick or the keyboard. The pour button held down either fills the held vessel from the tap it is under or tips it over to pour. The liquid is let out, simulated, and taken by the vessels it falls into, and a reaction that a pour starts is shown and takes its damage. The grab button, or E on a desktop, grabs or releases, and the jump button, or space, jumps. The matrix button, or R, opens the reaction matrix and pauses the lab until it is closed. The room is drawn first, then the hands and the bottle caps, then the liquid in the air, then the liquid in the vessels, then the glass blended over it all. The camera is at eye height, 1.6 m, with a 70 degree field of view. At zero health the player is knocked out and the lab is put back as it was.

**Decisions:**
- First person with a joystick, so the room can be crossed without a pointer tap on a floor spot and so stations can be reached by walking.
- The clip planes are 0.08 to 70 for the room. The default far plane of 4000 gives a 16-bit depth buffer almost no precision.
- The button in the corner changes scenes, so the balloon lab stays reachable on a phone.
- The liquid takes as many substeps as a real-time frame needs, or fewer if they would take more than 5 ms, going by how long a step took lately. Then the liquid runs a little slower than real time and the frame is not late.
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
**What it does:** Copies the shapes from `carry` into raylib meshes and draws them: for each kind of vessel its glass and the liquid inside it, the cap of a bottle, and a unit cube in glove blue and in sleeve white for the hands. Drawing is in passes. Hands and bottle caps are solid and use the room's material. Liquid is drawn next with the vessel shader, cut off at a flat surface in world space, with back faces on so the cut shows as the surface. Glass is drawn last, from the farthest vessel to the nearest, blended over everything behind it and without writing depth, so glass behind glass still shows. If the vessel shader fails to compile, the glass is drawn solid with the room's shader and there is no liquid.

**Decisions:**
- The matrix for each piece is built by hand. Raylib's `Matrix` in the Odin binding is row-major, with the move in the last column.
- Mesh memory comes from raylib's allocator, because `UnloadMesh` frees it.
- The hands and the held vessel are depth tested with the room, and the hands are drawn before the glass, so fingers behind a vessel are hidden by it and fingers in front of it are not. The cost is that a hand can poke into a counter when the player looks steeply down very close to it. A separate depth pass for the hands would fix that if it shows.
- The liquid is drawn opaque, so it needs no sorting.

### `interact_ui.odin`
**What it does:** The 2D pieces of carrying, pouring, and jumping: the crosshair dot with a hand icon under it, lines about the vessel in view or in hand, the grab button in the bottom right corner, the jump button above it, and the pour button to its left. The icon is an open hand in white while nothing is in reach, in teal when something is, and a closed fist while holding. The lines name the liquid and say how full the vessel is, and with a vessel held and another under the crosshair, close enough, they add what is in that one. The grab button says grab, and release while holding, and is dimmer when nothing is in reach. The pour button is held down. It says mix and is bright when there is a vessel to pour into, fill under a tap, and pour and dim when it would only spill. The jump button is dimmer in the air. At the top are a health bar and, for a moment after a hit, a red flash over the whole screen, a white-hot one for a blast or spatter, and a message saying what a mix made. A small button under the scene switch opens the liquid sim test.

**Decisions:**
- Grabbing on a phone is a button that turns into the release button while holding, as decided in the design discussion.
- Pouring is a held button. The target is the vessel under the crosshair within 1.5 m, and that is what makes the button bright. The first version asked for the held vessel to be directly over the target, which was hard to line up and gave no hint, so it was changed.
- Buttons have a dark backing, a bright edge, and a shadowed label, so they read on the light floor and walls as well as on the dark counters.
- The icons are drawn from rounded rectangles in code, so no image files have to be packaged into the APK.
- The icons are opaque with a dark outline, so overlapping pieces do not blend twice and the icon reads on light and dark surfaces.
- The contents lines are built in a buffer on the stack, so nothing is allocated each frame.

### `lab.vs`
**What it does:** Vertex shader for the room, the vessels, and the hands. The room mesh is in world space and is drawn with an identity model matrix, so its positions and normals pass straight through. Vessels and hands are drawn with a model matrix that moves them, and the shader applies it so the lighting and fog work on world positions. The vertex color and the glow and gloss values are passed on. There are two versions, `shaders/glsl330/` and `shaders/glsl100/`.

**Decisions:** The two files are kept in step by hand. Both pass `glslangValidator`.
- The glass and liquid of the vessels use this same vertex shader, with `vessel.fs` as their fragment shader.

### `lab.fs`
**What it does:** Fragment shader for the room. The lab has no real lights. Shading is a sky-and-floor ambient term, a soft key light from above, full brightness for the ceiling panels and counter glow, a sheen on glossy surfaces that grows at a slant, and fog that fades the far end of the room into the background color.

**Decisions:** Fake lighting costs the same however many lights the room has. The fog color matches the clear color of the room scene, so the far wall fades into the background. Highp precision is used where the device has it.

### `vessel.fs`
**What it does:** Fragment shader for the glass vessels and the liquid in them. One file serves both, switched by the `liquidMode` uniform. Glass is nearly clear in the middle of a surface, turns more solid toward its edge, and has a bright glint where it catches the light. Liquid is shaded like the room and cut off at a flat surface at the height `levelY`, in world space, in the color `liquidColor`. The liquid is drawn as a closed solid, so where the surface cuts it we see the inside of its far wall, and that is painted as the surface.

**Decisions:**
- The cut is made against the world position of each pixel, so when a vessel is tilted for pouring the surface will stay flat in the world with no change to the shader.
- Glass alpha stays at or below 0.88, so even the edge of a vessel shows what is behind it.
- Fog is the same as in `lab.fs`, so vessels far away fade with the room.
- The lighting is the same fake light as the room, so no real light is needed. The GLES 2 version is kept in step with the desktop one by hand.

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

- `.github/workflows/ci.yml` job `odin` downloads a pinned Odin release, runs `odin check`, the soft-body, balloon, lab, and carry tests, validates all the shader files, builds and runs `--selftest`, and renders headless screenshots of the lab resting and held by its tip, which are kept as an artifact.
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

### `health.odin`
- The knock-out rule, which resets the lab, is an assumption.

### `stream.odin`
- The first pours lost most of their liquid. Drops let out in the same frame were made in the same place and pushed each other apart in the simulation, and the vessel was allowed to tip so far that its lip was inside the counter. Both were found with a test that pours into a vessel and counts what arrives.
- Nothing has run on a phone yet. The drops use the liquid simulation at 3 cm cells, which the benchmark said fits.

### `station.odin`
- None recorded yet. Every tap is unlocked, and nothing takes a cost for the liquid.

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
- The carrying, hands, crosshair, and grab button were written and compile for desktop and Android, but have not been seen running on a phone yet.

### `lab.vs`
- The shader now reads the model matrix. The room is drawn with an identity matrix, so its look does not change. The normal is moved with `vec4(normal, 0.0)` and not `mat3(matModel)`, because GLSL ES 1.00 may not accept a matrix built from a matrix.

### `lab.fs`
- None recorded yet.

### `vessel.fs`
- None recorded yet. The glass and liquid look has been compiled and validated with glslang for both GLSL versions, but not seen on a device.

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
