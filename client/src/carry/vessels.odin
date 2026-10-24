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

// The stock liquids. These are a stand-in with fictional names and plain
// colors, until the compound database exists as DixScript content. Id 0 means
// empty, and the ids are what the wire format carries.
Stock :: enum u16 {
	None,
	Water,
	Fizz_Acid,
	Soda_Base,
	Ember_Oil,
	Spark_Blue,
	Frost_Gel,
	Glue_Goo,
	Slick,
	Dye_Red,
	Dye_Violet,
}

Compound :: struct {
	name:  string,
	color: [3]u8,
}

STOCK_LIQUIDS :: [?]Compound {
	{"Water", {120, 185, 235}},
	{"Fizz Acid", {170, 230, 70}},
	{"Soda Base", {235, 150, 220}},
	{"Ember Oil", {240, 128, 40}},
	{"Spark Blue", {60, 140, 255}},
	{"Frost Gel", {170, 235, 245}},
	{"Glue Goo", {240, 220, 110}},
	{"Slick", {96, 74, 120}},
	{"Dye Red", {225, 50, 60}},
	{"Dye Violet", {140, 70, 220}},
}

compound_name :: proc(id: u16) -> string {
	table := STOCK_LIQUIDS
	if id == 0 || int(id) > len(table) {
		return "Empty"
	}
	return table[id - 1].name
}

// The color of a liquid as red, green, and blue between 0 and 1.
compound_color :: proc(id: u16) -> [3]f32 {
	table := STOCK_LIQUIDS
	if id == 0 || int(id) > len(table) {
		return {1, 1, 1}
	}
	c := table[id - 1].color
	return {f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255}
}

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
