// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "art_codec_test.odin"
// ============================================================================

package carry

import "core:testing"

// What the Rust codec, `tv_proto::art`, made of this drawing: flat colors with a disc and a
// band, so it is run-length, with the palette of the lab. The test builds the same drawing
// here and the bytes must be the same.
RUST_FLAT :: "01cdd7e11414186e7078c8ccd2fafafac82828f07828f5cd328cc83c28a05028bebe3278dc463cbe9646c8e65aaa8c5a32006f5905230000d60005310000c900053d0000bf0005450000b700054d0000af0005550000a800055b0000a300055f00009e00056500009900056900009400056f00008f00057300008b00057700008800057900008500057d00008200057f00007f00058300007c00058500007900058900007600058b00007400058d00007200058f00007000059100006e00059300006c00059500006b00059500006a00059700006800059900006700059900006600059b00006500059b00006400059d00006300059d00006200059f00006100059f00006100059f00006100059f00006100059f00006100059f00006100059f00006100059f00006100059f00006100059f00006100059f00006100059f00006100059f00006200059d00006300059d00006400059b00006500059b00006600059900006700059900006800059700006a00059500006b00059500006c00059300006e00059100007000058f00007200058d00007400058b00007600058900007900058500007c00058300007f00057f00008200057d00008500057900008800057700008b00057300008f00056f00009400056900009900056500009e00055f0000a300055b0000a80005550000af00054d0000b70005450000bf00053d0000c90005310000d600052300006e21090037"

// The same, for a drawing of noise, which is raw: the length and a hash of the bytes.
RUST_NOISY_LEN :: 32817
RUST_NOISY_HASH :: u64(0xc4ab4cbd6b43ea70)

fnv :: proc(bytes: []u8) -> u64 {
	h := u64(0xcbf29ce484222325)
	for b in bytes {
		h ~= u64(b)
		h *= 0x100000001b3
	}
	return h
}

flat_drawing :: proc(c: ^Canvas) {
	for y in 0 ..< CANVAS_H {
		for x in 0 ..< CANVAS_W {
			dx, dy := x - 128, y - 128
			idx := u8(0)
			if dx * dx / 4 + dy * dy < 1600 {
				idx = 5
			} else if y > 200 {
				idx = 9
			}
			c.px[y * CANVAS_W + x] = idx
		}
	}
}

noisy_drawing :: proc(c: ^Canvas) {
	for y in 0 ..< CANVAS_H {
		for x in 0 ..< CANVAS_W {
			c.px[y * CANVAS_W + x] = u8(((x * 7 + y * 13) ~ (x >> 2)) & 15)
		}
	}
}

@(test)
a_flat_drawing_encodes_to_the_same_bytes_as_the_rust_codec :: proc(t: ^testing.T) {
	c := new(Canvas)
	defer free(c)
	flat_drawing(c)
	bytes := art_encode(c)
	defer delete(bytes)
	testing.expect_value(t, bytes[0], ART_FORMAT_RLE)
	got := hex_encode(bytes)
	defer delete(got)
	testing.expect_value(t, got, RUST_FLAT)
}

@(test)
a_noisy_drawing_is_raw_and_the_same_as_the_rust_codec :: proc(t: ^testing.T) {
	c := new(Canvas)
	defer free(c)
	noisy_drawing(c)
	bytes := art_encode(c)
	defer delete(bytes)
	testing.expect_value(t, bytes[0], ART_FORMAT_RAW)
	testing.expect_value(t, len(bytes), RUST_NOISY_LEN)
	testing.expect_value(t, len(bytes), ART_MAX_ENCODED)
	testing.expect_value(t, fnv(bytes), RUST_NOISY_HASH)
}

@(test)
what_the_rust_codec_made_decodes_to_the_same_drawing :: proc(t: ^testing.T) {
	bytes, ok := hex_decode(RUST_FLAT)
	defer delete(bytes)
	testing.expect(t, ok, "the hex is hex")
	c, want := new(Canvas), new(Canvas)
	defer free(c)
	defer free(want)
	testing.expect(t, art_decode(bytes, c), "it decodes")
	flat_drawing(want)
	testing.expect(t, c.px == want.px, "to the drawing it was made from")
}

@(test)
both_formats_round_trip_and_a_blank_drawing_is_tiny :: proc(t: ^testing.T) {
	for kind in 0 ..< 3 {
		c, back := new(Canvas), new(Canvas)
		defer free(c)
		defer free(back)
		switch kind {
		case 0:
			flat_drawing(c)
		case 1:
			noisy_drawing(c)
		}
		bytes := art_encode(c)
		defer delete(bytes)
		testing.expect(t, art_decode(bytes, back), "it decodes")
		testing.expect(t, back.px == c.px, "to what it was")
		if kind == 2 {
			testing.expect(t, len(bytes) < 60, "a blank drawing is a few bytes")
		}
	}
}

@(test)
bad_bytes_are_refused_and_leave_the_drawing_alone :: proc(t: ^testing.T) {
	c := new(Canvas)
	defer free(c)
	flat_drawing(c)
	keep := c.px
	good, _ := hex_decode(RUST_FLAT)
	defer delete(good)

	testing.expect(t, !art_decode(nil, c), "nothing")
	testing.expect(t, !art_decode(good[:20], c), "too short for the palette")
	truncated := good[:len(good) - 3]
	testing.expect(t, !art_decode(truncated, c), "a run is missing")
	extra := make([]u8, len(good) + 1)
	defer delete(extra)
	copy(extra, good)
	testing.expect(t, !art_decode(extra, c), "something left over")
	wrong := make([]u8, len(good))
	defer delete(wrong)
	copy(wrong, good)
	wrong[0] = 7
	testing.expect(t, !art_decode(wrong, c), "a format that is neither")
	copy(wrong, good)
	wrong[1 + 48] = 16 // a color outside the palette
	testing.expect(t, !art_decode(wrong, c), "a color that is not in the palette")
	copy(wrong, good)
	wrong[1 + 48 + 1], wrong[1 + 48 + 2] = 0, 0 // a run of nothing
	testing.expect(t, !art_decode(wrong, c), "a run of nothing")
	copy(wrong, good)
	wrong[1 + 48 + 1], wrong[1 + 48 + 2] = 0xFF, 0xFF // a run past the end
	wrong[1 + 48 + 4], wrong[1 + 48 + 5] = 0xFF, 0xFF
	testing.expect(t, !art_decode(wrong, c), "runs past the end of the drawing")
	raw_short := make([]u8, 1 + 48 + 100)
	defer delete(raw_short)
	testing.expect(t, !art_decode(raw_short, c), "a raw drawing that is short")
	testing.expect(t, c.px == keep, "and the drawing was never touched")
}

@(test)
hex_goes_both_ways_and_refuses_bad_text :: proc(t: ^testing.T) {
	text := hex_encode([]u8{0, 1, 0xab, 0xff})
	defer delete(text)
	testing.expect_value(t, text, "0001abff")
	back, ok := hex_decode("0001ABff")
	defer delete(back)
	testing.expect(t, ok && len(back) == 4 && back[2] == 0xab && back[3] == 0xff, "either case")
	_, odd := hex_decode("abc")
	testing.expect(t, !odd, "an odd length")
	_, bad := hex_decode("zz")
	testing.expect(t, !bad, "not hexadecimal")
	empty, fine := hex_decode("")
	testing.expect(t, fine && len(empty) == 0, "nothing is nothing")
}

@(test)
a_run_of_nothing_is_refused_even_when_the_rest_adds_up :: proc(t: ^testing.T) {
	good, _ := hex_decode(RUST_FLAT)
	defer delete(good)
	head := 1 + ART_PALETTE_LEN * 3
	padded := make([]u8, len(good) + 3)
	defer delete(padded)
	copy(padded, good[:head])
	padded[head], padded[head + 1], padded[head + 2] = 3, 0, 0 // a run of nothing, first
	copy(padded[head + 3:], good[head:])
	c := new(Canvas)
	defer free(c)
	testing.expect(t, !art_decode(padded, c), "the Rust decoder refuses it, so this one does")
}

@(test)
a_decoded_drawing_is_marked_as_changed_so_what_shows_it_updates :: proc(t: ^testing.T) {
	bytes, _ := hex_decode(RUST_FLAT)
	defer delete(bytes)
	c := new(Canvas)
	defer free(c)
	testing.expect(t, art_decode(bytes, c), "it decodes")
	testing.expect(t, c.version > 0 && c.has_dirty, "and the whole drawing counts as changed")
	testing.expect_value(t, c.dirty, [4]int{0, 0, CANVAS_W - 1, CANVAS_H - 1})
}
