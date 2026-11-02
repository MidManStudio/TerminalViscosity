// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "art_codec.odin"
// ============================================================================

package carry

import "../lab"
import "core:mem"

ART_PALETTE_LEN :: 16
ART_MAX_ENCODED :: 1 + ART_PALETTE_LEN * 3 + CANVAS_W * CANVAS_H / 2 // the most an encoded drawing can be

ART_FORMAT_RAW :: 0
ART_FORMAT_RLE :: 1

// Encodes a drawing in the byte layout of `tv_proto::art`, so the same bytes can be saved
// on the phone and, later, sent to the server and decoded there. A format byte, then the
// 16 colors of the palette as three bytes each, then either the pixels two to a byte, the
// first in the low half, or runs of one byte of color and two bytes, low first, of
// length. Whichever of the two is shorter is used, run-length only if it is strictly
// shorter, as the Rust one does. The palette written is that of the lab.
art_encode :: proc(c: ^Canvas, allocator := context.allocator) -> []u8 {
	rle := make([dynamic]u8, 0, 512, context.temp_allocator)
	append(&rle, ART_FORMAT_RLE)
	for k in 0 ..< ART_PALETTE_LEN {
		rgba := lab.palette_color(k)
		append(&rle, rgba.r, rgba.g, rgba.b)
	}
	i := 0
	for i < len(c.px) {
		idx := c.px[i] & 0x0F
		run := 1
		for i + run < len(c.px) && c.px[i + run] & 0x0F == idx && run < 65535 {
			run += 1
		}
		append(&rle, idx, u8(run & 0xFF), u8(run >> 8))
		i += run
	}
	if len(rle) < ART_MAX_ENCODED {
		out := make([]u8, len(rle), allocator)
		copy(out, rle[:])
		return out
	}
	out := make([]u8, ART_MAX_ENCODED, allocator)
	out[0] = ART_FORMAT_RAW
	for k in 0 ..< ART_PALETTE_LEN {
		rgba := lab.palette_color(k)
		out[1 + k * 3], out[2 + k * 3], out[3 + k * 3] = rgba.r, rgba.g, rgba.b
	}
	for p in 0 ..< len(c.px) / 2 {
		out[1 + ART_PALETTE_LEN * 3 + p] = (c.px[p * 2] & 0x0F) | ((c.px[p * 2 + 1] & 0x0F) << 4)
	}
	return out
}

// Decodes either format into `c`, and says whether it was well formed. It rejects what
// the Rust decoder rejects: a format byte that is neither, input that is too short, a
// run of nothing or past the end of the drawing or of a color outside the palette, and
// anything left over. The palette in the bytes is skipped, because a drawing here is
// indices and the palette is the lab's. `c` is left as it was if the bytes are bad.
art_decode :: proc(bytes: []u8, c: ^Canvas) -> bool {
	head := 1 + ART_PALETTE_LEN * 3
	if len(bytes) < head {
		return false
	}
	px := new([CANVAS_W * CANVAS_H]u8, context.temp_allocator)
	switch bytes[0] {
	case ART_FORMAT_RAW:
		if len(bytes) != head + CANVAS_W * CANVAS_H / 2 {
			return false
		}
		for p in 0 ..< CANVAS_W * CANVAS_H / 2 {
			b := bytes[head + p]
			px[p * 2], px[p * 2 + 1] = b & 0x0F, b >> 4
		}
	case ART_FORMAT_RLE:
		at, n := head, 0
		for n < len(px) {
			if at + 3 > len(bytes) {
				return false
			}
			idx, run := int(bytes[at]), int(bytes[at + 1]) | int(bytes[at + 2]) << 8
			at += 3
			if idx >= ART_PALETTE_LEN || run == 0 || n + run > len(px) {
				return false
			}
			for k in 0 ..< run {
				px[n + k] = u8(idx)
			}
			n += run
		}
		if at != len(bytes) {
			return false
		}
	case:
		return false
	}
	mem.copy(&c.px, px, len(px))
	mark_dirty(c, 0, 0, CANVAS_W - 1, CANVAS_H - 1)
	return true
}

HEX_DIGITS :: "0123456789abcdef"

hex_encode :: proc(bytes: []u8, allocator := context.allocator) -> string {
	digits := HEX_DIGITS
	out := make([]u8, len(bytes) * 2, allocator)
	for b, i in bytes {
		out[i * 2], out[i * 2 + 1] = digits[b >> 4], digits[b & 0x0F]
	}
	return string(out)
}

hex_value :: proc(ch: u8) -> (v: u8, ok: bool) {
	switch ch {
	case '0' ..= '9':
		return ch - '0', true
	case 'a' ..= 'f':
		return ch - 'a' + 10, true
	case 'A' ..= 'F':
		return ch - 'A' + 10, true
	}
	return 0, false
}

// Reads hexadecimal text back into bytes. False if the length is odd or a character is
// not a hexadecimal digit.
hex_decode :: proc(text: string, allocator := context.allocator) -> (bytes: []u8, ok: bool) {
	if len(text) % 2 != 0 {
		return nil, false
	}
	out := make([]u8, len(text) / 2, allocator)
	for i in 0 ..< len(out) {
		hi, a := hex_value(text[i * 2])
		lo, b := hex_value(text[i * 2 + 1])
		if !a || !b {
			delete(out, allocator)
			return nil, false
		}
		out[i] = hi << 4 | lo
	}
	return out, true
}
