// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "art_view.odin"
// ============================================================================

package main

import "carry"
import rl "vendor:raylib"

// The texture a drawing is shown with: 256 by 256 pixels, RGBA, with no alpha where
// there is no paint. It follows one drawing and is brought up to date when the
// drawing changes, not made again.
Art_Texture :: struct {
	tex:     rl.Texture2D,
	loaded:  bool,
	art_id:  u16, // the drawing it shows now, 0 for none
	version: u32, // the version of that drawing it was last brought up to
}

// Room for the pixels of one drawing, to turn a drawing into RGBA in.
art_scratch_alloc :: proc() -> []u8 {
	return (cast([^]u8)rl_alloc(carry.CANVAS_W * carry.CANVAS_H * 4))[:carry.CANVAS_W * carry.CANVAS_H * 4]
}

art_scratch_free :: proc(scratch: []u8) {
	rl.MemFree(raw_data(scratch))
}

art_texture_make :: proc() -> rl.Texture2D {
	pixels := cast([^]u8)rl_alloc(carry.CANVAS_W * carry.CANVAS_H * 4) // all zero, so all no paint
	img := rl.Image {
		data    = rawptr(pixels),
		width   = carry.CANVAS_W,
		height  = carry.CANVAS_H,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	tex := rl.LoadTextureFromImage(img)
	rl.MemFree(rawptr(pixels))
	rl.SetTextureFilter(tex, .BILINEAR) // no mipmaps, so a drawing wrapping round the seam has no line in it
	rl.SetTextureWrap(tex, .REPEAT)
	return tex
}

art_texture_unload :: proc(a: ^Art_Texture) {
	if a.loaded {
		rl.UnloadTexture(a.tex)
	}
	a^ = {}
}

// Brings the texture up to date with drawing `id` of the store, and says whether
// there is a drawing to show. A different drawing is sent whole, and a change to the
// same one is sent as the rectangle that changed. Nothing is sent when nothing has
// changed.
art_texture_sync :: proc(a: ^Art_Texture, store: ^carry.Art_Store, id: u16, scratch: []u8) -> bool {
	c := carry.art_get(store, id)
	if c == nil {
		a.art_id = 0
		return false
	}
	if !a.loaded {
		a.tex = art_texture_make()
		a.loaded = true
		a.art_id = 0
	}
	if a.art_id != id {
		carry.canvas_to_rgba(c, 0, 0, carry.CANVAS_W - 1, carry.CANVAS_H - 1, scratch)
		rl.UpdateTexture(a.tex, raw_data(scratch))
		carry.canvas_dirty_take(c)
		a.art_id, a.version = id, c.version
	} else if a.version != c.version {
		if rect, ok := carry.canvas_dirty_take(c); ok {
			w, h := rect[2] - rect[0] + 1, rect[3] - rect[1] + 1
			carry.canvas_to_rgba(c, rect[0], rect[1], rect[2], rect[3], scratch[:w * h * 4])
			rl.UpdateTextureRec(a.tex, rl.Rectangle{f32(rect[0]), f32(rect[1]), f32(w), f32(h)}, raw_data(scratch))
		}
		a.version = c.version
	}
	return true
}
