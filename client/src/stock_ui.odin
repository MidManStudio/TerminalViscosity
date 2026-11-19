// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stock_ui.odin"
// ============================================================================

package main

import "carry"
import "chemistry"
import "core:fmt"
import "dragdrop"
import "inventory"
import "lab"
import rl "vendor:raylib"

STOCK_BAG :: 0 // the number of the bag, and of the wall, in a drag
STOCK_WALL :: 1
STOCK_GAP :: f32(10)
WALL_COLUMNS :: 5 // the ten mounts of the wall in two rows of five
BAG_COLUMNS :: 4 // the twelve slots of the bag in three rows of four

// The state of the screen: the drag that is going on, if any.
Stock_Ui :: struct {
	drag: dragdrop.Controller,
}

stock_ui_init :: proc(ui: ^Stock_Ui) {
	dragdrop.controller_init(&ui.drag)
}

// A place to drop: which slot of which container, and the stock that holds them, for the rule that says whether
// the drag may end there.
Slot_Ref :: struct {
	stock:     ^carry.Stock,
	container: int,
	slot:      int,
}

stock_container :: proc(s: ^carry.Stock, container: int) -> ^inventory.Container {
	return container == STOCK_WALL ? &s.wall : &s.bag
}

stock_slot_count :: proc(container: int) -> int {
	return container == STOCK_WALL ? lab.DISPENSER_COUNT : carry.BAG_SIZE
}

// The button that opens the bag and the wall, to the left of the book button.
bag_button :: proc(w, h: f32) -> [4]f32 {
	b := book_button(w, h)
	return {b.x - b.z - 12, b.y, b.z, b.w}
}

draw_bag_button :: proc(w, h: f32) {
	draw_button(bag_button(w, h), "bag", {10, 18, 28, 190}, {230, 236, 242, 200}, rl.RAYWHITE)
}

// Where a grid starts, how big its tiles are, and how many columns it has. The wall is on the left half of the
// panel and the bag on the right. Both are under the line of text that the book also has.
stock_grid :: proc(w, h: f32, container: int) -> (x, y, tile: f32, cols: int) {
	p := book_panel(w, h)
	half := p.z * 0.5
	left := p.x + 20
	if container == STOCK_BAG {
		left = p.x + half + 10
	}
	width := half - 30
	cols = container == STOCK_WALL ? WALL_COLUMNS : BAG_COLUMNS
	rows := (stock_slot_count(container) + cols - 1) / cols
	top := book_body_top(w, h) + f32(book_sub_font(h)) + 10
	bottom := p.y + p.w - 20
	tile = min((width - STOCK_GAP * f32(cols - 1)) / f32(cols), (bottom - top - STOCK_GAP * f32(rows - 1)) / f32(rows))
	x = left + (width - (tile * f32(cols) + STOCK_GAP * f32(cols - 1))) * 0.5
	return x, top, tile, cols
}

stock_slot_box :: proc(w, h: f32, container, slot: int) -> [4]f32 {
	x, y, tile, cols := stock_grid(w, h, container)
	return {x + f32(slot % cols) * (tile + STOCK_GAP), y + f32(slot / cols) * (tile + STOCK_GAP), tile, tile}
}

// The slot the pointer is on, if it is on one.
stock_slot_at :: proc(w, h: f32, pointer: [2]f32) -> (container, slot: int, ok: bool) {
	for c in 0 ..< 2 {
		for s in 0 ..< stock_slot_count(c) {
			if inside(pointer, stock_slot_box(w, h, c, s)) {
				return c, s, true
			}
		}
	}
	return 0, 0, false
}

// The rule of a place to drop: the drag may end here if the stack it carries can move to this slot.
stock_can_accept :: proc(data: rawptr, payload: dragdrop.Payload) -> bool {
	ref := cast(^Slot_Ref)data
	return inventory.can_move(stock_container(ref.stock, int(payload.a)), int(payload.b), stock_container(ref.stock, ref.container), ref.slot)
}

// Runs one frame of the screen. A press on a slot that holds something starts a drag, while it goes on the slot
// under the pointer is the one the drag is over, and letting go over a slot that takes the stack moves it there.
// Letting go anywhere else is a cancel. Returns whether the contents of either container changed.
stock_update :: proc(ui: ^Stock_Ui, stock: ^carry.Stock, pointer: [2]f32, pressed, released: bool, w, h: f32) -> (changed: bool) {
	bag_version, wall_version := stock.bag.version, stock.wall.version
	c, s, over := stock_slot_at(w, h, pointer)
	if pressed && over && !dragdrop.is_dragging(&ui.drag) {
		held := stock_container(stock, c)
		if !held.locked && s < held.size && held.slots[s].count > 0 {
			dragdrop.begin(&ui.drag, {i32(c), i32(s)})
		}
	}
	if dragdrop.is_dragging(&ui.drag) {
		ref := Slot_Ref{stock, c, s}
		target := dragdrop.Target{c * inventory.MAX_SLOTS + s, &ref, stock_can_accept}
		dragdrop.set_hover(&ui.drag, over ? &target : nil)
		if released {
			payload, id, dropped := dragdrop.end(&ui.drag)
			if dropped {
				inventory.move(stock_container(stock, int(payload.a)), int(payload.b), stock_container(stock, id / inventory.MAX_SLOTS), id % inventory.MAX_SLOTS)
			}
		}
	}
	return stock.bag.version != bag_version || stock.wall.version != wall_version
}

// What a dispenser is called and the color of its bottle: the compound in it, or grey and "empty".
dispenser_look :: proc(item: inventory.Item) -> (color: [4]u8, name: cstring) {
	if c := chemistry.compound_of(chemistry.Id(item.arg)); c != nil {
		return {c.color.r, c.color.g, c.color.b, 255}, chemistry.cname_of(chemistry.Id(item.arg))
	}
	return {70, 74, 80, 255}, "empty"
}

// Draws what a slot holds in a box: a bottle in the color of its liquid with a cap, and its name under it.
draw_stack :: proc(box: [4]f32, slot: inventory.Slot, alpha: u8) {
	color, name := dispenser_look(slot.item)
	bottle := [4]f32{box.x + box.z * 0.3, box.y + box.w * 0.14, box.z * 0.4, box.w * 0.5}
	rl.DrawRectangleRounded({bottle.x, bottle.y, bottle.z, bottle.w}, 0.25, 4, {color.r, color.g, color.b, alpha})
	rl.DrawRectangleRounded({bottle.x + bottle.z * 0.2, bottle.y - box.w * 0.07, bottle.z * 0.6, box.w * 0.09}, 0.3, 4, {70, 78, 90, alpha})
	draw_text_fit(name, i32(box.x + box.z * 0.5), i32(box.y + box.w * 0.72), i32(box.z) - 8, i32(max(f32(12), box.w * 0.15)), {240, 244, 248, alpha})
}

// Draws the screen over the lab: the bottle wall on the left and the bag on the right, as grids of slots with
// what is in them. While a stack is being dragged, the slots that take it have a green edge, the one it is over has
// a brighter one, red if it does not take it, the slot it came from is dimmed, and the stack follows the pointer.
draw_stock :: proc(w, h: f32, stock: ^carry.Stock, ui: ^Stock_Ui, pointer: [2]f32) {
	p := book_panel(w, h)
	rl.DrawRectangle(0, 0, i32(w), i32(h), {0, 0, 0, 150})
	rl.DrawRectangleRounded({p.x, p.y, p.z, p.w}, 0.02, 8, {14, 20, 28, 248})
	rl.DrawRectangleRoundedLinesEx({p.x, p.y, p.z, p.w}, 0.02, 8, 3, {230, 236, 242, 160})
	draw_button(book_close_button(w, h), "close", {120, 30, 30, 235}, {255, 200, 200, 255}, rl.RAYWHITE)
	close := book_close_button(w, h)
	head_font := i32(max(f32(22), h * 0.06))
	rl.DrawText("bottle wall and bag", i32(p.x) + 24, i32(close.y + (close.w - f32(head_font)) * 0.5), head_font, rl.RAYWHITE)
	rl.DrawText("drag a dispenser to move it", i32(p.x) + 24, i32(book_sub_y(w, h)), book_sub_font(h), {200, 212, 224, 255})

	dragging := dragdrop.is_dragging(&ui.drag)
	from_c, from_s := int(ui.drag.payload.a), int(ui.drag.payload.b)
	for c in 0 ..< 2 {
		gx, gy, _, _ := stock_grid(w, h, c)
		label: cstring = c == STOCK_WALL ? "bottle wall" : "bag"
		rl.DrawText(label, i32(gx), i32(gy) - i32(book_sub_font(h)) - 6, book_sub_font(h), {200, 212, 224, 255})
		held := stock_container(stock, c)
		for s in 0 ..< stock_slot_count(c) {
			box := stock_slot_box(w, h, c, s)
			rect := rl.Rectangle{box.x, box.y, box.z, box.w}
			rl.DrawRectangleRounded(rect, 0.1, 6, {26, 36, 48, 255})
			edge, thick := rl.Color{230, 236, 242, 90}, f32(2)
			if dragging {
				if inventory.can_move(stock_container(stock, from_c), from_s, held, s) {
					edge, thick = {70, 220, 120, 230}, 3
				}
				if ui.drag.hover == c * inventory.MAX_SLOTS + s {
					edge, thick = ui.drag.hover_ok ? rl.Color{150, 255, 180, 255} : rl.Color{240, 90, 90, 255}, 4
				}
			}
			rl.DrawRectangleRoundedLinesEx(rect, 0.1, 6, thick, edge)
			if s < held.size && held.slots[s].count > 0 {
				draw_stack(box, held.slots[s], dragging && c == from_c && s == from_s ? 80 : 255)
			}
			if c == STOCK_WALL {
				buf: [8]u8
				text := fmt.bprintf(buf[:7], "%d", s + 1)
				buf[len(text)] = 0
				rl.DrawText(cstring(raw_data(buf[:])), i32(box.x) + 6, i32(box.y) + 4, i32(max(f32(10), box.w * 0.12)), {160, 172, 186, 255})
			}
		}
	}
	if dragging {
		_, _, tile, _ := stock_grid(w, h, STOCK_WALL)
		src := stock_container(stock, from_c).slots[from_s]
		if src.count > 0 {
			size := tile * 0.9
			draw_stack({pointer.x - size * 0.5, pointer.y - size * 0.5, size, size}, src, 200)
		}
	}
}
