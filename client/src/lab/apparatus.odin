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

// The tip of the faucet over the middle of the basin. A vessel held under it is filled with water,
// the sink's own, which is what the sink is for: water has no tap on the bottle wall.
SINK_NOZZLE :: Vec3{-11.63, COUNTER_HEIGHT + 0.42, -4.2}

// The soap beside the basin: a bottle with a pump, standing on the counter at the far end of the basin from the
// wall. The box is what the crosshair has to be on to use it.
SOAP_AT :: Vec3{-11.63, COUNTER_HEIGHT, -3.5}
SOAP_AIM_LOW :: Vec3{-11.7, COUNTER_HEIGHT, -3.57}
SOAP_AIM_HIGH :: Vec3{-11.56, COUNTER_HEIGHT + 0.25, -3.43}

// The faucet counts as one more tap after the ten of the bottle wall, so that a vessel is found under
// it, and filled from it, in the same way.
TAP_COUNT :: DISPENSER_COUNT + 1
SINK_TAP :: DISPENSER_COUNT

// Where the tip of tap `i` is: a nozzle of the bottle wall, or the faucet of the sink.
tap_nozzle :: proc(i: int) -> Vec3 {
	if i == SINK_TAP {
		return SINK_NOZZLE
	}
	return dispenser_nozzle(i)
}

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
// taking one liquid, a window and lights on the front, and a spout off the right end
// over a drip tray, which fills a vessel held under it or standing on the tray. A vessel's mouth at a port is a
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
MIXER_SPOUT :: Vec3{4.02, 1.45, -7.63} // the tip of the spout, off the right end of the oven over free counter
MIXER_TRAY_RADIUS :: f32(0.11) // the drip tray under it, where a vessel can stand to be filled
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
// its neck and a second clamp, a cradle, under its bottom, with a palette and a rack of
// brushes beside it. The balloon hangs from `PAINT_CLAMP`. Once it has settled, at any
// fill from empty to stretched, the bottom of it is between 0.176 and 0.192 m below, so
// `PAINT_DROP` is 0.20, which covers the slackest, and the cradle stands `PAINT_CRADLE_GAP` lower still. The
// first cradle was placed for a balloon that reached 0.15 m, which is how far the
// soft body reaches before it has sagged, and it cut into the real one.
PAINT_CLAMP :: Vec3{-11.63, 1.62, 2.0}
PAINT_DROP :: f32(0.20)
PAINT_CRADLE_GAP :: f32(0.05)
CLAMP_HALF_HEIGHT :: f32(0.025) // the walls of a clamp are 0.05 m high
PAINT_AIM_LOW :: Vec3{-11.85, 1.25, 1.78}
PAINT_AIM_HIGH :: Vec3{-11.41, 1.78, 2.22}
PALETTE_SIZE :: 16

// The tablet beside the clamp: a flat panel, twice as wide as it is high, that
// the drawing is made on and that the balloon in the clamp wears. It is twice as
// wide because the picture goes once round the balloon, which is about twice as far
// round as it is from pole to pole, so what is drawn on the tablet looks the same on
// the balloon at its middle. It faces east, to a player at the counter.
TABLET_CENTER :: Vec3{-11.912, 1.36, 1.43} // the middle of its screen
TABLET_W :: f32(0.52) // along the counter
TABLET_H :: f32(0.26)
TABLET_AIM_LOW :: Vec3{-11.99, 1.2, 1.15}
TABLET_AIM_HIGH :: Vec3{-11.84, 1.52, 1.71}

// The incinerator on the south counter, east of the loadout rack: a squat furnace with a
// hopper on top, a glowing door in front, and a chimney. A balloon held over the hopper is
// burned, which is how the player gets rid of one.
INCINERATOR :: Rect {
	min_x = 10.2,
	min_z = 7.42,
	max_x = 10.8,
	max_z = 7.84,
}
INCINERATOR_TOP :: f32(1.58) // the top of the body, where the hopper starts
INCINERATOR_MOUTH :: Vec3{10.5, 1.68, 7.55} // the middle of the opening of the hopper
INCINERATOR_HOPPER :: f32(0.11) // half the width of the opening
INCINERATOR_AIM_LOW :: Vec3{10.17, 1.12, 7.38} // the box the crosshair tests for it
INCINERATOR_AIM_HIGH :: Vec3{10.83, 1.72, 7.88}

// The loadout rack on the south counter: a hook for each balloon of the loadout, a
// light over each that shows what is on it. The balloons hang by their necks, as
// at the fill station.
LOADOUT_SLOTS :: 3
SLOT_VIEWED_FROM :: Vec3{0, 0, -1} // the balloons on the hooks are seen from the north, where the player stands
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
	add_apparatus_with(l, default_placed())
}

// The same, with the stations that can be moved where `placed` has them.
add_apparatus_with :: proc(l: ^Layout, placed: Placed) {
	add_sink(l)
	add_hood(l)
	add_filler(l)
	add_mixer(l)
	add_placed(l, placed)
	add_paint_station(l)
	add_loadout_rack(l)
	add_incinerator(l)
	add_equipment(l)
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
	// The faucet: a pipe up the back of the basin, a spout out from its top to over the middle, a tip
	// that the water comes from, and a handle.
	n := SINK_NOZZLE
	back := b.min_x + 0.04
	pipe := n.y - top + 0.04
	add_box(l, {back, top + pipe * 0.5, cz}, {0.04, pipe, 0.04}, COLOR_STEEL, 0, 0.9)
	add_box(l, {(back + n.x) * 0.5, n.y + 0.02, cz}, {n.x - back + 0.04, 0.04, 0.04}, COLOR_STEEL, 0, 0.9)
	add_box(l, {n.x, n.y - 0.01, cz}, {0.03, 0.04, 0.03}, COLOR_STEEL, 0, 0.9)
	add_box(l, {back, top + pipe + 0.015, cz}, {0.05, 0.03, 0.12}, COLOR_METAL, 0, 0.6)
	// The soap: a bottle, a neck, and a pump head that points over the basin.
	s := SOAP_AT
	add_box(l, {s.x, s.y + 0.08, s.z}, {0.07, 0.16, 0.07}, {214, 160, 196, 255}, 0, 0.4)
	add_box(l, {s.x, s.y + 0.185, s.z}, {0.02, 0.05, 0.02}, {236, 238, 242, 255}, 0, 0.5)
	add_box(l, {s.x, s.y + 0.22, s.z - 0.02}, {0.025, 0.02, 0.07}, {236, 238, 242, 255}, 0, 0.5)
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
	// The spout: an arm out of the right end, a nozzle that hangs from it, and a tray on
	// the counter under it.
	sp := MIXER_SPOUT
	add_box(l, {(m.max_x + sp.x) * 0.5, sp.y + 0.065, sp.z}, {sp.x - m.max_x + 0.04, 0.04, 0.04}, COLOR_METAL, 0, 0.5)
	add_box(l, {sp.x, sp.y + 0.03, sp.z}, {0.04, 0.06, 0.04}, COLOR_METAL, 0, 0.5)
	add_box(l, {sp.x, COUNTER_HEIGHT + 0.006, sp.z}, {2 * MIXER_TRAY_RADIUS, 0.012, 2 * MIXER_TRAY_RADIUS}, COLOR_STEEL, 0, 0.9)
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

add_paint_station :: proc(l: ^Layout) {
	c := PAINT_CLAMP
	top := COUNTER_HEIGHT
	post_x := c.x - 0.3
	add_box(l, {c.x, top + 0.01, c.z}, {0.34, 0.02, 0.6}, COLOR_METAL, 0, 0.5) // the base plate
	add_box(l, {post_x, top + 0.02 + 0.33, c.z}, {0.04, 0.66, 0.04}, COLOR_METAL, 0, 0.5) // the post
	add_box(l, {(post_x + c.x) * 0.5, 1.70, c.z}, {0.34, 0.04, 0.04}, COLOR_METAL, 0, 0.5) // the top arm
	add_box(l, {c.x, 1.675, c.z}, {0.03, 0.05, 0.03}, COLOR_METAL, 0, 0.5) // down to the top clamp
	add_clamp(l, {c.x, 1.65, c.z})
	// The second clamp, a cradle under the bottom of the balloon, with room to spare.
	cradle := paint_cradle()
	add_box(l, {(post_x + c.x) * 0.5, cradle.y - 0.04, c.z}, {0.34, 0.04, 0.04}, COLOR_METAL, 0, 0.5)
	add_clamp(l, cradle)
	// The palette: a board standing on the counter with a grid of swatches on it.
	bz := c.z + 0.6
	add_box(l, {post_x - 0.01, top + 0.18, bz}, {0.03, 0.36, 0.4}, {30, 36, 46, 255})
	for k in 0 ..< PALETTE_SIZE {
		row, col := k / 4, k % 4
		add_box(l, {post_x + 0.01, top + 0.05 + 0.085 * f32(row), bz - 0.15 + 0.1 * f32(col)}, {0.012, 0.07, 0.08}, palette_color(k), 0.2)
	}
	// The tablet: a bezel on two short legs. Its screen is drawn by the client.
	t := TABLET_CENTER
	add_box(l, {t.x - 0.02, t.y, t.z}, {0.03, TABLET_H + 0.05, TABLET_W + 0.05}, {24, 28, 36, 255}, 0, 0.5)
	add_box(l, {t.x - 0.02, COUNTER_HEIGHT + 0.055, t.z - TABLET_W * 0.35}, {0.04, 0.11, 0.04}, COLOR_METAL, 0, 0.5)
	add_box(l, {t.x - 0.02, COUNTER_HEIGHT + 0.055, t.z + TABLET_W * 0.35}, {0.04, 0.11, 0.04}, COLOR_METAL, 0, 0.5)
	// A cup of brushes, past the palette.
	cz := c.z + 1.05
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

// The middle of the cradle under the balloon of the paint station.
paint_cradle :: proc() -> Vec3 {
	return {PAINT_CLAMP.x, PAINT_CLAMP.y - PAINT_DROP - PAINT_CRADLE_GAP, PAINT_CLAMP.z}
}

// Where the smoke leaves the chimney of the incinerator.
incinerator_vent :: proc() -> Vec3 {
	return {INCINERATOR.max_x - 0.12, 2.18, INCINERATOR.max_z - 0.1}
}

add_incinerator :: proc(l: ^Layout) {
	b := INCINERATOR
	cx := (b.min_x + b.max_x) * 0.5
	cz := (b.min_z + b.max_z) * 0.5
	w := b.max_x - b.min_x
	d := b.max_z - b.min_z
	top := INCINERATOR_TOP
	add_box(l, {cx, COUNTER_HEIGHT + 0.02, cz}, {w + 0.04, 0.04, d + 0.04}, COLOR_METAL, 0, 0.5) // the base lip
	add_box(l, {cx, (COUNTER_HEIGHT + 0.04 + top) * 0.5, cz}, {w, top - COUNTER_HEIGHT - 0.04, d}, {52, 56, 64, 255}, 0, 0.35) // the body

	// The hopper: four thin walls round the opening a balloon is dropped into, and the
	// fire glowing at the bottom of it.
	m := INCINERATOR_MOUTH
	h := INCINERATOR_HOPPER
	wall := f32(0.012)
	rim := m.y - top
	add_box(l, {m.x - h, top + rim * 0.5, m.z}, {wall, rim, 2 * h + wall}, COLOR_STEEL, 0, 0.8)
	add_box(l, {m.x + h, top + rim * 0.5, m.z}, {wall, rim, 2 * h + wall}, COLOR_STEEL, 0, 0.8)
	add_box(l, {m.x, top + rim * 0.5, m.z - h}, {2 * h + wall, rim, wall}, COLOR_STEEL, 0, 0.8)
	add_box(l, {m.x, top + rim * 0.5, m.z + h}, {2 * h + wall, rim, wall}, COLOR_STEEL, 0, 0.8)
	add_box(l, {m.x, top + 0.004, m.z}, {2 * h - 0.02, 0.008, 2 * h - 0.02}, {255, 110, 30, 255}, 1) // the fire

	// The door in front, facing the player at the counter: a dark panel with a glowing
	// slit, and a warning stripe above.
	add_box(l, {cx, 1.36, b.min_z - 0.005}, {0.38, 0.22, 0.012}, {30, 34, 42, 255}, 0, 0.6)
	add_box(l, {cx, 1.36, b.min_z - 0.012}, {0.28, 0.07, 0.006}, {255, 120, 40, 255}, 1)
	add_box(l, {cx, 1.52, b.min_z - 0.003}, {w - 0.1, 0.02, 0.008}, {210, 70, 30, 255}, 0.6)

	// The chimney, at the back.
	v := incinerator_vent()
	add_box(l, {v.x, top + (v.y - 0.04 - top) * 0.5, v.z}, {0.14, v.y - 0.04 - top, 0.14}, COLOR_METAL, 0, 0.5)
	add_box(l, {v.x, v.y - 0.02, v.z}, {0.2, 0.03, 0.2}, COLOR_STEEL, 0, 0.8)
}

// The color of swatch `k` of the palette. Swatch 0 is no paint, so the other 15 are
// the paints. These are stand-ins: the palette of the drawing is not decided.
palette_color :: proc(k: int) -> [4]u8 {
	table := [PALETTE_SIZE][4]u8 {
		{205, 215, 225, 255}, // 0 is no paint: the bare rubber, which is also the eraser
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

// Where the light at the tip of the spout is, which shows there is product to pour.
mixer_spout_light :: proc() -> Vec3 {
	return {MIXER_SPOUT.x, MIXER_SPOUT.y + 0.015, MIXER_SPOUT.z}
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
