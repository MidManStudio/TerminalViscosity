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

// The height of the liquid surface in the world, tilt included.
liquid_level :: proc(pr: ^Prop) -> f32 {
	return pr.pos.y + fill_level_tilted(pr.kind, pr.ml, pr.tilt)
}

// Liquid in a vessel that is tilted over: where its surface is, how much it can
// hold before it spills over the lip, and where the lip is. The surface of a
// liquid is always level in the world, so a tilted vessel is cut by a flat
// plane, and the amount below the plane is worked out by adding up slices
// across the inside. The vessel tilts about its middle toward a horizontal
// direction, and the tilt is in radians, 0 upright and more than 1.5 on its side.

TILT_SLICES :: 32

// The inside of a vessel cut into slices across its axis: the radius of each,
// the height of the first, and the thickness.
Slices :: struct {
	r:  [TILT_SLICES]f32,
	h0: f32,
	dh: f32,
}

// Radius of the inside at a height above the base, from the inside outline.
interior_radius_at :: proc(k: Kind, h: f32) -> f32 {
	profile: [MAX_PROFILE][2]f32
	n := interior_profile(k, &profile)
	for i in 0 ..< n - 1 {
		a, b := profile[i], profile[i + 1]
		if b.y > a.y && h >= a.y && h <= b.y {
			return a.x + (b.x - a.x) * (h - a.y) / (b.y - a.y)
		}
	}
	return 0
}

mouth_radius :: proc(k: Kind) -> f32 {
	profile: [MAX_PROFILE][2]f32
	n := interior_profile(k, &profile)
	return profile[n - 1].x
}

slices_of :: proc(k: Kind) -> Slices {
	sl: Slices
	sl.h0 = VESSEL_WALL
	sl.dh = (brim_height(k) - VESSEL_WALL) / TILT_SLICES
	for i in 0 ..< TILT_SLICES {
		sl.r[i] = interior_radius_at(k, sl.h0 + (f32(i) + 0.5) * sl.dh)
	}
	return sl
}

// The area of the part of a disc of radius r that lies at or below x = c.
area_below :: proc(r, c: f32) -> f32 {
	if r <= 0 || c <= -r {
		return 0
	}
	if c >= r {
		return math.PI * r * r
	}
	return r * r * math.acos(-c / r) + c * math.sqrt(r * r - c * c)
}

// The liquid, in millilitres, that lies below a level plane `plane` metres above
// the middle of the base, in a vessel tilted by `tilt`. Points on the side of the
// lip are lower, and the height of a point at a distance `x` toward the lip
// and a height `h` up the axis is h cos(tilt) minus x sin(tilt).
volume_in_slices :: proc(sl: ^Slices, tilt, plane: f32) -> f32 {
	cos_t, sin_t := math.cos(tilt), math.sin(tilt)
	total := f32(0)
	for i in 0 ..< TILT_SLICES {
		h := sl.h0 + (f32(i) + 0.5) * sl.dh
		d := plane - h * cos_t
		c := f32(0)
		if abs(sin_t) < 1e-5 {
			c = d >= 0 ? 1e6 : -1e6
		} else {
			c = d / sin_t
		}
		total += area_below(sl.r[i], c)
	}
	return total * sl.dh * 1e6
}

// Height of the liquid surface above the middle of the base, for `ml` in a
// vessel tilted by `tilt`, found by halving the range.
fill_level_tilted :: proc(k: Kind, ml, tilt: f32) -> f32 {
	if tilt < 1e-3 {
		return fill_height(k, ml)
	}
	sl := slices_of(k)
	radius := kind_dims(k).radius
	sin_t, cos_t := math.sin(tilt), math.cos(tilt)
	lo := -radius * sin_t - 0.01
	hi := radius * sin_t + brim_height(k) * max(cos_t, 0) + 0.01
	for _ in 0 ..< 24 {
		mid := (lo + hi) * 0.5
		if volume_in_slices(&sl, tilt, mid) < ml {
			lo = mid
		} else {
			hi = mid
		}
	}
	return (lo + hi) * 0.5
}

// The most liquid a vessel tilted by `tilt` can hold before it runs over the
// lowest point of the rim: what lies below a level plane through that point.
capacity_at_tilt :: proc(k: Kind, tilt: f32) -> f32 {
	if tilt < 1e-3 {
		return capacity_ml(k)
	}
	sl := slices_of(k)
	lip_y := brim_height(k) * math.cos(tilt) - mouth_radius(k) * math.sin(tilt)
	return min(volume_in_slices(&sl, tilt, lip_y), capacity_ml(k))
}

// The axis of a vessel tilted toward the horizontal direction `d`, pointing
// from the base to the mouth, and the direction from the middle of the rim to
// its lowest point.
tilt_axis :: proc(d: Vec3, tilt: f32) -> (axis, down: Vec3) {
	s, c := math.sin(tilt), math.cos(tilt)
	return {d.x * s, c, d.z * s}, {d.x * c, -s, d.z * c}
}

// Where the lowest point of the rim is, from the middle of the base.
lip_offset :: proc(k: Kind, tilt: f32, d: Vec3) -> Vec3 {
	axis, down := tilt_axis(d, tilt)
	return axis * brim_height(k) + down * mouth_radius(k)
}
