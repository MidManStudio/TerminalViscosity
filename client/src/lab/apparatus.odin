// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "apparatus.odin"
// ============================================================================

package lab

// The workstations of the lab, as boxes and as the places they act on: the sink
// with its drain on the west counter, the fume hood on the north counter, and the
// balloon fill station on the south counter. What each does is in package carry;
// this file only says where things are and builds what is static. The glass of the
// hood and the gauge of the fill station change from frame to frame, so the client
// draws them itself. Units are metres.

// The inside of the sink basin. A drop that falls into it, near the counter top,
// goes down the drain.
SINK_BASIN :: Rect {
	min_x = -11.88,
	min_z = -4.7,
	max_x = -11.38,
	max_z = -3.7,
}
SINK_DRAIN_TOP :: COUNTER_HEIGHT + 0.10

// The floor of the fume hood and how high it reaches. A vessel whose middle is
// inside this footprint and under the top is in the hood.
HOOD :: Rect {
	min_x = -6.8,
	min_z = -7.98,
	max_x = -5.2,
	max_z = -7.28,
}
HOOD_TOP :: f32(2.25)
HOOD_GLASS_LOW :: f32(1.55) // the sash is raised, so the glass starts here and the hands go under it
HOOD_GLASS_Z :: f32(-7.27)

// The reaction oven on the north counter: a big box with four ports on top, each
// taking one liquid, a window and lights on the front, and a spout under the
// lights that fills a held vessel with the product. A vessel's mouth at a port is a
// funnel, as at the fill station.
MIXER :: Rect {
	min_x = 2.2,
	min_z = -7.94,
	max_x = 3.8,
	max_z = -7.32,
}
MIXER_TOP :: f32(1.62) // the top of the box, where the funnels start
MIXER_PORTS :: 4
MIXER_PORT_SPACING :: f32(0.4)
MIXER_PORT_RADIUS :: f32(0.06)
MIXER_CAPTURE_ABOVE :: f32(0.30) // a drop up to this far over the top, inside a funnel, goes in
MIXER_SPOUT :: Vec3{3.0, 1.41, -7.25} // the tip of the spout
MIXER_AIM_LOW :: Vec3{2.18, 1.1, -7.96} // the box the crosshair tests for the oven
MIXER_AIM_HIGH :: Vec3{3.82, 1.95, -7.30}
MIXER_PROGRESS_LIGHTS :: 10

// The hot plate and the ice bath on the north counter. A vessel standing on one
// takes the temperature of the station, slowly: the plate warms what is in it and
// the bath cools it. A vessel counts as standing on one when its middle is inside
// the footprint and it is resting near the counter top.
HOT_PLATE :: Rect {
	min_x = -3.8,
	min_z = -7.88,
	max_x = -3.2,
	max_z = -7.38,
}
ICE_BATH :: Rect {
	min_x = -2.8,
	min_z = -7.88,
	max_x = -2.0,
	max_z = -7.38,
}
STATION_RESTING :: COUNTER_HEIGHT + 0.06

// The paint station on the west counter: a frame that holds a balloon by a clamp at
// its neck and a second clamp under its bottom, with a palette and a rack of
// brushes beside it. The drawing itself is not built yet. The balloon hangs from
// `PAINT_CLAMP`, and at its full size its bottom is `PAINT_DROP` below.
PAINT_CLAMP :: Vec3{-11.63, 1.62, 2.0}
PAINT_DROP :: f32(0.15)
PAINT_AIM_LOW :: Vec3{-11.85, 1.25, 1.78}
PAINT_AIM_HIGH :: Vec3{-11.41, 1.78, 2.22}
PALETTE_SIZE :: 16

// The loadout rack on the south counter: a hook for each balloon of the loadout, a
// light over each that shows what is on it. The balloons hang by their necks, as
// at the fill station.
LOADOUT_SLOTS :: 3
SLOT_FIRST_X :: f32(8.4)
SLOT_SPACING :: f32(0.4)

// The balloon fill station: a stand with a clamp that holds the neck of a balloon,
// a funnel over the clamp for pouring into, and a gauge beside it.
FILLER_CLAMP :: Vec3{6.0, 1.52, 7.45} // where the neck of the balloon is held
FILLER_MOUTH :: Vec3{6.0, 1.68, 7.45} // the middle of the rim of the funnel
FILLER_FUNNEL_RADIUS :: f32(0.06)
FILLER_CAPTURE_LOW :: f32(1.54) // a drop between these heights over the funnel goes into the balloon
FILLER_CAPTURE_HIGH :: f32(1.82)
FILLER_AIM_LOW :: Vec3{5.86, 1.26, 7.31} // the box the crosshair tests for the station
FILLER_AIM_HIGH :: Vec3{6.14, 1.74, 7.59}
GAUGE_ORIGIN :: Vec3{6.30, 1.28, 7.505} // the lowest light of the gauge
GAUGE_LIGHTS :: 10
GAUGE_SPACING :: f32(0.04)

COLOR_METAL :: [4]u8{70, 78, 90, 255}
COLOR_STEEL :: [4]u8{170, 180, 190, 255}
COLOR_PANEL :: [4]u8{200, 208, 216, 255}

// Adds the boxes of the three workstations. They stand on counters that
// `build` has already made, and block nobody: the counters do that.
add_apparatus :: proc(l: ^Layout) {
	add_sink(l)
	add_hood(l)
	add_filler(l)
	add_mixer(l)
	add_hot_plate(l)
	add_ice_bath(l)
	add_paint_station(l)
	add_loadout_rack(l)
}

add_sink :: proc(l: ^Layout) {
	b := SINK_BASIN
	cx, cz := (b.min_x + b.max_x) * 0.5, (b.min_z + b.max_z) * 0.5
	w, d := b.max_x - b.min_x, b.max_z - b.min_z
	top := COUNTER_HEIGHT
	add_box(l, {cx, top + 0.006, cz}, {w, 0.012, d}, COLOR_STEEL, 0, 1)
	rim := f32(0.03)
	add_box(l, {b.min_x - 0.02, top + rim * 0.5, cz}, {0.04, rim, d + 0.08}, COLOR_METAL, 0, 0.6)
	add_box(l, {b.max_x + 0.02, top + rim * 0.5, cz}, {0.04, rim, d + 0.08}, COLOR_METAL, 0, 0.6)
	add_box(l, {cx, top + rim * 0.5, b.min_z - 0.02}, {w, rim, 0.04}, COLOR_METAL, 0, 0.6)
	add_box(l, {cx, top + rim * 0.5, b.max_z + 0.02}, {w, rim, 0.04}, COLOR_METAL, 0, 0.6)
	add_box(l, {cx, top + 0.016, cz}, {0.1, 0.016, 0.1}, {24, 28, 34, 255})
}

add_hood :: proc(l: ^Layout) {
	h := HOOD
	cx, cz := (h.min_x + h.max_x) * 0.5, (h.min_z + h.max_z) * 0.5
	w, d := h.max_x - h.min_x, h.max_z - h.min_z
	height := HOOD_TOP - COUNTER_HEIGHT
	mid := COUNTER_HEIGHT + height * 0.5
	add_box(l, {cx, mid, h.min_z + 0.02}, {w + 0.1, height, 0.04}, COLOR_PANEL, 0, 0.3)
	add_box(l, {h.min_x - 0.025, mid, cz}, {0.05, height, d}, COLOR_PANEL, 0, 0.3)
	add_box(l, {h.max_x + 0.025, mid, cz}, {0.05, height, d}, COLOR_PANEL, 0, 0.3)
	add_box(l, {cx, HOOD_TOP + 0.04, cz}, {w + 0.1, 0.08, d + 0.02}, COLOR_METAL, 0, 0.4)
	add_box(l, {cx, HOOD_TOP - 0.03, h.max_z - 0.02}, {w - 0.1, 0.025, 0.025}, COLOR_GLOW, 1)
}

add_filler :: proc(l: ^Layout) {
	c := FILLER_CLAMP
	m := FILLER_MOUTH
	top := COUNTER_HEIGHT
	add_box(l, {c.x, top + 0.01, 7.63}, {0.34, 0.02, 0.5}, COLOR_METAL, 0, 0.5) // the base plate
	add_box(l, {c.x, top + 0.02 + 0.25, 7.84}, {0.04, 0.5, 0.04}, COLOR_METAL, 0, 0.5) // the pole
	add_box(l, {c.x, 1.60, (7.84 + c.z - 0.02) * 0.5}, {0.04, 0.04, 7.84 - c.z + 0.02}, COLOR_METAL, 0, 0.5) // the arm
	// The collar that holds the neck, four thin walls.
	add_box(l, {c.x - 0.05, 1.55, c.z}, {0.012, 0.06, 0.112}, COLOR_STEEL, 0, 0.8)
	add_box(l, {c.x + 0.05, 1.55, c.z}, {0.012, 0.06, 0.112}, COLOR_STEEL, 0, 0.8)
	add_box(l, {c.x, 1.55, c.z - 0.05}, {0.112, 0.06, 0.012}, COLOR_STEEL, 0, 0.8)
	add_box(l, {c.x, 1.55, c.z + 0.05}, {0.112, 0.06, 0.012}, COLOR_STEEL, 0, 0.8)
	// The funnel on top of it, four walls.
	r := FILLER_FUNNEL_RADIUS + 0.006
	add_box(l, {m.x - r, m.y - 0.035, m.z}, {0.012, 0.07, 2 * r + 0.012}, COLOR_STEEL, 0, 0.8)
	add_box(l, {m.x + r, m.y - 0.035, m.z}, {0.012, 0.07, 2 * r + 0.012}, COLOR_STEEL, 0, 0.8)
	add_box(l, {m.x, m.y - 0.035, m.z - r}, {2 * r + 0.012, 0.07, 0.012}, COLOR_STEEL, 0, 0.8)
	add_box(l, {m.x, m.y - 0.035, m.z + r}, {2 * r + 0.012, 0.07, 0.012}, COLOR_STEEL, 0, 0.8)
	// The back of the gauge.
	g := GAUGE_ORIGIN
	add_box(l, {g.x, g.y + GAUGE_SPACING * (GAUGE_LIGHTS - 1) * 0.5, g.z + 0.015}, {0.1, GAUGE_SPACING * GAUGE_LIGHTS + 0.04, 0.02}, {20, 26, 34, 255})
}

add_mixer :: proc(l: ^Layout) {
	m := MIXER
	cx, cz := (m.min_x + m.max_x) * 0.5, (m.min_z + m.max_z) * 0.5
	w, d := m.max_x - m.min_x, m.max_z - m.min_z
	height := MIXER_TOP - COUNTER_HEIGHT
	add_box(l, {cx, COUNTER_HEIGHT + height * 0.5, cz}, {w, height, d}, COLOR_PANEL, 0, 0.4) // the body
	add_box(l, {cx - 0.1, 1.24, m.max_z + 0.003}, {1.0, 0.18, 0.012}, {26, 30, 38, 255}, 0, 0.9) // the window
	// The spout: a bracket out of the front and a nozzle that hangs from it.
	add_box(l, {MIXER_SPOUT.x, 1.47, m.max_z + 0.035}, {0.04, 0.04, 0.1}, COLOR_METAL, 0, 0.5)
	add_box(l, {MIXER_SPOUT.x, MIXER_SPOUT.y + 0.025, MIXER_SPOUT.z}, {0.04, 0.05, 0.04}, COLOR_METAL, 0, 0.5)
	// A funnel over each port, four thin walls.
	r := MIXER_PORT_RADIUS + 0.006
	for i in 0 ..< MIXER_PORTS {
		p := mixer_port(i)
		add_box(l, {p.x - r, MIXER_TOP + 0.035, p.z}, {0.012, 0.07, 2 * r + 0.012}, COLOR_STEEL, 0, 0.8)
		add_box(l, {p.x + r, MIXER_TOP + 0.035, p.z}, {0.012, 0.07, 2 * r + 0.012}, COLOR_STEEL, 0, 0.8)
		add_box(l, {p.x, MIXER_TOP + 0.035, p.z - r}, {2 * r + 0.012, 0.07, 0.012}, COLOR_STEEL, 0, 0.8)
		add_box(l, {p.x, MIXER_TOP + 0.035, p.z + r}, {2 * r + 0.012, 0.07, 0.012}, COLOR_STEEL, 0, 0.8)
	}
}

add_hot_plate :: proc(l: ^Layout) {
	h := HOT_PLATE
	cx, cz := (h.min_x + h.max_x) * 0.5, (h.min_z + h.max_z) * 0.5
	add_box(l, {cx, COUNTER_HEIGHT + 0.02, cz}, {h.max_x - h.min_x, 0.04, h.max_z - h.min_z}, {50, 54, 62, 255}, 0, 0.4)
	add_box(l, {cx, COUNTER_HEIGHT + 0.043, cz}, {h.max_x - h.min_x - 0.12, 0.012, h.max_z - h.min_z - 0.12}, {255, 96, 40, 255}, 1) // the coil, glowing
}

add_ice_bath :: proc(l: ^Layout) {
	b := ICE_BATH
	cx, cz := (b.min_x + b.max_x) * 0.5, (b.min_z + b.max_z) * 0.5
	w, d := b.max_x - b.min_x, b.max_z - b.min_z
	add_box(l, {cx, COUNTER_HEIGHT + 0.015, cz}, {w, 0.03, d}, {170, 214, 238, 255}, 0, 0.8) // the floor of the tub, pale blue
	rim := f32(0.07)
	add_box(l, {b.min_x - 0.015, COUNTER_HEIGHT + rim * 0.5, cz}, {0.03, rim, d + 0.06}, {120, 160, 190, 255}, 0, 0.6)
	add_box(l, {b.max_x + 0.015, COUNTER_HEIGHT + rim * 0.5, cz}, {0.03, rim, d + 0.06}, {120, 160, 190, 255}, 0, 0.6)
	add_box(l, {cx, COUNTER_HEIGHT + rim * 0.5, b.min_z - 0.015}, {w, rim, 0.03}, {120, 160, 190, 255}, 0, 0.6)
	add_box(l, {cx, COUNTER_HEIGHT + rim * 0.5, b.max_z + 0.015}, {w, rim, 0.03}, {120, 160, 190, 255}, 0, 0.6)
	// A few lumps of ice standing in it.
	add_box(l, {cx - 0.25, COUNTER_HEIGHT + 0.05, cz - 0.1}, {0.1, 0.04, 0.1}, {225, 240, 250, 255}, 0.3, 0.9)
	add_box(l, {cx + 0.28, COUNTER_HEIGHT + 0.05, cz + 0.12}, {0.09, 0.04, 0.12}, {225, 240, 250, 255}, 0.3, 0.9)
	add_box(l, {cx + 0.05, COUNTER_HEIGHT + 0.045, cz - 0.15}, {0.08, 0.03, 0.08}, {225, 240, 250, 255}, 0.3, 0.9)
}

add_paint_station :: proc(l: ^Layout) {
	c := PAINT_CLAMP
	top := COUNTER_HEIGHT
	post_x := c.x - 0.3
	add_box(l, {c.x, top + 0.01, c.z}, {0.34, 0.02, 0.6}, COLOR_METAL, 0, 0.5) // the base plate
	add_box(l, {post_x, top + 0.02 + 0.33, c.z}, {0.04, 0.66, 0.04}, COLOR_METAL, 0, 0.5) // the post
	add_box(l, {(post_x + c.x) * 0.5, 1.70, c.z}, {0.34, 0.04, 0.04}, COLOR_METAL, 0, 0.5) // the top arm
	add_box(l, {c.x, 1.675, c.z}, {0.03, 0.05, 0.03}, COLOR_METAL, 0, 0.5) // down to the top clamp
	add_clamp(l, {c.x, 1.65, c.z})
	// The second clamp, a cradle under the bottom of the balloon at its full size.
	bottom := c.y - PAINT_DROP
	add_box(l, {(post_x + c.x) * 0.5, bottom - 0.05, c.z}, {0.34, 0.04, 0.04}, COLOR_METAL, 0, 0.5)
	add_clamp(l, {c.x, bottom - 0.01, c.z})
	// The palette: a board standing on the counter with a grid of swatches on it.
	bz := c.z + 0.6
	add_box(l, {post_x - 0.01, top + 0.18, bz}, {0.03, 0.36, 0.4}, {30, 36, 46, 255})
	for k in 0 ..< PALETTE_SIZE {
		row, col := k / 4, k % 4
		add_box(l, {post_x + 0.01, top + 0.05 + 0.085 * f32(row), bz - 0.15 + 0.1 * f32(col)}, {0.012, 0.07, 0.08}, palette_color(k), 0.2)
	}
	// A cup of brushes, to the other side.
	cz := c.z - 0.5
	add_box(l, {post_x + 0.05, top + 0.04, cz}, {0.07, 0.08, 0.07}, {80, 84, 94, 255})
	for k in 0 ..< 3 {
		add_box(l, {post_x + 0.035 + 0.025 * f32(k), top + 0.14, cz}, {0.012, 0.16, 0.012}, {170, 126, 70, 255})
	}
}

// Four thin walls round a point, that hold the neck or the bottom of a balloon.
add_clamp :: proc(l: ^Layout, c: Vec3) {
	add_box(l, {c.x - 0.04, c.y, c.z}, {0.012, 0.05, 0.092}, COLOR_STEEL, 0, 0.8)
	add_box(l, {c.x + 0.04, c.y, c.z}, {0.012, 0.05, 0.092}, COLOR_STEEL, 0, 0.8)
	add_box(l, {c.x, c.y, c.z - 0.04}, {0.092, 0.05, 0.012}, COLOR_STEEL, 0, 0.8)
	add_box(l, {c.x, c.y, c.z + 0.04}, {0.092, 0.05, 0.012}, COLOR_STEEL, 0, 0.8)
}

add_loadout_rack :: proc(l: ^Layout) {
	mid := SLOT_FIRST_X + SLOT_SPACING * f32(LOADOUT_SLOTS - 1) * 0.5
	add_box(l, {mid, 1.55, 7.90}, {SLOT_SPACING * f32(LOADOUT_SLOTS) + 0.2, 0.5, 0.03}, {20, 26, 34, 255}) // the board behind the hooks
	for i in 0 ..< LOADOUT_SLOTS {
		c := slot_clamp(i)
		add_box(l, {c.x, 1.60, (7.885 + c.z) * 0.5}, {0.03, 0.03, 7.885 - c.z}, COLOR_METAL, 0, 0.5) // the arm from the board
		add_clamp(l, {c.x, 1.55, c.z})
	}
}

// The color of swatch `k` of the palette. These are stand-ins: the palette of the
// drawing is not decided.
palette_color :: proc(k: int) -> [4]u8 {
	table := [PALETTE_SIZE][4]u8 {
		{20, 20, 24, 255},
		{110, 112, 120, 255},
		{200, 204, 210, 255},
		{250, 250, 250, 255},
		{200, 40, 40, 255},
		{240, 120, 40, 255},
		{245, 205, 50, 255},
		{140, 200, 60, 255},
		{40, 160, 80, 255},
		{40, 190, 190, 255},
		{50, 120, 220, 255},
		{70, 60, 190, 255},
		{150, 70, 200, 255},
		{230, 90, 170, 255},
		{140, 90, 50, 255},
		{250, 190, 160, 255},
	}
	return table[clamp(k, 0, PALETTE_SIZE - 1)]
}

// Where the neck of the balloon on hook `i` of the loadout rack is held.
slot_clamp :: proc(i: int) -> Vec3 {
	return {SLOT_FIRST_X + SLOT_SPACING * f32(i), 1.52, 7.45}
}

// The box the crosshair tests for hook `i`.
slot_aim :: proc(i: int) -> (low, high: Vec3) {
	c := slot_clamp(i)
	return {c.x - 0.14, 1.26, 7.31}, {c.x + 0.14, 1.74, 7.59}
}

// Where the light over hook `i` is, on the board.
slot_light :: proc(i: int) -> Vec3 {
	return {SLOT_FIRST_X + SLOT_SPACING * f32(i), 1.74, 7.88}
}

// The middle of the rim of the funnel of port `i`, counting from the west.
mixer_port :: proc(i: int) -> Vec3 {
	return {MIXER.min_x + 0.2 + MIXER_PORT_SPACING * f32(i), MIXER_TOP + 0.07, (MIXER.min_z + MIXER.max_z) * 0.5}
}

// Where the light of port `i` is, on the front, over the window.
mixer_port_light :: proc(i: int) -> Vec3 {
	return {MIXER.min_x + 0.2 + MIXER_PORT_SPACING * f32(i), 1.54, MIXER.max_z + 0.012}
}

// Where light `i` of the strip that shows how far a run is, across the window.
mixer_progress_light :: proc(i: int) -> Vec3 {
	return {2.0 + 0.1 * f32(i) + 0.46, 1.24, MIXER.max_z + 0.012}
}

// Where the light that shows the product in the tank is, beside the window.
mixer_tank_light :: proc() -> Vec3 {
	return {3.62, 1.24, MIXER.max_z + 0.012}
}

// Where the oven vents, over the middle of its top, for steam while it runs.
mixer_vent :: proc() -> Vec3 {
	return {(MIXER.min_x + MIXER.max_x) * 0.5, MIXER_TOP + 0.05, (MIXER.min_z + MIXER.max_z) * 0.5}
}

// The center of the balloon at the station, for aiming effects at it: a little
// under the clamp, where the round part of the balloon hangs.
filler_center :: proc() -> Vec3 {
	return {FILLER_CLAMP.x, FILLER_CLAMP.y - 0.1, FILLER_CLAMP.z}
}

// Where light number `i` of the gauge is, counting from the bottom.
gauge_light :: proc(i: int) -> Vec3 {
	return {GAUGE_ORIGIN.x, GAUGE_ORIGIN.y + GAUGE_SPACING * f32(i), GAUGE_ORIGIN.z}
}

in_rect :: proc(r: Rect, x, z: f32) -> bool {
	return x >= r.min_x && x <= r.max_x && z >= r.min_z && z <= r.max_z
}
