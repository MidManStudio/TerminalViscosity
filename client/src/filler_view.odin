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

// One soft-body balloon at the size of the lab. The body is simulated at the size
// it was tuned for, about one unit across, with its tip pinned at the origin, and
// drawn scaled down and moved to where it hangs. `scale` is chosen so that the rest
// volume of the soft body takes the volume of `BALLOON_REST_ML`, so how big the
// balloon looks is how full it is. The fill station, the hand, the paint station,
// and each hook of the loadout rack have one.
Balloon_Body :: struct {
	balloon:   ^bl.Balloon,
	view:      Balloon_View,
	scale:     f32,
	awake:     f32, // seconds left to keep simulating
	last_fill: f32,
	hanging:   bool, // a balloon has been hung in it since it was last empty
	art:       Art_Texture, // the drawing it wears, if it has one
}

// The fill the soft body is given for a fill ratio of the balloon: a limp balloon
// when empty, its natural size at 1, and as much as the balloon has above that.
view_fill :: proc(ratio: f32) -> f32 {
	if ratio <= 1 {
		return SLACK_FILL + (1 - SLACK_FILL) * max(ratio, 0)
	}
	return ratio
}

// `pin_speed` is how fast the neck may follow the hand, in the units of the soft
// body a second, and `shared` says the shader belongs to another body.
body_init :: proc(b: ^Balloon_Body, shader: rl.Shader, lit: bool, shared: bool, pin_speed: f32) {
	b.balloon = new(bl.Balloon)
	cfg := bl.default_config()
	cfg.frequency = STATION_FREQUENCY
	cfg.substeps = STATION_SUBSTEPS
	bl.init(b.balloon, cfg)
	b.balloon.floor_y = -1000 // it hangs in the air, with no floor to land on
	b.balloon.pin_speed = pin_speed
	rest_m3 := carry.BALLOON_REST_ML * 1e-6
	b.scale = math.pow(rest_m3 / b.balloon.rest_volume, 1.0 / 3.0)
	view_init(&b.view, b.balloon, shader, lit)
	b.view.hide_knot = true
	b.view.shares_shader = shared
	body_reset(b, 0)
}

body_unload :: proc(b: ^Balloon_Body) {
	art_texture_unload(&b.art)
	view_unload(&b.view)
	free(b.balloon)
	b^ = {}
}

// Hangs a fresh balloon from its tip, which is the origin of its own space, filled
// to `ratio` of its rest volume.
body_reset :: proc(b: ^Balloon_Body, ratio: f32) {
	bal := b.balloon
	bl.reset(bal, -bal.rest_pos[bl.TIP])
	b.last_fill = view_fill(ratio)
	bl.set_fill(bal, b.last_fill)
	bl.pin(bal, bl.TIP, {0, 0, 0})
	bl.update_normals(bal)
	view_update(&b.view, bal)
	b.awake = AWAKE_TIME
	b.hanging = true
}

// Moves the soft body so that it stays where it is in the world when the point it
// hangs from has moved by `d` metres: the body is drawn at that point, so it would
// otherwise be carried along rigidly, and a balloon in the hand would not swing.
body_shift :: proc(b: ^Balloon_Body, d: Vec3) {
	bal := b.balloon
	local := -d / b.scale
	for i in 0 ..< bal.vert_count {
		bal.pos[i] += local
		bal.prev[i] += local
	}
	bal.pin_pos += local
}

// Runs the soft body for a frame: the fill it should have, how far it hangs from a
// point that has moved by `moved` metres, and a step of the simulation while it is
// still moving. A balloon at rest costs nothing, and one that is carried is always
// moving. `strain` is how near a burst it is, for the rubber.
body_step :: proc(b: ^Balloon_Body, ratio, strain, dt: f32, moved: Vec3) {
	bal := b.balloon
	fill := view_fill(ratio)
	if abs(fill - b.last_fill) > 0.001 {
		bl.set_fill(bal, fill)
		b.last_fill = fill
		b.awake = AWAKE_TIME
	}
	if moved != {} {
		body_shift(b, moved)
		b.awake = AWAKE_TIME
	}
	b.view.strain = strain
	if b.awake > 0 {
		bl.pin(bal, bl.TIP, {0, 0, 0})
		bl.step(bal, min(dt, 1.0 / 60))
		bl.update_normals(bal)
		view_update(&b.view, bal)
		b.awake -= dt
	}
}

// Puts drawing `id` of the store on the balloon, or takes the drawing off if there
// is none, and keeps the texture up to date with it.
body_art :: proc(b: ^Balloon_Body, store: ^carry.Art_Store, id: u16, scratch: []u8) {
	if art_texture_sync(&b.art, store, id, scratch) {
		view_set_art(&b.view, b.art.tex)
	} else {
		view_clear_art(&b.view)
	}
}

// Draws the balloon hanging from `origin`, in the color `tint`.
body_draw :: proc(b: ^Balloon_Body, origin, eye, tint: Vec3) {
	local_eye := (eye - origin) / b.scale
	m := rl.Matrix(1)
	m[0, 0], m[1, 1], m[2, 2] = b.scale, b.scale, b.scale
	m[0, 3], m[1, 3], m[2, 3] = origin.x, origin.y, origin.z
	view_draw_at(&b.view, local_eye, bl.normalize3(LIGHT_DIR), tint, m)
}

// The balloon of the fill station.
Filler_View :: struct {
	body:       Balloon_Body,
	generation: int, // the balloon of the station this body is standing in for
}

filler_view_init :: proc(fv: ^Filler_View, shader: rl.Shader, lit: bool) {
	body_init(&fv.body, shader, lit, false, 40)
}

filler_view_unload :: proc(fv: ^Filler_View) {
	body_unload(&fv.body)
	fv^ = {}
}

// Brings the soft body up to the station: a new balloon when the station has
// clamped one, the fill it holds, and a step of the simulation while it is still
// moving.
filler_view_update :: proc(fv: ^Filler_View, f: ^carry.Filler, dt: f32) {
	if f.generation != fv.generation {
		fv.generation = f.generation
		body_reset(&fv.body, 0)
	}
	if !f.present {
		return
	}
	body_step(&fv.body, carry.fill_ratio(f), carry.strain(f), dt, {})
}

// The color a balloon is drawn in: that of what it holds, or a pale one when empty.
balloon_tint :: proc(compound: u16, ml: f32) -> Vec3 {
	if ml > 0 {
		return chem.compound_color(compound)
	}
	return EMPTY_TINT
}

// Draws the balloon at the clamp, in the color of what it holds.
filler_view_draw :: proc(fv: ^Filler_View, f: ^carry.Filler, eye: Vec3) {
	if !f.present {
		return
	}
	body_draw(&fv.body, lab.FILLER_CLAMP, eye, balloon_tint(f.compound, f.ml))
}

// The balloons the player has apart from the one at the fill station: the one in the
// hand, the one in the paint station, and one for each hook of the loadout rack. A
// body is made ready when an item arrives in its place, and costs nothing while
// the place is empty, or while the balloon in it is at rest.
Loadout_View :: struct {
	hand:        Balloon_Body,
	paint:       Balloon_Body,
	slots:       [carry.LOADOUT_SLOTS]Balloon_Body,
	hand_on:     bool,
	paint_on:    bool,
	slots_on:    [carry.LOADOUT_SLOTS]bool,
	hand_origin: Vec3, // where the hand body hung last frame
	scratch:     []u8, // room to turn a drawing into pixels in
}

// Every body shares the shader of the fill station, which is the one that owns it.
loadout_view_init :: proc(lv: ^Loadout_View, shader: rl.Shader, lit: bool) {
	body_init(&lv.hand, shader, lit, true, 400) // a hand moves faster than a clamp, so the neck follows faster
	body_init(&lv.paint, shader, lit, true, 40)
	for &s in lv.slots {
		body_init(&s, shader, lit, true, 40)
	}
	lv.scratch = art_scratch_alloc()
}

loadout_view_unload :: proc(lv: ^Loadout_View) {
	body_unload(&lv.hand)
	body_unload(&lv.paint)
	for &s in lv.slots {
		body_unload(&s)
	}
	art_scratch_free(lv.scratch)
	lv^ = {}
}

// Where a balloon in the hand hangs from: in front of the player, a little to the
// right, and level with the hold point of a vessel.
hand_origin :: proc(v: carry.View) -> Vec3 {
	return v.eye + (-v.back) * 0.55 + v.right * 0.17 - v.up * 0.05
}

// Gets each body ready when its item arrives and runs it. The one in the hand is moved
// with the hand, and starts afresh if the hand has jumped, as after a reset.
loadout_view_update :: proc(lv: ^Loadout_View, lo: ^carry.Loadout, store: ^carry.Art_Store, v: carry.View, dt: f32) {
	place :: proc(b: ^Balloon_Body, on: ^bool, item: carry.Item, store: ^carry.Art_Store, scratch: []u8, dt: f32, moved: Vec3) {
		if !item.used {
			on^ = false
			return
		}
		ratio := item.ml / carry.BALLOON_REST_ML
		if !on^ {
			on^ = true
			body_reset(b, ratio)
		}
		body_step(b, ratio, 0, dt, moved)
		body_art(b, store, item.art, scratch)
	}
	origin := hand_origin(v)
	moved := lv.hand_on ? origin - lv.hand_origin : Vec3{}
	if moved.x * moved.x + moved.y * moved.y + moved.z * moved.z > 0.36 { // 0.6 m in a frame is a jump
		moved = {}
		lv.hand_on = false
	}
	place(&lv.hand, &lv.hand_on, lo.hand, store, lv.scratch, dt, moved)
	lv.hand_origin = origin
	place(&lv.paint, &lv.paint_on, lo.paint, store, lv.scratch, dt, {})
	for i in 0 ..< carry.LOADOUT_SLOTS {
		place(&lv.slots[i], &lv.slots_on[i], lo.slots[i], store, lv.scratch, dt, {})
	}
}

loadout_view_draw :: proc(lv: ^Loadout_View, lo: ^carry.Loadout, eye: Vec3, show_hand: bool) {
	if show_hand && lo.hand.used && lv.hand_on {
		body_draw(&lv.hand, lv.hand_origin, eye, balloon_tint(lo.hand.compound, lo.hand.ml))
	}
	if lo.paint.used && lv.paint_on {
		body_draw(&lv.paint, lab.PAINT_CLAMP, eye, balloon_tint(lo.paint.compound, lo.paint.ml))
	}
	for i in 0 ..< carry.LOADOUT_SLOTS {
		if lo.slots[i].used && lv.slots_on[i] {
			body_draw(&lv.slots[i], lab.slot_clamp(i), eye, balloon_tint(lo.slots[i].compound, lo.slots[i].ml))
		}
	}
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

// The lights of the gauge beside the clamp, the lights over the hooks of the loadout rack, and the glass of the fume hood. Both
// change from frame to frame, so they are drawn here and not with the room. Near the
// limit the red lights blink, which says the balloon is about to go.
stations_draw :: proc(f: ^carry.Filler, lo: ^carry.Loadout) {
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
	// A light over each hook of the loadout rack: the color of what hangs on it.
	for i in 0 ..< carry.LOADOUT_SLOTS {
		color := gauge_rgb(.Off)
		if lo.slots[i].used {
			c := chem.compound_color(lo.slots[i].compound)
			color = {u8(c.r * 255), u8(c.g * 255), u8(c.b * 255), 255}
		}
		draw_flat_box(lab.slot_light(i), {0.12, 0.04, 0.012}, color)
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

// The screen of the tablet beside the paint station: bare rubber color with the drawing
// on it when a balloon is clamped, so it shows what the balloon wears, and dark and
// blank when there is none. It is a flat picture on the wall side of the counter, facing east.
tablet_draw :: proc(lv: ^Loadout_View, lo: ^carry.Loadout) {
	c := lab.TABLET_CENTER
	hw, hh := lab.TABLET_W * 0.5, lab.TABLET_H * 0.5
	// Seen from the east, the left edge is the south one, so the drawing starts there.
	tl, tr := Vec3{c.x, c.y + hh, c.z + hw}, Vec3{c.x, c.y + hh, c.z - hw}
	bl_, br := Vec3{c.x, c.y - hh, c.z + hw}, Vec3{c.x, c.y - hh, c.z - hw}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.TRIANGLES)
	back := lo.paint.used ? lab.palette_color(0) : [4]u8{34, 40, 52, 255}
	rlgl.Color4ub(back.r, back.g, back.b, 255)
	for p in ([6]Vec3{tl, tr, br, tl, br, bl_}) {
		rlgl.Vertex3f(p.x, p.y, p.z)
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	if lo.paint.used && lv.paint.art.loaded && lv.paint.art.art_id != 0 {
		rlgl.SetTexture(lv.paint.art.tex.id)
		rlgl.Begin(rlgl.TRIANGLES)
		rlgl.Color4ub(255, 255, 255, 255)
		corners := [6]struct {
			p:    Vec3,
			u, v: f32,
		}{{tl, 0, 0}, {tr, 1, 0}, {br, 1, 1}, {tl, 0, 0}, {br, 1, 1}, {bl_, 0, 1}}
		for k in corners {
			rlgl.TexCoord2f(k.u, k.v)
			rlgl.Vertex3f(k.p.x + 0.001, k.p.y, k.p.z)
		}
		rlgl.End()
		rlgl.DrawRenderBatchActive()
		rlgl.SetTexture(0)
	}
	rlgl.EnableBackfaceCulling()
}
