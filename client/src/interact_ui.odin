// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "interact_ui.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import "carry"
import "chem"
import "core:fmt"
import "core:strconv"

// One rounded box of a hand icon, in a unit square with y pointing down.
// `shade` darkens the box so a thumb can be told apart from the fist.
Icon_Box :: struct {
	x, y, w, h: f32,
	shade:      f32,
}

ICON_OPEN :: [?]Icon_Box {
	{0.22, 0.50, 0.56, 0.42, 1}, // palm
	{0.22, 0.14, 0.115, 0.42, 1}, // index
	{0.345, 0.06, 0.115, 0.50, 1}, // middle
	{0.47, 0.12, 0.115, 0.46, 1}, // ring
	{0.595, 0.24, 0.115, 0.34, 1}, // little
	{0.04, 0.54, 0.26, 0.13, 1}, // thumb, out to the side
}

ICON_CLOSED :: [?]Icon_Box {
	{0.20, 0.32, 0.60, 0.52, 1}, // fist
	{0.20, 0.20, 0.14, 0.24, 1}, // knuckles
	{0.355, 0.17, 0.14, 0.27, 1},
	{0.51, 0.19, 0.14, 0.25, 1},
	{0.66, 0.24, 0.14, 0.20, 1},
	{0.26, 0.60, 0.40, 0.15, 0.78}, // thumb across the front
}

// The grab button, in the bottom right corner. A finger that lands on it does
// not move or look.
grab_button :: proc(w, h: f32) -> [4]f32 {
	size := max(f32(64), h * 0.13)
	return {w - size * 1.8 - 24, h - size - 24, size * 1.8, size}
}

// The jump button, just above the grab button and as wide as it.
jump_button :: proc(w, h: f32) -> [4]f32 {
	g := grab_button(w, h)
	height := g.w * 0.8
	return {g.x, g.y - height - 16, g.z, height}
}

// The pour button, just left of the grab button. It says "mix" when the held
// vessel can be poured into the one under the crosshair, "fill" under a tap, and
// "pour" otherwise.
pour_button :: proc(w, h: f32) -> [4]f32 {
	g := grab_button(w, h)
	return {g.x - g.z - 16, g.y, g.z, g.w}
}

// The button that opens the liquid sim test, just under the scene switch.
bench_button :: proc(w, h: f32) -> [4]f32 {
	b := switch_button(w, h)
	return {b.x, b.y + b.w + 12, b.z, b.w}
}

// A button on a dark backing with a bright edge and a shadowed label, so it
// reads on the light walls and floor as well as on the dark counters.
draw_button :: proc(b: [4]f32, label: cstring, fill, edge, ink: rl.Color) {
	rect := rl.Rectangle{b.x, b.y, b.z, b.w}
	rl.DrawRectangleRounded(rect, 0.3, 8, fill)
	rl.DrawRectangleRoundedLinesEx(rect, 0.3, 8, 3, edge)
	font := i32(min(b.z / 5, b.w * 0.34))
	x := i32(b.x + b.z * 0.5) - rl.MeasureText(label, font) / 2
	y := i32(b.y + b.w * 0.5) - font / 2
	rl.DrawText(label, x + 1, y + 2, font, {0, 0, 0, 220})
	rl.DrawText(label, x, y, font, ink)
}

// The button says "grab" until something is held, and then "release". It is
// dimmer when there is nothing within reach to grab.
draw_grab_button :: proc(w, h: f32, state: carry.State) {
	label: cstring = "grab"
	fill := rl.Color{10, 18, 28, 150}
	edge := rl.Color{200, 210, 222, 120}
	ink := rl.Color{200, 210, 222, 170}
	switch state {
	case .Idle:
	case .Reaching:
		fill, edge, ink = {10, 44, 50, 215}, {60, 230, 215, 255}, rl.RAYWHITE
	case .Holding:
		label = "release"
		fill, edge, ink = {14, 74, 74, 230}, {60, 230, 215, 255}, rl.RAYWHITE
	}
	draw_button(grab_button(w, h), label, fill, edge, ink)
}

// The jump button is dimmer while the player is already in the air.
draw_jump_button :: proc(w, h: f32, airborne: bool) {
	fill := rl.Color{10, 18, 28, 190}
	edge := rl.Color{230, 236, 242, 220}
	ink := rl.RAYWHITE
	if airborne {
		fill, edge, ink = {10, 18, 28, 120}, {200, 210, 222, 100}, {200, 210, 222, 150}
	}
	draw_button(jump_button(w, h), "jump", fill, edge, ink)
}

// Writes what a vessel holds into a buffer on the stack, such as
// "Dye Red  400 / 935 ml", so nothing is allocated each frame.
contents_text :: proc(buf: ^[96]u8, pr: ^carry.Prop) -> cstring {
	n := 0
	put :: proc(buf: []u8, n: ^int, text: string) {
		for c in transmute([]u8)text {
			if n^ < len(buf) - 1 {
				buf[n^] = c
				n^ += 1
			}
		}
	}
	digits: [24]u8
	put(buf[:], &n, chem.compound_name(pr.compound))
	if pr.compound != 0 {
		put(buf[:], &n, "  ")
		put(buf[:], &n, strconv.write_int(digits[:], i64(pr.ml + 0.5), 10))
		put(buf[:], &n, " / ")
		put(buf[:], &n, strconv.write_int(digits[:], i64(carry.capacity_ml(pr.kind) + 0.5), 10))
		put(buf[:], &n, " ml")
	}
	if word := carry.heat_word(pr.heat); pr.compound != 0 && word != "" {
		put(buf[:], &n, ", ")
		put(buf[:], &n, word)
	}
	buf[n] = 0
	return cstring(raw_data(buf[:]))
}

draw_text_centered :: proc(text: cstring, cx, y, font: i32, color: rl.Color) {
	x := cx - rl.MeasureText(text, font) / 2
	rl.DrawText(text, x + 1, y + 2, font, {0, 0, 0, 220})
	rl.DrawText(text, x, y, font, color)
}

// Lines under the hand icon: what the vessel in view or in hand holds and how
// full it is, and, with something held over another vessel, what is in the one
// it would be poured into.
draw_contents :: proc(w, h: f32, pr: ^carry.Prop, target: ^carry.Prop) {
	buf: [96]u8
	font := i32(max(f32(16), h * 0.032))
	cx := i32(w * 0.5)
	y := i32(h * 0.5) + i32(max(f32(30), h * 0.075)) + 24
	draw_text_centered(contents_text(&buf, pr), cx, y, font, rl.RAYWHITE)
	if target != nil {
		draw_text_centered("pour into", cx, y + font + font / 3, font * 3 / 4, {60, 230, 215, 255})
		draw_text_centered(contents_text(&buf, target), cx, y + 2 * (font + font / 3) - font / 4, font, {60, 230, 215, 255})
	}
}

// Draws a hand icon with its top left corner at (x, y) and `size` pixels
// across: a dark outline first, then the fill, so it reads on any background.
draw_icon :: proc(boxes: []Icon_Box, x, y, size: f32, fill: rl.Color) {
	outline := f32(2)
	for b in boxes {
		rect := rl.Rectangle{x + b.x * size - outline, y + b.y * size - outline, b.w * size + 2 * outline, b.h * size + 2 * outline}
		rl.DrawRectangleRounded(rect, 0.45, 6, {10, 18, 26, 255})
	}
	for b in boxes {
		rect := rl.Rectangle{x + b.x * size, y + b.y * size, b.w * size, b.h * size}
		c := rl.Color{u8(f32(fill.r) * b.shade), u8(f32(fill.g) * b.shade), u8(f32(fill.b) * b.shade), 255}
		rl.DrawRectangleRounded(rect, 0.45, 6, c)
	}
}

// The crosshair dot at the middle of the screen with a hand under it: an open
// hand in white while nothing is in reach, in teal when something is, and a
// closed fist while holding.
draw_crosshair :: proc(w, h: f32, state: carry.State) {
	cx, cy := i32(w * 0.5), i32(h * 0.5)
	radius := max(f32(3), h * 0.006)
	dot := rl.Color{255, 255, 255, 235}
	hand := rl.Color{226, 232, 238, 255}
	switch state {
	case .Idle:
	case .Reaching:
		radius *= 1.6
		dot, hand = {60, 230, 215, 255}, {60, 230, 215, 255}
	case .Holding:
		hand = rl.RAYWHITE
	}
	rl.DrawCircle(cx, cy, radius + 1.5, {10, 18, 26, 170})
	rl.DrawCircle(cx, cy, radius, dot)

	size := max(f32(30), h * 0.075)
	x := f32(cx) - size * 0.5
	y := f32(cy) + radius + 8
	if state == .Holding {
		closed := ICON_CLOSED
		draw_icon(closed[:], x, y, size, hand)
	} else {
		open := ICON_OPEN
		draw_icon(open[:], x, y, size, hand)
	}
}

draw_bench_button :: proc(w, h: f32) {
	draw_button(bench_button(w, h), "sim test", {10, 18, 28, 190}, {230, 236, 242, 200}, rl.RAYWHITE)
}

// The pour button is held down. It is bright when there is something to pour
// into, a vessel under the crosshair close enough or a tap, and dim when it would
// only spill what is held.
draw_pour_button :: proc(w, h: f32, label: cstring, ready: bool, held: bool) {
	fill := rl.Color{10, 18, 28, 150}
	edge := rl.Color{200, 210, 222, 110}
	ink := rl.Color{200, 210, 222, 160}
	if ready {
		fill, edge, ink = {14, 74, 74, 230}, {60, 230, 215, 255}, rl.RAYWHITE
	}
	if held {
		fill = {30, 130, 120, 245}
	}
	draw_button(pour_button(w, h), label, fill, edge, ink)
}

// The health bar, at the top in the middle, green when full and red when low.
draw_health :: proc(w, h: f32, hp: f32) {
	bar_w := w * 0.22
	bar_h := max(f32(10), h * 0.02)
	x := w * 0.5 - bar_w * 0.5
	y := h * 0.025
	share := clamp(hp / carry.HEALTH_MAX, 0, 1)
	fill := rl.Color{u8(230 - 170 * share), u8(60 + 170 * share), 70, 255}
	rl.DrawRectangleRounded({x - 3, y - 3, bar_w + 6, bar_h + 6}, 0.5, 6, {10, 18, 26, 200})
	if share > 0 {
		rl.DrawRectangleRounded({x, y, bar_w * share, bar_h}, 0.5, 6, fill)
	}
}

// A color over the whole screen: red when hurt, white-hot for a blast.
draw_flash :: proc(w, h: f32, color: rl.Color, amount: f32) {
	if amount < 0.02 {
		return
	}
	rl.DrawRectangle(0, 0, i32(w), i32(h), {color.r, color.g, color.b, u8(clamp(amount, 0, 1) * f32(color.a))})
}

// A message that fades out, for what a mix just did.
draw_toast :: proc(w, h: f32, text: cstring, timer: f32) {
	if timer <= 0 {
		return
	}
	alpha := u8(255 * clamp(timer / 0.6, 0, 1))
	font := i32(max(f32(18), h * 0.04))
	draw_text_centered(text, i32(w * 0.5), i32(h * 0.14), font, {255, 255, 255, alpha})
}

// What the crosshair says about the balloon at the fill station: what it holds and
// how full it is, going from teal to red as it nears bursting. `line` is 1 when a
// line about a vessel is already under the crosshair, and 0 when this is the first.
draw_filler_readout :: proc(w, h: f32, f: ^carry.Filler, line: int) {
	buf: [96]u8
	name := f.ml > 0 ? chem.compound_name(f.compound) : "empty"
	text := fmt.bprintf(buf[:95], "balloon  %v  %d / %d ml  %d%%", name, int(f.ml + 0.5), int(carry.BALLOON_REST_ML), int(carry.fill_ratio(f) * 100 + 0.5))
	buf[len(text)] = 0
	font := i32(max(f32(16), h * 0.032))
	y := i32(h * 0.5) + i32(max(f32(30), h * 0.075)) + 24 + i32(line) * (font + font / 3)
	st := carry.strain(f)
	color := rl.Color{u8(60 + 185 * st), u8(230 - 170 * st), u8(215 - 165 * st), 255}
	draw_text_centered(cstring(raw_data(buf[:])), i32(w * 0.5), y, font, color)
}

// The button that sets how fast liquid runs, under the matrix button. Each press goes
// to the next speed. It is lit when it is not at normal speed.
speed_button :: proc(w, h: f32) -> [4]f32 {
	b := matrix_button(w, h)
	return {b.x, b.y + b.w + 12, b.z, b.w}
}

draw_speed_button :: proc(w, h: f32, speed: f32) {
	buf: [24]u8
	text := fmt.bprintf(buf[:23], "speed x%d", int(speed + 0.5))
	buf[len(text)] = 0
	fill, edge, ink := rl.Color{10, 18, 28, 190}, rl.Color{230, 236, 242, 200}, rl.RAYWHITE
	if speed > 1.5 {
		fill, edge = {14, 74, 74, 230}, {60, 230, 215, 255}
	}
	draw_button(speed_button(w, h), cstring(raw_data(buf[:])), fill, edge, ink)
}

// The grab button as the run button, when the crosshair is on the reaction oven and
// a run could start.
draw_run_button :: proc(w, h: f32) {
	draw_button(grab_button(w, h), "run", {14, 74, 74, 230}, {60, 230, 215, 255}, rl.RAYWHITE)
}

// What the crosshair says about the reaction oven: what each of the four ports holds,
// with the one the crosshair points at in brackets, and then how the run is going or
// what waits in the tank. `line` is how many lines of text are already under the
// crosshair.
draw_oven_readout :: proc(w, h: f32, o: ^carry.Oven, line: int) {
	buf: [160]u8
	pos := 0
	for i in 0 ..< len(o.ports) {
		p := o.ports[i]
		name := p.ml > 0 ? chem.compound_name(p.compound) : "-"
		open, close := i == o.aimed_port ? "[" : " ", i == o.aimed_port ? "]" : " "
		pos += len(fmt.bprintf(buf[pos:150], "%v%d %v %d%v", open, i + 1, name, int(p.ml + 0.5), close))
	}
	switch {
	case o.state == .Running:
		pos += len(fmt.bprintf(buf[pos:150], "  running %d%%", int(carry.oven_progress(o) * 100 + 0.5)))
	case o.tank.ml > 0:
		pos += len(fmt.bprintf(buf[pos:150], "  tank: %v %d ml", chem.compound_name(o.tank.compound), int(o.tank.ml + 0.5)))
	}
	buf[min(pos, 159)] = 0
	font := i32(max(f32(16), h * 0.032))
	y := i32(h * 0.5) + i32(max(f32(30), h * 0.075)) + 24 + i32(line) * (font + font / 3)
	color := o.state == .Running ? rl.Color{255, 190, 60, 255} : rl.Color{60, 230, 215, 255}
	draw_text_centered(cstring(raw_data(buf[:])), i32(w * 0.5), y, font, color)
}

// The grab button as the button of a balloon action: tie off and take, clamp, take,
// or store. It is lit like the run button.
draw_action_button :: proc(w, h: f32, label: cstring) {
	draw_button(grab_button(w, h), label, {14, 74, 74, 230}, {60, 230, 215, 255}, rl.RAYWHITE)
}

// The grab button while a balloon is in the hands and there is nothing to do with it
// where the crosshair is: dim, with a word for why.
draw_full_button :: proc(w, h: f32) {
	draw_button(grab_button(w, h), "full", {10, 18, 28, 120}, {230, 236, 242, 90}, {230, 236, 242, 120})
}

balloon_action_label :: proc(a: carry.Balloon_Action) -> cstring {
	switch a {
	case .None:
		return ""
	case .Tie_Take:
		return "tie & take"
	case .Clamp:
		return "clamp"
	case .Take_Paint, .Take_Slot:
		return "take"
	case .Store:
		return "store"
	}
	return ""
}

// What the crosshair says about the paint station or a hook of the rack: what
// balloon is there, or that it is empty.
draw_spot_readout :: proc(w, h: f32, lo: ^carry.Loadout, line: int) {
	buf: [128]u8
	text: string
	switch lo.spot {
	case .None, .Fill:
		return
	case .Paint:
		if lo.paint.used {
			text = fmt.bprintf(buf[:120], "paint station  %v  %d ml  (drawing not built yet)", chem.compound_name(lo.paint.compound), int(lo.paint.ml + 0.5))
		} else {
			text = fmt.bprintf(buf[:120], "paint station  empty")
		}
	case .Slot:
		slot := lo.slots[lo.spot_slot]
		if slot.used {
			text = fmt.bprintf(buf[:120], "hook %d  %v  %d ml", lo.spot_slot + 1, chem.compound_name(slot.compound), int(slot.ml + 0.5))
		} else {
			text = fmt.bprintf(buf[:120], "hook %d  empty", lo.spot_slot + 1)
		}
	}
	buf[len(text)] = 0
	font := i32(max(f32(16), h * 0.032))
	y := i32(h * 0.5) + i32(max(f32(30), h * 0.075)) + 24 + i32(line) * (font + font / 3)
	draw_text_centered(cstring(raw_data(buf[:])), i32(w * 0.5), y, font, {60, 230, 215, 255})
}

// A line near the bottom of the screen that says the hands hold a balloon.
draw_carrying :: proc(w, h: f32, item: carry.Item) {
	if !item.used {
		return
	}
	buf: [96]u8
	text := fmt.bprintf(buf[:95], "carrying a balloon  %v  %d ml", chem.compound_name(item.compound), int(item.ml + 0.5))
	buf[len(text)] = 0
	draw_text_centered(cstring(raw_data(buf[:])), i32(w * 0.5), i32(h * 0.86), i32(max(f32(16), h * 0.032)), {255, 214, 120, 255})
}
