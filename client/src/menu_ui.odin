// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "menu_ui.odin"
// ============================================================================

package main

import "chemistry"
import "core:fmt"
import rl "vendor:raylib"

CELL_CALM :: rl.Color{30, 92, 62, 255}
CELL_SPATTER :: rl.Color{176, 112, 24, 255}
CELL_BLAST :: rl.Color{184, 44, 44, 255}

// The button that opens the list of reactions, under the sim test button.
matrix_button :: proc(w, h: f32) -> [4]f32 {
	b := bench_button(w, h)
	return {b.x, b.y + b.w + 12, b.z, b.w}
}

draw_matrix_button :: proc(w, h: f32) {
	draw_button(matrix_button(w, h), "matrix", {10, 18, 28, 190}, {230, 236, 242, 200}, rl.RAYWHITE)
}

// The panel of the list of reactions, and its close button in the top right corner.
matrix_panel :: proc(w, h: f32) -> [4]f32 {
	return {w * 0.03, h * 0.03, w * 0.94, h * 0.94}
}

matrix_close_button :: proc(w, h: f32) -> [4]f32 {
	p := matrix_panel(w, h)
	size := max(f32(56), h * 0.1)
	return {p.x + p.z - size * 1.7 - 20, p.y + 20, size * 1.7, size}
}

// Draws text that is made smaller until it fits `width`.
draw_text_fit :: proc(text: cstring, cx, y, width, font: i32, color: rl.Color) {
	size := font
	for size > 10 && rl.MeasureText(text, size) > width {
		size -= 1
	}
	rl.DrawText(text, cx - rl.MeasureText(text, size) / 2, y, size, color)
}

// What a station is called in the list of reactions, and "" for any.
station_text :: proc(station: chemistry.Station) -> string {
	#partial switch station {
	case .Hot_Bath:
		return "hot bath"
	case .Cold_Bath:
		return "cold bath"
	case .Oven:
		return "oven"
	case .Freezer:
		return "freezer"
	case .Furnace:
		return "furnace"
	case .Electrolysis:
		return "electrolysis"
	case .Distillation:
		return "distillation"
	case .Centrifuge:
		return "centrifuge"
	}
	return ""
}

// One reaction of the pages as a line: what goes in, what comes out, where and how hot it has to be, and what has
// to be there to help it. The text is a view of `buf`.
reaction_line :: proc(buf: []u8, r: ^chemistry.Reaction) -> cstring {
	n := 0
	put :: proc(buf: []u8, n: ^int, text: string) {
		for c in transmute([]u8)text {
			if n^ < len(buf) - 1 {
				buf[n^] = c
				n^ += 1
			}
		}
	}
	for k in r.inputs.first ..< r.inputs.first + r.inputs.count {
		if k > r.inputs.first {
			put(buf, &n, " + ")
		}
		put(buf, &n, chemistry.name_of(chemistry.parts[k].compound))
	}
	put(buf, &n, "  ->  ")
	if r.outputs.count == 0 {
		put(buf, &n, "a mix")
	}
	for k in r.outputs.first ..< r.outputs.first + r.outputs.count {
		if k > r.outputs.first {
			put(buf, &n, " + ")
		}
		put(buf, &n, chemistry.name_of(chemistry.products[k].compound))
	}
	buf[n] = 0
	return cstring(raw_data(buf))
}

// The conditions of a reaction as a line: the station and the temperature it has to be at, and the catalyst.
reaction_conditions :: proc(buf: []u8, r: ^chemistry.Reaction) -> cstring {
	where_ := station_text(r.station)
	text: string
	if r.catalyst != .None {
		text = fmt.bprintf(buf[:len(buf) - 1], "%v%v%d-%d C, with %v", where_, where_ == "" ? "" : " ", int(r.min_c), int(r.max_c), chemistry.name_of(r.catalyst))
	} else {
		text = fmt.bprintf(buf[:len(buf) - 1], "%v%v%d-%d C", where_, where_ == "" ? "" : " ", int(r.min_c), int(r.max_c))
	}
	buf[len(text)] = 0
	return cstring(raw_data(buf))
}

// The reactions of the pages as a menu over the lab: one line for each, with what goes in and what comes out and
// the temperature it needs. Green is a reaction that cannot go wrong, amber can spatter or give off fumes, and
// red can burst. The reactions are the ones the pages have, and nothing here says which the player has found.
draw_matrix_menu :: proc(w, h: f32) {
	p := matrix_panel(w, h)
	rl.DrawRectangle(0, 0, i32(w), i32(h), {0, 0, 0, 150})
	rl.DrawRectangleRounded({p.x, p.y, p.z, p.w}, 0.02, 8, {14, 20, 28, 248})
	rl.DrawRectangleRoundedLinesEx({p.x, p.y, p.z, p.w}, 0.02, 8, 3, {230, 236, 242, 160})

	title_font := i32(max(f32(22), h * 0.05))
	rl.DrawText("reactions", i32(p.x) + 24, i32(p.y) + 18, title_font, rl.RAYWHITE)
	draw_button(matrix_close_button(w, h), "close", {120, 30, 30, 235}, {255, 200, 200, 255}, rl.RAYWHITE)

	// The key.
	legend_font := i32(max(f32(14), h * 0.028))
	key_y := i32(p.y) + 18 + title_font + 14
	key_x := i32(p.x) + 24
	keys := [3]struct {
		color: rl.Color,
		label: cstring,
	}{{CELL_CALM, "cannot go wrong"}, {CELL_SPATTER, "can spatter or fume"}, {CELL_BLAST, "can burst"}}
	for k in keys {
		rl.DrawRectangleRounded({f32(key_x), f32(key_y), f32(legend_font), f32(legend_font)}, 0.3, 4, k.color)
		rl.DrawText(k.label, key_x + legend_font + 8, key_y, legend_font, {220, 228, 236, 255})
		key_x += legend_font + 8 + rl.MeasureText(k.label, legend_font) + 36
	}

	// The list: what goes in and what comes out on the left, the conditions on the right.
	grid_top := f32(key_y + legend_font + 18)
	grid_bottom := p.y + p.w - 16
	row_h := (grid_bottom - grid_top) / f32(chemistry.REACTION_COUNT)
	font := i32(max(f32(12), row_h * 0.4))
	left_w := (p.z - 40) * 0.62
	for i in 0 ..< chemistry.REACTION_COUNT {
		r := &chemistry.reactions[i]
		y := grid_top + f32(i) * row_h
		fill := CELL_CALM
		if r.has_failure {
			fill = r.failure == .Burst ? CELL_BLAST : CELL_SPATTER
		}
		rl.DrawRectangleRounded({p.x + 20, y + 2, p.z - 40, row_h - 4}, 0.15, 4, fill)
		line, cond: [160]u8
		draw_text_fit(reaction_line(line[:], r), i32(p.x + 20 + left_w * 0.5), i32(y + row_h * 0.25), i32(left_w) - 16, font, rl.RAYWHITE)
		draw_text_fit(reaction_conditions(cond[:], r), i32(p.x + 20 + left_w + (p.z - 40 - left_w) * 0.5), i32(y + row_h * 0.25), i32(p.z - 40 - left_w) - 16, font, {255, 236, 200, 255})
	}
}
