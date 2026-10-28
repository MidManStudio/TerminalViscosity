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
