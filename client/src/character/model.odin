// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "model.odin"
// ============================================================================

package character

import "core:math"

// The parts of the character that move. Each is a soup built round its own pivot.
Part :: enum {
	Body, // the coat, with its lapels, pockets, and badge, and the legs of the trousers hang from it
	Head, // with goggles, mask, and the quiff
	Arm_L, // the character's left, which is -x for a character that faces -z
	Arm_R,
	Leg_L,
	Leg_R,
}

HEIGHT :: f32(1.94) // the top of the quiff above the feet. The eyes are at about 1.62.

// The colours of one character. The coat and skin are the same for everyone, and the trim and
// the hair tell the players apart.
Palette :: struct {
	coat:  [4]u8,
	shirt: [4]u8,
	trim:  [4]u8,
	hair:  [4]u8,
	skin:  [4]u8,
	mask:  [4]u8,
	lens:  [4]u8,
}

TRIMS :: [8][4]u8{
	{56, 112, 196, 255}, // blue, as in the design
	{196, 64, 64, 255},
	{64, 160, 96, 255},
	{226, 142, 48, 255},
	{140, 80, 190, 255},
	{48, 170, 180, 255},
	{216, 184, 48, 255},
	{212, 100, 160, 255},
}

palette_for :: proc(id: u8) -> Palette {
	trims := TRIMS
	trim := trims[int(id) % len(trims)]
	return {
		coat  = {214, 226, 214, 255},
		shirt = {170, 206, 214, 255},
		trim  = trim,
		hair  = {trim.r / 2, trim.g / 2, trim.b / 2 + 20, 255},
		skin  = {220, 230, 214, 255},
		mask  = {58, 64, 78, 255},
		lens  = {200, 225, 240, 255},
	}
}

Model :: struct {
	parts: [Part]Soup,
}

// Where each part turns about, in the space of the character with its feet at the origin.
part_pivot :: proc(p: Part) -> Vec3 {
	switch p {
	case .Body:
		return {0, 0, 0}
	case .Head:
		return {0, 1.4, 0}
	case .Arm_L:
		return {-0.34, 1.22, 0}
	case .Arm_R:
		return {0.34, 1.22, 0}
	case .Leg_L:
		return {-0.13, 0.38, 0}
	case .Leg_R:
		return {0.13, 0.38, 0}
	}
	return {}
}

// A box or cylinder placed at `center` and turned about y, x, then z, in that order of applying.
place :: proc(center: Vec3, rx: f32 = 0, ry: f32 = 0, rz: f32 = 0) -> Mat {
	return mat_mul(mat_translate(center), mat_mul(mat_rotate_y(ry), mat_mul(mat_rotate_x(rx), mat_rotate_z(rz))))
}

// Builds all the parts for a palette. Everything is written in the space of the character, with
// the feet at the origin and the front toward -z, and moved to the pivot of its part.
model_build :: proc(m: ^Model, pal: Palette) {
	m^ = {}
	body := &m.parts[.Body]
	head := &m.parts[.Head]

	// Moves a placement from the space of the character to the space of a part.
	into :: proc(p: Part, center: Vec3) -> Vec3 {
		return center - part_pivot(p)
	}

	// The coat: a round body, wider than it is deep, with a vest down the front, lapels and
	// pockets in the trim colour, a collar, and a badge on a strap. The details sit a little into
	// the surface because the facets of the body are inside the true ellipsoid.
	soup_ellipsoid(body, {0, 0.88, 0}, {0.46, 0.5, 0.38}, 8, 6, pal.coat)
	soup_box(body, place({0, 0.9, -0.34}), {0.26, 0.6, 0.06}, pal.shirt)
	soup_box(body, place({-0.15, 0.98, -0.35}, 0, 0, -0.18), {0.1, 0.52, 0.04}, pal.trim)
	soup_box(body, place({0.15, 0.98, -0.35}, 0, 0, 0.18), {0.1, 0.52, 0.04}, pal.trim)
	soup_box(body, place({0, 1.37, -0.1}), {0.22, 0.07, 0.16}, pal.shirt)
	soup_box(body, place({-0.27, 0.62, -0.23}), {0.17, 0.16, 0.04}, pal.trim)
	soup_box(body, place({0.27, 0.62, -0.23}), {0.17, 0.16, 0.04}, pal.trim)
	soup_box(body, place({0, 1.1, -0.375}), {0.03, 0.3, 0.015}, pal.trim)
	soup_box(body, place({0, 0.95, -0.385}), {0.08, 0.11, 0.03}, pal.trim)
	soup_box(body, place({0.3, 0.74, -0.24}), {0.015, 0.09, 0.015}, pal.hair)

	// The head: round, with goggles, a mask over the lower face with a round filter, and a quiff
	// of three boxes that rise and lean forward.
	h := into(.Head, {0, 1.58, 0})
	soup_ellipsoid(head, h, {0.2, 0.2, 0.2}, 10, 6, pal.skin)
	for side in ([2]f32{-1, 1}) {
		soup_box(head, place(into(.Head, {side * 0.095, 1.62, -0.18})), {0.16, 0.11, 0.05}, pal.trim)
		soup_box(head, place(into(.Head, {side * 0.095, 1.62, -0.185})), {0.12, 0.075, 0.055}, pal.lens)
		soup_box(head, place(into(.Head, {side * 0.09, 1.615, -0.19})), {0.035, 0.035, 0.06}, pal.hair)
	}
	soup_box(head, place(into(.Head, {0, 1.63, -0.185})), {0.04, 0.03, 0.05}, pal.trim)
	soup_box(head, place(into(.Head, {0, 1.47, -0.15})), {0.28, 0.13, 0.1}, pal.mask)
	soup_cylinder(head, mat_mul(mat_translate(into(.Head, {0.07, 1.47, -0.205})), mat_rotate_x(math.PI * 0.5)), 0.05, 0.04, 8, pal.trim)
	soup_box(head, place(into(.Head, {0, 1.77, -0.02}), 0.2), {0.12, 0.06, 0.22}, pal.hair)
	soup_box(head, place(into(.Head, {0, 1.83, -0.04}), 0.5), {0.09, 0.06, 0.16}, pal.hair)
	soup_box(head, place(into(.Head, {0, 1.88, -0.07}), 0.9), {0.06, 0.05, 0.12}, pal.hair)

	// The arms, each hanging straight down from its shoulder: a sleeve, a cuff in the trim colour,
	// and a round hand. The pivot is the origin, so they turn as they are.
	for part in ([2]Part{.Arm_L, .Arm_R}) {
		s := &m.parts[part]
		soup_cylinder(s, mat_translate({0, -0.28, 0}), 0.075, 0.56, 6, pal.coat)
		soup_cylinder(s, mat_translate({0, -0.52, 0}), 0.085, 0.05, 6, pal.trim)
		soup_ellipsoid(s, {0, -0.64, 0}, {0.09, 0.09, 0.09}, 6, 4, pal.skin)
	}

	// The legs, hanging from the hip: a trouser leg and a flat shoe in the trim colour.
	for part in ([2]Part{.Leg_L, .Leg_R}) {
		s := &m.parts[part]
		soup_box(s, mat_translate({0, -0.175, 0}), {0.15, 0.35, 0.17}, pal.shirt)
		soup_box(s, mat_translate({0, -0.35, -0.045}), {0.19, 0.06, 0.3}, pal.trim)
	}
}

// The matrix that puts the whole character on the floor at `feet`, facing the heading `yaw`,
// where yaw 0 faces -z and a quarter turn faces +x, as everywhere in the game.
root_matrix :: proc(feet: Vec3, yaw: f32) -> Mat {
	return mat_mul(mat_translate(feet), mat_rotate_y(-yaw))
}
