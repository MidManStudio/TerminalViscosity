// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "menu_ui.odin"
// ============================================================================

package main

import rl "vendor:raylib"
import "chem"

CELL_CALM :: rl.Color{30, 92, 62, 255}
CELL_SPATTER :: rl.Color{176, 112, 24, 255}
CELL_BLAST :: rl.Color{184, 44, 44, 255}
CELL_SAME :: rl.Color{52, 58, 70, 255}

// The button that opens the reaction matrix, under the sim test button.
matrix_button :: proc(w, h: f32) -> [4]f32 {
	b := bench_button(w, h)
	return {b.x, b.y + b.w + 12, b.z, b.w}
}

draw_matrix_button :: proc(w, h: f32) {
	draw_button(matrix_button(w, h), "matrix", {10, 18, 28, 190}, {230, 236, 242, 200}, rl.RAYWHITE)
}

// The panel of the reaction matrix, and its close button in the top right corner.
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

// The reaction matrix as a menu over the lab: every stock liquid against every
// other, each cell colored by how it ends, with what it makes written in it.
// Green is no volatile, amber spatters, and red is volatile, a blast.
draw_matrix_menu :: proc(w, h: f32) {
	p := matrix_panel(w, h)
	rl.DrawRectangle(0, 0, i32(w), i32(h), {0, 0, 0, 150})
	rl.DrawRectangleRounded({p.x, p.y, p.z, p.w}, 0.02, 8, {14, 20, 28, 248})
	rl.DrawRectangleRoundedLinesEx({p.x, p.y, p.z, p.w}, 0.02, 8, 3, {230, 236, 242, 160})

	title_font := i32(max(f32(22), h * 0.05))
	rl.DrawText("reaction matrix", i32(p.x) + 24, i32(p.y) + 18, title_font, rl.RAYWHITE)
	draw_button(matrix_close_button(w, h), "close", {120, 30, 30, 235}, {255, 200, 200, 255}, rl.RAYWHITE)

	// The key.
	legend_font := i32(max(f32(14), h * 0.028))
	key_y := i32(p.y) + 18 + title_font + 14
	key_x := i32(p.x) + 24
	keys := [4]struct {
		color: rl.Color,
		label: cstring,
	}{{CELL_CALM, "no volatile"}, {CELL_SPATTER, "spatter"}, {CELL_BLAST, "volatile (blast)"}, {CELL_SAME, "same liquid, nothing happens"}}
	for k in keys {
		rl.DrawRectangleRounded({f32(key_x), f32(key_y), f32(legend_font), f32(legend_font)}, 0.3, 4, k.color)
		rl.DrawText(k.label, key_x + legend_font + 8, key_y, legend_font, {220, 228, 236, 255})
		key_x += legend_font + 8 + rl.MeasureText(k.label, legend_font) + 36
	}

	// The grid: a row of names across the top, and a column of names down the side.
	n := chem.STOCK_COUNT
	grid_top := f32(key_y + legend_font + 18)
	grid_bottom := p.y + p.w - 16
	label_w := p.z * 0.12
	cell_w := (p.z - label_w - 40) / f32(n)
	cell_h := (grid_bottom - grid_top) / f32(n + 1)
	left := p.x + 20 + label_w
	name_font := i32(max(f32(12), cell_h * 0.34))

	for i in 0 ..< n {
		id := u16(i + 1)
		color := chem.compound_color(id)
		swatch := rl.Color{u8(color.r * 255), u8(color.g * 255), u8(color.b * 255), 255}
		// column header
		cx := left + f32(i) * cell_w
		rl.DrawRectangle(i32(cx) + 2, i32(grid_top) + i32(cell_h) - 6, i32(cell_w) - 4, 4, swatch)
		draw_text_fit(chem.compound_cname(id), i32(cx + cell_w * 0.5), i32(grid_top + cell_h * 0.2), i32(cell_w) - 8, name_font, rl.RAYWHITE)
		// row header
		cy := grid_top + f32(i + 1) * cell_h
		rl.DrawRectangle(i32(p.x) + 20, i32(cy) + 2, 6, i32(cell_h) - 4, swatch)
		draw_text_fit(chem.compound_cname(id), i32(p.x + 20 + label_w * 0.5) + 4, i32(cy + cell_h * 0.3), i32(label_w) - 24, name_font, rl.RAYWHITE)

		for j in 0 ..< n {
			other := u16(j + 1)
			x := left + f32(j) * cell_w
			rect := rl.Rectangle{x + 2, cy + 2, cell_w - 4, cell_h - 4}
			if i == j {
				rl.DrawRectangleRounded(rect, 0.15, 4, CELL_SAME)
				draw_text_fit("-", i32(x + cell_w * 0.5), i32(cy + cell_h * 0.3), i32(cell_w) - 8, name_font, {160, 170, 182, 255})
				continue
			}
			outcome := chem.react(id, other)
			fill := CELL_CALM
			tag: cstring = ""
			switch chem.hazard_of(outcome.volatility) {
			case .Calm:
			case .Spatter:
				fill, tag = CELL_SPATTER, "spatter"
			case .Blast:
				fill, tag = CELL_BLAST, "volatile"
			}
			rl.DrawRectangleRounded(rect, 0.15, 4, fill)
			product := chem.compound_cname(outcome.product)
			if tag == "" {
				draw_text_fit(product, i32(x + cell_w * 0.5), i32(cy + cell_h * 0.3), i32(cell_w) - 10, name_font, rl.RAYWHITE)
			} else {
				draw_text_fit(product, i32(x + cell_w * 0.5), i32(cy + cell_h * 0.12), i32(cell_w) - 10, name_font, rl.RAYWHITE)
				draw_text_fit(tag, i32(x + cell_w * 0.5), i32(cy + cell_h * 0.12) + name_font + 2, i32(cell_w) - 10, name_font * 3 / 4, {255, 236, 200, 255})
			}
		}
	}
}
