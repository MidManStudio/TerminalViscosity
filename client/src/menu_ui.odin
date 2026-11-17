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

BOOK_COLUMNS :: 6 // compounds in a row of the contents page
BOOK_ROWS :: 8 // lines on one spread of a compound's page, the rest go on the next spread

// The button that opens the book of reactions, under the sim test button.
book_button :: proc(w, h: f32) -> [4]f32 {
	b := bench_button(w, h)
	return {b.x, b.y + b.w + 12, b.z, b.w}
}

draw_book_button :: proc(w, h: f32) {
	draw_button(book_button(w, h), "book", {10, 18, 28, 190}, {230, 236, 242, 200}, rl.RAYWHITE)
}

// The panel of the book, and its close button in the top right corner.
book_panel :: proc(w, h: f32) -> [4]f32 {
	return {w * 0.03, h * 0.03, w * 0.94, h * 0.94}
}

book_close_button :: proc(w, h: f32) -> [4]f32 {
	p := book_panel(w, h)
	size := max(f32(56), h * 0.1)
	return {p.x + p.z - size * 1.7 - 20, p.y + 20, size * 1.7, size}
}

// The bar along the bottom of the panel has three buttons: back (0), contents (1) and next (2).
book_bar_button :: proc(w, h: f32, k: int) -> [4]f32 {
	p := book_panel(w, h)
	bar := max(f32(56), h * 0.1)
	button_w := min(p.z * 0.26, bar * 3.4)
	gap := button_w * 0.12
	left := p.x + (p.z - button_w * 3 - gap * 2) * 0.5
	return {left + f32(k) * (button_w + gap), p.y + p.w - 16 - bar, button_w, bar}
}

book_prev_button :: proc(w, h: f32) -> [4]f32 {
	return book_bar_button(w, h, 0)
}

book_contents_button :: proc(w, h: f32) -> [4]f32 {
	return book_bar_button(w, h, 1)
}

book_next_button :: proc(w, h: f32) -> [4]f32 {
	return book_bar_button(w, h, 2)
}

// The small line under the heading, and where it starts: just under the close button.
book_sub_font :: proc(h: f32) -> i32 {
	return i32(max(f32(14), h * 0.032))
}

book_sub_y :: proc(w, h: f32) -> f32 {
	c := book_close_button(w, h)
	return c.y + c.w + 8
}

// Where the body of a page starts, under the small line.
book_body_top :: proc(w, h: f32) -> f32 {
	return book_sub_y(w, h) + f32(book_sub_font(h)) + 12
}

// The box of the k-th tile (from 0) of the contents page: one for each compound, BOOK_COLUMNS to a row.
book_tile :: proc(w, h: f32, k: int) -> [4]f32 {
	p := book_panel(w, h)
	gap := f32(12)
	rows := (chemistry.COMPOUND_COUNT + BOOK_COLUMNS - 1) / BOOK_COLUMNS
	top := book_body_top(w, h)
	bottom := book_prev_button(w, h).y - 12
	tile_w := (p.z - 40 - gap * f32(BOOK_COLUMNS - 1)) / f32(BOOK_COLUMNS)
	tile_h := min((bottom - top - gap * f32(rows - 1)) / f32(rows), h * 0.2)
	return {p.x + 20 + f32(k % BOOK_COLUMNS) * (tile_w + gap), top + f32(k / BOOK_COLUMNS) * (tile_h + gap), tile_w, tile_h}
}

// The number of the compound whose tile the pointer is on, from 1, and 0 for none.
book_tile_at :: proc(w, h: f32, pointer: [2]f32) -> int {
	for k in 0 ..< chemistry.COMPOUND_COUNT {
		if inside(pointer, book_tile(w, h, k)) {
			return k + 1
		}
	}
	return 0
}

// How many spreads the page of a compound takes, at least one.
book_parts :: proc(id: chemistry.Id) -> int {
	return max(1, (chemistry.page_count(id) + BOOK_ROWS - 1) / BOOK_ROWS)
}

// The last page of the book. Page 0 is the contents, and then each compound has its spreads, in the order of
// the pages.
book_last_page :: proc() -> int {
	n := 0
	for c in 1 ..= chemistry.COMPOUND_COUNT {
		n += book_parts(chemistry.Id(c))
	}
	return n
}

// Which compound a page is of, and which of its spreads, from 0. The contents page is of none.
book_at :: proc(page: int) -> (id: chemistry.Id, part: int) {
	left := clamp(page, 0, book_last_page())
	if left == 0 {
		return .None, 0
	}
	for c in 1 ..= chemistry.COMPOUND_COUNT {
		parts := book_parts(chemistry.Id(c))
		if left <= parts {
			return chemistry.Id(c), left - 1
		}
		left -= parts
	}
	return .None, 0
}

// The first page of a compound.
book_first_page :: proc(id: chemistry.Id) -> int {
	page := 1
	for c in 1 ..< int(id) {
		page += book_parts(chemistry.Id(c))
	}
	return page
}

book_prev_page :: proc(page: int) -> int {
	return clamp(page - 1, 0, book_last_page())
}

book_next_page :: proc(page: int) -> int {
	return clamp(page + 1, 0, book_last_page())
}

// The page after a press at `pointer`: the back and next buttons turn a page, the contents button goes to the
// contents, and on the contents page a tile goes to its compound. A press anywhere else changes nothing.
book_press :: proc(page: int, pointer: [2]f32, w, h: f32) -> int {
	if inside(pointer, book_prev_button(w, h)) {
		return book_prev_page(page)
	}
	if inside(pointer, book_next_button(w, h)) {
		return book_next_page(page)
	}
	if inside(pointer, book_contents_button(w, h)) {
		return 0
	}
	if page == 0 {
		if c := book_tile_at(w, h, pointer); c > 0 {
			return book_first_page(chemistry.Id(c))
		}
	}
	return page
}

// Draws text that is made smaller until it fits `width`, centred on `cx`.
draw_text_fit :: proc(text: cstring, cx, y, width, font: i32, color: rl.Color) {
	size := font
	for size > 10 && rl.MeasureText(text, size) > width {
		size -= 1
	}
	rl.DrawText(text, cx - rl.MeasureText(text, size) / 2, y, size, color)
}

// The same, starting at `x`.
draw_text_left :: proc(text: cstring, x, y, width, font: i32, color: rl.Color) {
	size := font
	for size > 10 && rl.MeasureText(text, size) > width {
		size -= 1
	}
	rl.DrawText(text, x, y, size, color)
}

// What a station is called in the book, and "" for any.
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

// Text written into a caller's buffer, so that nothing is allocated while the book is open.
Book_Line :: struct {
	buf: []u8,
	n:   int,
}

book_put :: proc(l: ^Book_Line, text: string) {
	for c in transmute([]u8)text {
		if l.n < len(l.buf) - 1 {
			l.buf[l.n] = c
			l.n += 1
		}
	}
}

// The text, ended with a zero byte. It is a view of the buffer.
book_text :: proc(l: ^Book_Line) -> cstring {
	l.buf[l.n] = 0
	return cstring(raw_data(l.buf))
}

// An input of a reaction: the compound, and the purity it asks for when that is not any, as the band or bands the
// pages call it, such as "Water (Distilled water or better)".
book_put_part :: proc(l: ^Book_Line, part: ^chemistry.Part) {
	book_put(l, chemistry.name_of(part.compound))
	if part.purity_min <= 0 && part.purity_max >= 1 {
		return
	}
	low, high, ok := chemistry.bands_of(part.compound, part.purity_min, part.purity_max)
	if !ok {
		return
	}
	book_put(l, " (")
	book_put(l, low.label)
	if low != high {
		if part.purity_max >= 1 {
			book_put(l, " or better")
		} else {
			book_put(l, " to ")
			book_put(l, high.label)
		}
	}
	book_put(l, ")")
}

// A list of outputs as text, with "a mix" for none, which is a reaction that makes a solution.
book_put_products :: proc(l: ^Book_Line, span: chemistry.Span) {
	if span.count == 0 {
		book_put(l, "a mix")
	}
	for k in span.first ..< span.first + span.count {
		if k > span.first {
			book_put(l, " + ")
		}
		book_put(l, chemistry.name_of(chemistry.products[k].compound))
	}
}

// What goes in and what comes out of a reaction, as a line. `fails` is for the reaction going wrong, which
// comes out as its failure outputs.
book_reaction_text :: proc(buf: []u8, r: ^chemistry.Reaction, fails: bool) -> cstring {
	l := Book_Line {
		buf = buf,
	}
	for k in r.inputs.first ..< r.inputs.first + r.inputs.count {
		if k > r.inputs.first {
			book_put(&l, " + ")
		}
		book_put_part(&l, &chemistry.parts[k])
	}
	book_put(&l, "  ->  ")
	book_put_products(&l, fails ? r.failure_outputs : r.outputs)
	return book_text(&l)
}

// The same for an electrolysis: the band that it is done to, and what it gives.
book_electrolysis_text :: proc(buf: []u8, e: ^chemistry.Electrolysis) -> cstring {
	l := Book_Line {
		buf = buf,
	}
	label := chemistry.label_of(e.compound, e.form)
	book_put(&l, label == "" ? chemistry.name_of(e.compound) : label)
	book_put(&l, "  ->  ")
	book_put_products(&l, e.products)
	return book_text(&l)
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

// When a reaction goes wrong, and where it does.
failure_conditions :: proc(buf: []u8, r: ^chemistry.Reaction) -> cstring {
	where_ := station_text(r.station)
	text := fmt.bprintf(buf[:len(buf) - 1], "%v%vgoes wrong at %d C and above", where_, where_ == "" ? "" : ", ", int(r.over_c))
	buf[len(text)] = 0
	return cstring(raw_data(buf))
}

// What an electrolysis needs: the station, and the catalyst when it has one.
electrolysis_conditions :: proc(buf: []u8, e: ^chemistry.Electrolysis) -> cstring {
	text: string
	if e.catalyst != .None {
		text = fmt.bprintf(buf[:len(buf) - 1], "electrolysis, with %v", chemistry.name_of(e.catalyst))
	} else {
		text = fmt.bprintf(buf[:len(buf) - 1], "electrolysis")
	}
	buf[len(text)] = 0
	return cstring(raw_data(buf))
}

// What the left column of a line says about the compound whose page it is on.
book_tag :: proc(kind: chemistry.Page_Kind) -> cstring {
	switch kind {
	case .Makes, .Electrolysis_Makes:
		return "made by"
	case .Fails_Into:
		return "made if wrong"
	case .Input:
		return "goes into"
	case .Catalyst:
		return "catalyst in"
	case .Electrolysed:
		return "electrolysed"
	}
	return ""
}

// How a line is coloured: green for what cannot go wrong, amber for what can spatter or give off fumes, red for
// what can burst.
book_fill :: proc(entry: chemistry.Page_Entry) -> rl.Color {
	if chemistry.is_electrolysis(entry.kind) {
		#partial switch chemistry.electrolyses[entry.index].event {
		case .None:
			return CELL_CALM
		case .Burst:
			return CELL_BLAST
		}
		return CELL_SPATTER
	}
	r := &chemistry.reactions[entry.index]
	if r.has_failure {
		return r.failure == .Burst ? CELL_BLAST : CELL_SPATTER
	}
	return CELL_CALM
}

phase_text :: proc(phase: chemistry.Phase) -> string {
	switch phase {
	case .Solid:
		return "solid"
	case .Liquid:
		return "liquid"
	case .Gas:
		return "gas"
	}
	return ""
}

level_text :: proc(level: u8) -> string {
	switch level {
	case 0:
		return "a base chemical"
	case 1:
		return "made from base chemicals"
	}
	return "made from a product"
}

// A button of the bar: bright when it can be used and dim when it cannot, so that its state is known before it
// is pressed.
draw_book_nav :: proc(b: [4]f32, label: cstring, usable: bool) {
	fill, edge, ink := rl.Color{10, 18, 28, 150}, rl.Color{200, 210, 222, 110}, rl.Color{200, 210, 222, 160}
	if usable {
		fill, edge, ink = {14, 74, 74, 230}, {60, 230, 215, 255}, rl.RAYWHITE
	}
	draw_button(b, label, fill, edge, ink)
}

// The contents page: a tile for each compound. Pressing one opens its page.
draw_book_contents :: proc(w, h: f32) {
	for k in 0 ..< chemistry.COMPOUND_COUNT {
		c := chemistry.compound_of(chemistry.Id(k + 1))
		t := book_tile(w, h, k)
		rl.DrawRectangleRounded({t.x, t.y, t.z, t.w}, 0.12, 6, {26, 36, 48, 255})
		rl.DrawRectangleRoundedLinesEx({t.x, t.y, t.z, t.w}, 0.12, 6, 2, {230, 236, 242, 90})
		rl.DrawRectangleRounded({t.x + 8, t.y + 8, t.z * 0.12, t.w - 16}, 0.3, 4, {c.color.r, c.color.g, c.color.b, 255})
		text_x := i32(t.x + 8 + t.z * 0.12 + 8)
		text_w := i32(t.x + t.z - 8) - text_x
		name_font := i32(max(f32(14), t.w * 0.16))
		draw_text_left(chemistry.cname_of(chemistry.Id(k + 1)), text_x, i32(t.y + t.w * 0.2), text_w, name_font, rl.RAYWHITE)
		buf: [32]u8
		line := Book_Line {
			buf = buf[:],
		}
		book_put(&line, phase_text(c.phase))
		draw_text_left(book_text(&line), text_x, i32(t.y + t.w * 0.2) + name_font + 6, text_w, i32(max(f32(12), t.w * 0.11)), {200, 212, 224, 255})
	}
}

// One spread of the page of a compound: its colour and name, what it is, and the lines the pages have for it.
draw_book_compound :: proc(w, h: f32, id: chemistry.Id, part: int) {
	p := book_panel(w, h)
	c := chemistry.compound_of(id)
	close := book_close_button(w, h)
	head_font := i32(max(f32(22), h * 0.06))
	head_y := i32(close.y + (close.w - f32(head_font)) * 0.5)
	rl.DrawRectangleRounded({p.x + 24, f32(head_y), f32(head_font), f32(head_font)}, 0.25, 4, {c.color.r, c.color.g, c.color.b, 255})
	title: [96]u8
	parts := book_parts(id)
	text: string
	if parts > 1 {
		text = fmt.bprintf(title[:len(title) - 1], "%v (%d of %d)", c.name, part + 1, parts)
	} else {
		text = fmt.bprintf(title[:len(title) - 1], "%v", c.name)
	}
	title[len(text)] = 0
	rl.DrawText(cstring(raw_data(title[:])), i32(p.x) + 24 + head_font + 14, head_y, head_font, rl.RAYWHITE)

	sub: [96]u8
	sub_line := Book_Line {
		buf = sub[:],
	}
	book_put(&sub_line, phase_text(c.phase))
	book_put(&sub_line, ", ")
	book_put(&sub_line, level_text(c.level))
	sub_font := book_sub_font(h)
	rl.DrawText(book_text(&sub_line), i32(p.x) + 24, i32(book_sub_y(w, h)), sub_font, {200, 212, 224, 255})

	// The key.
	key_y := i32(book_body_top(w, h))
	key_x := i32(p.x) + 24
	legend_font := i32(max(f32(14), h * 0.028))
	keys := [3]struct {
		color: rl.Color,
		label: cstring,
	}{{CELL_CALM, "cannot go wrong"}, {CELL_SPATTER, "can spatter or fume"}, {CELL_BLAST, "can burst"}}
	for k in keys {
		rl.DrawRectangleRounded({f32(key_x), f32(key_y), f32(legend_font), f32(legend_font)}, 0.3, 4, k.color)
		rl.DrawText(k.label, key_x + legend_font + 8, key_y, legend_font, {220, 228, 236, 255})
		key_x += legend_font + 8 + rl.MeasureText(k.label, legend_font) + 36
	}

	// The lines of this spread. Each has what it says about the compound on the left, then what goes in and what
	// comes out, and under that where and how hot.
	lines: [chemistry.MAX_PAGE_ENTRIES]chemistry.Page_Entry
	n := chemistry.page_of(id, lines[:])
	rows_top := f32(key_y + legend_font + 12)
	rows_bottom := book_prev_button(w, h).y - 12
	row_h := min((rows_bottom - rows_top) / f32(BOOK_ROWS), h * 0.12)
	if n == 0 {
		draw_text_fit("no reaction or electrolysis on the pages names it yet", i32(p.x + p.z * 0.5), i32(rows_top + row_h), i32(p.z) - 48, legend_font + 4, {200, 212, 224, 255})
		return
	}
	first := part * BOOK_ROWS
	shown := clamp(n - first, 0, BOOK_ROWS)
	tag_w := (p.z - 40) * 0.16
	body_w := p.z - 40 - tag_w - 24
	for k in 0 ..< shown {
		entry := lines[first + k]
		y := rows_top + f32(k) * row_h
		rl.DrawRectangleRounded({p.x + 20, y + 2, p.z - 40, row_h - 4}, 0.15, 4, book_fill(entry))
		draw_text_fit(book_tag(entry.kind), i32(p.x + 20 + tag_w * 0.5), i32(y + row_h * 0.3), i32(tag_w) - 12, i32(max(f32(12), row_h * 0.3)), {255, 236, 200, 255})
		equation, conditions: [200]u8
		x := i32(p.x + 20 + tag_w + 12)
		eq_font := i32(max(f32(12), row_h * 0.34))
		cond_font := i32(max(f32(10), row_h * 0.26))
		eq_text, cond_text: cstring
		switch entry.kind {
		case .Makes, .Input, .Catalyst:
			r := &chemistry.reactions[entry.index]
			eq_text, cond_text = book_reaction_text(equation[:], r, false), reaction_conditions(conditions[:], r)
		case .Fails_Into:
			r := &chemistry.reactions[entry.index]
			eq_text, cond_text = book_reaction_text(equation[:], r, true), failure_conditions(conditions[:], r)
		case .Electrolysis_Makes, .Electrolysed:
			e := &chemistry.electrolyses[entry.index]
			eq_text, cond_text = book_electrolysis_text(equation[:], e), electrolysis_conditions(conditions[:], e)
		}
		draw_text_left(eq_text, x, i32(y + row_h * 0.1), i32(body_w), eq_font, rl.RAYWHITE)
		draw_text_left(cond_text, x, i32(y + row_h * 0.55), i32(body_w), cond_font, {255, 236, 200, 255})
	}
}

// The book of reactions over the lab: a contents page of the compounds, and a page for each compound with every
// reaction that makes it, goes wrong into it, or uses it, and every electrolysis that gives it or is done to it.
// The pages are the ones the game has, and nothing here says which the player has found.
draw_book :: proc(w, h: f32, page: int) {
	p := book_panel(w, h)
	rl.DrawRectangle(0, 0, i32(w), i32(h), {0, 0, 0, 150})
	rl.DrawRectangleRounded({p.x, p.y, p.z, p.w}, 0.02, 8, {14, 20, 28, 248})
	rl.DrawRectangleRoundedLinesEx({p.x, p.y, p.z, p.w}, 0.02, 8, 3, {230, 236, 242, 160})
	draw_button(book_close_button(w, h), "close", {120, 30, 30, 235}, {255, 200, 200, 255}, rl.RAYWHITE)

	last := book_last_page()
	here := clamp(page, 0, last)
	draw_book_nav(book_prev_button(w, h), "back", here > 0)
	draw_book_nav(book_contents_button(w, h), "contents", here > 0)
	draw_book_nav(book_next_button(w, h), "next", here < last)

	// The page number, in the top row beside the close button.
	number: [32]u8
	text := fmt.bprintf(number[:len(number) - 1], "page %d of %d", here + 1, last + 1)
	number[len(text)] = 0
	close := book_close_button(w, h)
	number_font := book_sub_font(h)
	rl.DrawText(cstring(raw_data(number[:])), i32(close.x) - 16 - rl.MeasureText(cstring(raw_data(number[:])), number_font), i32(close.y + (close.w - f32(number_font)) * 0.5), number_font, {200, 212, 224, 255})

	id, part := book_at(here)
	if id == .None {
		head_font := i32(max(f32(22), h * 0.06))
		rl.DrawText("reaction book", i32(p.x) + 24, i32(close.y + (close.w - f32(head_font)) * 0.5), head_font, rl.RAYWHITE)
		rl.DrawText("tap a compound to open its page", i32(p.x) + 24, i32(book_sub_y(w, h)), book_sub_font(h), {200, 212, 224, 255})
		draw_book_contents(w, h)
		return
	}
	draw_book_compound(w, h, id, part)
}
