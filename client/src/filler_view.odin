// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "filler_view.odin"
// ============================================================================

package main

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import bl "balloon"
import "carry"
import "chem"
import "lab"

STATION_FREQUENCY :: 4 // mesh detail of the balloon at the station, lower than in the balloon lab
STATION_SUBSTEPS :: 6
SLACK_FILL :: f32(0.55) // how full an empty balloon looks, as a share of its rest volume
AWAKE_TIME :: f32(1.5) // seconds the soft body keeps running after the fill last changed
EMPTY_TINT :: Vec3{0.85, 0.88, 0.95}

// The soft body of the balloon at the fill station, and what it takes to draw it
// at the size of the lab. The body is simulated at the size it was tuned for, about
// one unit across, with its tip pinned at the origin, and drawn scaled down and
// moved to the clamp. `scale` is chosen so that the balloon at its rest volume
// takes the volume of `BALLOON_REST_ML`, so how big it looks is how full it is.
Filler_View :: struct {
	balloon:    ^bl.Balloon,
	view:       Balloon_View,
	scale:      f32,
	generation: int, // the balloon of the station this body is standing in for
	awake:      f32, // seconds left to keep simulating
	last_fill:  f32,
}

// The fill the soft body is given for a fill ratio of the station: a limp balloon
// when empty, its natural size at 1, and as much as the station has above that.
view_fill :: proc(ratio: f32) -> f32 {
	if ratio <= 1 {
		return SLACK_FILL + (1 - SLACK_FILL) * max(ratio, 0)
	}
	return ratio
}

filler_view_init :: proc(fv: ^Filler_View, shader: rl.Shader, lit: bool) {
	fv.balloon = new(bl.Balloon)
	cfg := bl.default_config()
	cfg.frequency = STATION_FREQUENCY
	cfg.substeps = STATION_SUBSTEPS
	bl.init(fv.balloon, cfg)
	fv.balloon.floor_y = -1000 // it hangs in the air, with no floor to land on
	rest_m3 := carry.BALLOON_REST_ML * 1e-6
	fv.scale = math.pow(rest_m3 / fv.balloon.rest_volume, 1.0 / 3.0)
	view_init(&fv.view, fv.balloon, shader, lit)
	fv.view.hide_knot = true
	filler_view_reset(fv)
}

filler_view_unload :: proc(fv: ^Filler_View) {
	view_unload(&fv.view)
	free(fv.balloon)
	fv^ = {}
}

// Hangs a fresh balloon from the clamp, which is the origin of its own space, with
// its tip pinned there.
filler_view_reset :: proc(fv: ^Filler_View) {
	b := fv.balloon
	bl.reset(b, -b.rest_pos[bl.TIP])
	fv.last_fill = view_fill(0)
	bl.set_fill(b, fv.last_fill)
	bl.pin(b, bl.TIP, {0, 0, 0})
	bl.update_normals(b)
	view_update(&fv.view, b)
	fv.awake = AWAKE_TIME
}

// Brings the soft body up to the station: a new balloon when the station has
// clamped one, the fill it holds, and a step of the simulation while it is still
// moving. A balloon at rest, which is nearly always, costs nothing.
filler_view_update :: proc(fv: ^Filler_View, f: ^carry.Filler, dt: f32) {
	if f.generation != fv.generation {
		fv.generation = f.generation
		filler_view_reset(fv)
	}
	if !f.present {
		return
	}
	b := fv.balloon
	fill := view_fill(carry.fill_ratio(f))
	if abs(fill - fv.last_fill) > 0.001 {
		bl.set_fill(b, fill)
		fv.last_fill = fill
		fv.awake = AWAKE_TIME
	}
	fv.view.strain = carry.strain(f)
	if fv.awake > 0 {
		bl.pin(b, bl.TIP, {0, 0, 0})
		bl.step(b, min(dt, 1.0 / 60))
		bl.update_normals(b)
		view_update(&fv.view, b)
		fv.awake -= dt
	}
}

// Draws the balloon at the clamp, in the color of what it holds.
filler_view_draw :: proc(fv: ^Filler_View, f: ^carry.Filler, eye: Vec3) {
	if !f.present {
		return
	}
	o := lab.FILLER_CLAMP
	local_eye := (eye - Vec3{o.x, o.y, o.z}) / fv.scale
	tint := EMPTY_TINT
	if f.ml > 0 {
		tint = chem.compound_color(f.compound)
	}
	m := rl.Matrix(1)
	m[0, 0], m[1, 1], m[2, 2] = fv.scale, fv.scale, fv.scale
	m[0, 3], m[1, 3], m[2, 3] = o.x, o.y, o.z
	view_draw_at(&fv.view, local_eye, bl.normalize3(LIGHT_DIR), tint, m)
}

// A flat colored box, six faces of two triangles each, drawn without lighting.
draw_flat_box :: proc(c, size: Vec3, color: [4]u8) {
	h := size * 0.5
	p := [8]Vec3{
		{c.x - h.x, c.y - h.y, c.z - h.z},
		{c.x + h.x, c.y - h.y, c.z - h.z},
		{c.x + h.x, c.y + h.y, c.z - h.z},
		{c.x - h.x, c.y + h.y, c.z - h.z},
		{c.x - h.x, c.y - h.y, c.z + h.z},
		{c.x + h.x, c.y - h.y, c.z + h.z},
		{c.x + h.x, c.y + h.y, c.z + h.z},
		{c.x - h.x, c.y + h.y, c.z + h.z},
	}
	faces := [6][4]int{{0, 1, 2, 3}, {5, 4, 7, 6}, {4, 0, 3, 7}, {1, 5, 6, 2}, {3, 2, 6, 7}, {4, 5, 1, 0}}
	rlgl.Color4ub(color.r, color.g, color.b, color.a)
	for f in faces {
		a, b, d, e := p[f[0]], p[f[1]], p[f[2]], p[f[3]]
		rlgl.Vertex3f(a.x, a.y, a.z)
		rlgl.Vertex3f(b.x, b.y, b.z)
		rlgl.Vertex3f(d.x, d.y, d.z)
		rlgl.Vertex3f(a.x, a.y, a.z)
		rlgl.Vertex3f(d.x, d.y, d.z)
		rlgl.Vertex3f(e.x, e.y, e.z)
	}
}

gauge_rgb :: proc(c: carry.Gauge_Color) -> [4]u8 {
	switch c {
	case .Off:
		return {46, 54, 64, 255}
	case .Green:
		return {70, 220, 120, 255}
	case .Amber:
		return {245, 190, 50, 255}
	case .Red:
		return {245, 60, 50, 255}
	}
	return {46, 54, 64, 255}
}

// The lights of the gauge beside the clamp, and the glass of the fume hood. Both
// change from frame to frame, so they are drawn here and not with the room. Near the
// limit the red lights blink, which says the balloon is about to go.
stations_draw :: proc(f: ^carry.Filler) {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.TRIANGLES)

	ratio := carry.fill_ratio(f)
	blink := carry.strain(f) > 0.75 && i32(rl.GetTime() * 6) % 2 == 0
	for i in 0 ..< lab.GAUGE_LIGHTS {
		c := carry.gauge_color(ratio, i)
		if blink && c == .Red {
			c = .Off
		}
		draw_flat_box(lab.gauge_light(i), {0.07, 0.03, 0.012}, gauge_rgb(c))
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()

	// The glass comes last, blended, and writes no depth.
	rlgl.DisableDepthMask()
	rlgl.Begin(rlgl.TRIANGLES)
	h := lab.HOOD
	mid_x := (h.min_x + h.max_x) * 0.5
	mid_y := (lab.HOOD_GLASS_LOW + lab.HOOD_TOP) * 0.5
	draw_flat_box({mid_x, mid_y, lab.HOOD_GLASS_Z}, {h.max_x - h.min_x - 0.1, lab.HOOD_TOP - lab.HOOD_GLASS_LOW, 0.01}, {170, 215, 235, 46})
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	rlgl.EnableBackfaceCulling()
}
