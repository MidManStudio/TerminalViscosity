// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "bench.odin"
// ============================================================================

package lab

// The bench: a row of spots on the north counter where the stations that can be moved stand. A station is a
// hot plate, an ice bath or a scale; each spot holds one or none. Where a station stands is where its footprint
// is, and everything that depends on it, the heat of the plate, the cold of the bath, the weighing of the scale and
// the height of its plate, reads the bench and not a place that is fixed. Units are metres.

BENCH_SPOTS :: 6

Bench_Kind :: enum u8 {
	None,
	Hot_Plate,
	Ice_Bath,
	Scale,
}

// What stands at each spot.
Bench :: struct {
	spots: [BENCH_SPOTS]Bench_Kind,
}

// Where spot `i` is along the counter: the middle of a station standing there. They are 1 to 1.3 m apart, which
// is room for the widest station, the ice bath, with a hand between, and clear of the fume hood to the west
// and the oven to the east.
bench_spot_x :: proc(i: int) -> f32 {
	xs := [BENCH_SPOTS]f32{-4.5, -3.5, -2.4, -1.2, 0.0, 1.2}
	return xs[clamp(i, 0, BENCH_SPOTS - 1)]
}

// The bench as the lab starts: the hot plate, the ice bath and the scale where they have always been.
default_bench :: proc() -> Bench {
	b: Bench
	b.spots[1] = .Hot_Plate
	b.spots[2] = .Ice_Bath
	b.spots[4] = .Scale
	return b
}

// The footprint of a station of this kind standing at spot `i`: what a vessel's middle has to be inside to be on
// it. For a scale it is the plate. An empty spot has a footprint too, which is its place on the counter.
bench_rect :: proc(kind: Bench_Kind, i: int) -> Rect {
	x := bench_spot_x(i)
	switch kind {
	case .Hot_Plate:
		return {x - 0.3, -7.88, x + 0.3, -7.38}
	case .Ice_Bath:
		return {x - 0.4, -7.88, x + 0.4, -7.38}
	case .Scale:
		return {x - 0.2, -7.8, x + 0.2, -7.45}
	case .None:
	}
	return {x - 0.25, -7.85, x + 0.25, -7.41}
}

// Whether the point (x, z) is on a station of this kind anywhere on the bench.
on_bench :: proc(b: ^Bench, kind: Bench_Kind, x, z: f32) -> bool {
	for i in 0 ..< BENCH_SPOTS {
		if b.spots[i] == kind && in_rect(bench_rect(kind, i), x, z) {
			return true
		}
	}
	return false
}

// The box that the crosshair is tested against for a station of this kind at spot `i`: its footprint, and as
// high as the station is.
bench_aim_box :: proc(kind: Bench_Kind, i: int) -> (low, high: Vec3) {
	x := bench_spot_x(i)
	switch kind {
	case .Hot_Plate:
		return {x - 0.3, COUNTER_HEIGHT, -7.88}, {x + 0.3, COUNTER_HEIGHT + 0.07, -7.38}
	case .Ice_Bath:
		return {x - 0.4, COUNTER_HEIGHT, -7.9}, {x + 0.4, COUNTER_HEIGHT + 0.09, -7.36}
	case .Scale:
		return {x - 0.26, COUNTER_HEIGHT, -7.86}, {x + 0.26, COUNTER_HEIGHT + 0.22, -7.4}
	case .None:
	}
	return {x, COUNTER_HEIGHT, -7.63}, {x, COUNTER_HEIGHT, -7.63}
}

// Adds the boxes of the bench: each station where it stands, and a dark plate at each spot that has none, so that
// the player can see where one goes.
add_bench :: proc(l: ^Layout, bench: Bench) {
	for i in 0 ..< BENCH_SPOTS {
		r := bench_rect(bench.spots[i], i)
		switch bench.spots[i] {
		case .Hot_Plate:
			add_hot_plate(l, r)
		case .Ice_Bath:
			add_ice_bath(l, r)
		case .Scale:
			add_scale(l, r)
		case .None:
			add_box(l, {(r.min_x + r.max_x) * 0.5, COUNTER_HEIGHT + 0.004, (r.min_z + r.max_z) * 0.5}, {r.max_x - r.min_x, 0.008, r.max_z - r.min_z}, {44, 50, 60, 255}, 0, 0.3) // an empty spot
		}
	}
}

add_hot_plate :: proc(l: ^Layout, h: Rect) {
	cx, cz := (h.min_x + h.max_x) * 0.5, (h.min_z + h.max_z) * 0.5
	add_box(l, {cx, COUNTER_HEIGHT + 0.02, cz}, {h.max_x - h.min_x, 0.04, h.max_z - h.min_z}, {50, 54, 62, 255}, 0, 0.4)
	add_box(l, {cx, COUNTER_HEIGHT + 0.043, cz}, {h.max_x - h.min_x - 0.12, 0.012, h.max_z - h.min_z - 0.12}, {255, 96, 40, 255}, 1) // the coil, glowing
}

add_ice_bath :: proc(l: ^Layout, b: Rect) {
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

add_scale :: proc(l: ^Layout, p: Rect) {
	cx, cz := (p.min_x + p.max_x) * 0.5, (p.min_z + p.max_z) * 0.5
	w, d := p.max_x - p.min_x, p.max_z - p.min_z
	add_box(l, {cx, COUNTER_HEIGHT + 0.02, cz}, {w + 0.1, 0.04, d + 0.1}, COLOR_METAL, 0, 0.5) // the body
	add_box(l, {cx, COUNTER_HEIGHT + SCALE_PLATE_TOP - 0.015, cz}, {w, 0.03, d}, COLOR_STEEL, 0, 0.9) // the plate
	add_box(l, {cx, COUNTER_HEIGHT + 0.025, p.max_z + 0.055}, {0.2, 0.035, 0.012}, {16, 20, 26, 255}, 0, 0.6) // the display, on the front
	add_box(l, {cx, COUNTER_HEIGHT + 0.025, p.max_z + 0.062}, {0.14, 0.012, 0.004}, COLOR_GLOW, 1) // and its light
}
