// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "vessels.odin"
// ============================================================================

package carry

import "core:math"

MAX_PROFILE :: 12

// Fractions of a vessel's footprint radius and height that fix its outline.
FLASK_NECK :: f32(0.28) // neck radius, as a fraction of the radius
FLASK_SHOULDER :: f32(0.62) // height where the cone meets the neck
BOTTLE_NECK :: f32(0.42)
BOTTLE_BODY :: f32(0.58) // height where the straight body ends
BOTTLE_SHOULDER :: f32(0.78) // height where the shoulder meets the neck
BOTTLE_NECK_TOP :: f32(0.86) // height of the mouth, under the cap

// The outline of the space inside a vessel that liquid can fill, from the
// middle of the floor up to the brim, as (radius, height) pairs. Returns how
// many points.
interior_profile :: proc(k: Kind, out: ^[MAX_PROFILE][2]f32) -> int {
	d := kind_dims(k)
	r, h, t := d.radius, d.height, VESSEL_WALL
	switch k {
	case .Beaker:
		out[0], out[1], out[2] = {0, t}, {r - t, t}, {r - t, h}
		return 3
	case .Flask:
		nr := r * FLASK_NECK
		out[0], out[1], out[2], out[3] = {0, t}, {r - t, t}, {nr - t, h * FLASK_SHOULDER}, {nr - t, h}
		return 4
	case .Bottle:
		nr := r * BOTTLE_NECK
		out[0], out[1], out[2] = {0, t}, {r - t, t}, {r - t, h * BOTTLE_BODY}
		out[3], out[4] = {nr - t, h * BOTTLE_SHOULDER}, {nr - t, h * BOTTLE_NECK_TOP}
		return 5
	}
	return 0
}

// How much liquid fills a vessel up to `height` above its base, in millilitres.
// Each step of the interior outline is a slice of a cone, so the sum is exact.
interior_volume :: proc(k: Kind, height: f32) -> f32 {
	profile: [MAX_PROFILE][2]f32
	n := interior_profile(k, &profile)
	total := f32(0)
	for i in 0 ..< n - 1 {
		a, b := profile[i], profile[i + 1]
		if b.y <= a.y || height <= a.y {
			continue
		}
		top := min(height, b.y)
		r_top := a.x + (b.x - a.x) * (top - a.y) / (b.y - a.y)
		total += math.PI * (top - a.y) / 3 * (a.x * a.x + a.x * r_top + r_top * r_top)
	}
	return total * 1e6
}

brim_height :: proc(k: Kind) -> f32 {
	profile: [MAX_PROFILE][2]f32
	n := interior_profile(k, &profile)
	return profile[n - 1].y
}

// How much a vessel holds when full, in millilitres, from its shape.
capacity_ml :: proc(k: Kind) -> f32 {
	return interior_volume(k, brim_height(k))
}

// How high liquid stands above the base of the vessel for a given amount, found
// by halving the range, since the volume only ever grows with the height.
fill_height :: proc(k: Kind, ml: f32) -> f32 {
	lo := VESSEL_WALL
	hi := brim_height(k)
	if ml <= 0 {
		return lo
	}
	if ml >= capacity_ml(k) {
		return hi
	}
	for _ in 0 ..< 24 {
		mid := (lo + hi) * 0.5
		if interior_volume(k, mid) < ml {
			lo = mid
		} else {
			hi = mid
		}
	}
	return (lo + hi) * 0.5
}

// The height of the liquid surface in the world, for a vessel standing upright.
liquid_level :: proc(pr: ^Prop) -> f32 {
	return pr.pos.y + fill_height(pr.kind, pr.ml)
}
