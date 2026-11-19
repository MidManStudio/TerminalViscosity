// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stream_view.odin"
// ============================================================================

package main

import "carry"
import "chem"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

DROP_RADIUS :: f32(0.012) // metres, the radius of a drop that stands for the usual 3.4 ml
JET_SIDES :: 6 // sides of the tube a jet is drawn as
JET_ALPHA :: u8(225) // the liquid shows a little of what is behind it
MAX_DRAW_VERTICES :: 7000 // the most the stream puts in one batch, which the smallest batch of raylib holds

// Draws the liquid in the air and what has landed. Puddles come first, flat on the surfaces they lie on, each a
// quad that the spill shader makes into a wandering shape that dissolves away. Drops that are part of a stream
// are drawn as one smooth tube through them, joined to the lip or the tap they came from, with a highlight along
// it and brighter edges, in the color of the liquid. Drops that are alone, such as the spray of a splash, are
// drawn as round beads, quads that face the camera and that the spill shader makes into lit balls. The tubes are
// drawn by the batch renderer with the lighting worked out for each vertex, which is cheap enough for the few
// dozen drops there are, and all of it without back-face culling so that winding does not matter.
stream_draw :: proc(st: ^carry.Stream, view: carry.View, shader: rl.Shader, shader_ok: bool) {
	if st.spill.count == 0 && st.sim.count == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	if st.spill.count > 0 {
		draw_puddles(&st.spill, shader, shader_ok)
	}
	if st.sim.count > 0 {
		jet: carry.Jet
		carry.jet_build(st, &jet)
		rlgl.Begin(rlgl.TRIANGLES)
		verts := 0
		for s in 0 ..< jet.strands {
			draw_strand(st, &jet, s, view.eye, &verts)
		}
		if !shader_ok {
			for i in 0 ..< st.sim.count {
				if jet.loose[i] && !st.puddled[i] && verts + 24 <= MAX_DRAW_VERTICES {
					draw_bead(carry.stream_position(st, i), chem.compound_color(st.compound[i]), st.ml[i])
					verts += 24
				}
			}
		}
		rlgl.End()
		rlgl.DrawRenderBatchActive()
		if shader_ok {
			draw_beads(st, &jet, view, shader)
		}
	}
	rlgl.EnableBackfaceCulling()
}

// Draws every puddle that has landed as a flat quad, a little over its surface. The quad is a little wider than
// the puddle, since the shader draws the edge wandering inside it. The alpha is how much of the puddle is left,
// which the shader turns into the dissolve. Without the shader a puddle is a flat disc that only fades.
draw_puddles :: proc(sp: ^carry.Spill, shader: rl.Shader, shader_ok: bool) {
	if shader_ok {
		rl.BeginShaderMode(shader)
	}
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< sp.count {
		p := sp.puddles[i]
		if !carry.puddle_landed(p) {
			continue
		}
		c := chem.compound_color(p.compound)
		life := 1 - carry.puddle_dissolve(p)
		a := u8(life * 255)
		y := p.pos.y + 0.003
		if shader_ok {
			half := p.radius * 1.15
			corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
			order := [6]int{0, 1, 2, 0, 2, 3}
			for k in order {
				rlgl.Color4ub(u8(c.r * 255), u8(c.g * 255), u8(c.b * 255), a)
				rlgl.TexCoord2f(corners[k].x, corners[k].y)
				rlgl.Vertex3f(p.pos.x + corners[k].x * half, y, p.pos.z + corners[k].y * half)
			}
		} else {
			for k in 0 ..< 8 {
				a0, a1 := f32(k) * math.PI / 4, f32(k + 1) * math.PI / 4
				rlgl.Color4ub(u8(c.r * 230), u8(c.g * 230), u8(c.b * 230), u8(f32(a) * 0.7))
				rlgl.Vertex3f(p.pos.x, y, p.pos.z)
				rlgl.Vertex3f(p.pos.x + math.cos(a0) * p.radius, y, p.pos.z + math.sin(a0) * p.radius)
				rlgl.Vertex3f(p.pos.x + math.cos(a1) * p.radius, y, p.pos.z + math.sin(a1) * p.radius)
			}
		}
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	if shader_ok {
		rl.EndShaderMode()
	}
}

// Draws the drops that are in no stream and have not landed as round beads: quads that face the camera, as wide as
// the liquid they stand for.
draw_beads :: proc(st: ^carry.Stream, jet: ^carry.Jet, view: carry.View, shader: rl.Shader) {
	rl.BeginShaderMode(shader)
	rlgl.Begin(rlgl.TRIANGLES)
	corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
	order := [6]int{0, 1, 2, 0, 2, 3}
	for i in 0 ..< st.sim.count {
		if !jet.loose[i] || st.puddled[i] {
			continue
		}
		p := carry.stream_position(st, i)
		r := bead_radius(st.ml[i]) * 1.1
		c := chem.compound_color(st.compound[i])
		for k in order {
			rlgl.Color4ub(u8(c.r * 255), u8(c.g * 255), u8(c.b * 255), JET_ALPHA)
			rlgl.TexCoord2f(10 + corners[k].x, corners[k].y)
			at := p + view.right * (corners[k].x * r) + view.up * (corners[k].y * r)
			rlgl.Vertex3f(at.x, at.y, at.z)
		}
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rl.EndShaderMode()
}

// How wide a bead is for the liquid it stands for, in metres.
bead_radius :: proc(ml: f32) -> f32 {
	return clamp(DROP_RADIUS * math.pow(ml / carry.DROP_ML, 1.0 / 3.0), 0.006, 0.03)
}

// The color of a point of the liquid with the surface turned to `n`, seen from the direction `to_eye`: its own
// color made lighter on the side to the light, a sharp highlight where the surface faces halfway between light and
// eye, and a glow at the edges, where the surface is turned away, as clear liquid has.
jet_shade :: proc(base: [3]f32, n, to_eye: Vec3) -> (r, g, b, a: u8) {
	light := linalg.normalize(Vec3{0.35, 0.85, 0.4})
	v := linalg.normalize(to_eye)
	diffuse := 0.55 + 0.45 * max(linalg.dot(n, light), 0)
	half := linalg.normalize(light + v)
	spec := math.pow(max(linalg.dot(n, half), 0), 24) * 0.6
	rim := math.pow(1 - clamp(abs(linalg.dot(n, v)), 0, 1), 3) * 0.3
	return u8(clamp(base.r * diffuse + spec + rim, 0, 1) * 255),
		u8(clamp(base.g * diffuse + spec + rim, 0, 1) * 255),
		u8(clamp(base.b * diffuse + spec + rim, 0, 1) * 255),
		JET_ALPHA
}

// A small bead for a drop that is not in a stream: a diamond, lighter on top and darker underneath, as wide as
// the liquid it stands for.
draw_bead :: proc(p: Vec3, c: [3]f32, ml: f32) {
	r := bead_radius(ml)
	top, bottom := Vec3{p.x, p.y + r, p.z}, Vec3{p.x, p.y - r, p.z}
	ring := [4]Vec3{{p.x + r, p.y, p.z}, {p.x, p.y, p.z + r}, {p.x - r, p.y, p.z}, {p.x, p.y, p.z - r}}
	shades := [4]f32{1.0, 0.92, 0.84, 0.95}
	for k in 0 ..< 4 {
		a, b := ring[k], ring[(k + 1) % 4]
		bead_face(top, a, b, c, shades[k])
		bead_face(bottom, b, a, c, shades[k] * 0.6)
	}
}

bead_face :: proc(a, b, c: Vec3, color: [3]f32, shade: f32) {
	rlgl.Color4ub(u8(clamp(color.r * shade, 0, 1) * 255), u8(clamp(color.g * shade, 0, 1) * 255), u8(clamp(color.b * shade, 0, 1) * 255), JET_ALPHA)
	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(c.x, c.y, c.z)
}

// One vertex of a ring of the tube.
Ring_Vertex :: struct {
	pos:   Vec3,
	color: [4]u8,
}

// A direction at right angles to `t`.
perpendicular :: proc(t: Vec3) -> Vec3 {
	axis := abs(t.y) > 0.9 ? Vec3{1, 0, 0} : Vec3{0, 1, 0}
	return linalg.normalize(linalg.cross(t, axis))
}

// Draws jet number `s` as a tube with `JET_SIDES` sides: a ring of vertices at each point, joined to the ring
// before, with the rings turned along the curve without twisting. The end that is not joined to a mouth is
// closed with a point just past it, so it is rounded, and so is the oldest end.
draw_strand :: proc(st: ^carry.Stream, jet: ^carry.Jet, s: int, eye: Vec3, verts: ^int) {
	first, n := int(jet.strand_first[s]), int(jet.strand_len[s])
	if n < 2 {
		return
	}
	pts := jet.points[first:first + n]
	prev: [JET_SIDES]Ring_Vertex
	frame := Vec3{0, 0, 1}
	tangent := Vec3{0, -1, 0}
	for k in 0 ..< n {
		heading := pts[min(k + 1, n - 1)].pos - pts[max(k - 1, 0)].pos
		if linalg.length(heading) > 1e-6 {
			tangent = linalg.normalize(heading)
		}
		if k == 0 {
			frame = perpendicular(tangent)
		} else {
			frame -= tangent * linalg.dot(frame, tangent)
			frame = linalg.length(frame) > 1e-4 ? linalg.normalize(frame) : perpendicular(tangent)
		}
		side := linalg.cross(tangent, frame)
		color := chem.compound_color(st.compound[pts[k].drop])
		ring: [JET_SIDES]Ring_Vertex
		for i in 0 ..< JET_SIDES {
			angle := f32(i) * 2 * math.PI / JET_SIDES
			normal := frame * math.cos(angle) + side * math.sin(angle)
			pos := pts[k].pos + normal * pts[k].radius
			r, g, b, a := jet_shade(color, normal, eye - pos)
			ring[i] = {pos, {r, g, b, a}}
		}
		if k == 0 {
			tip := pts[0].pos - tangent * pts[0].radius * 0.8
			if verts^ + 3 * JET_SIDES > MAX_DRAW_VERTICES {
				return
			}
			close_ring(ring, tip, color, eye, tangent)
			verts^ += 3 * JET_SIDES
		} else {
			if verts^ + 6 * JET_SIDES > MAX_DRAW_VERTICES {
				return
			}
			for i in 0 ..< JET_SIDES {
				j := (i + 1) % JET_SIDES
				ring_vertex(prev[i])
				ring_vertex(prev[j])
				ring_vertex(ring[j])
				ring_vertex(prev[i])
				ring_vertex(ring[j])
				ring_vertex(ring[i])
			}
			verts^ += 6 * JET_SIDES
		}
		if k == n - 1 && !jet.to_mouth[s] && verts^ + 3 * JET_SIDES <= MAX_DRAW_VERTICES {
			tip := pts[k].pos + tangent * pts[k].radius * 0.8
			close_ring(ring, tip, color, eye, -tangent)
			verts^ += 3 * JET_SIDES
		}
		prev = ring
	}
}

ring_vertex :: proc(v: Ring_Vertex) {
	rlgl.Color4ub(v.color.r, v.color.g, v.color.b, v.color.a)
	rlgl.Vertex3f(v.pos.x, v.pos.y, v.pos.z)
}

// Closes the end of a tube with a fan from `tip` to its ring. `out` is the way the end faces.
close_ring :: proc(ring: [JET_SIDES]Ring_Vertex, tip: Vec3, color: [3]f32, eye: Vec3, out: Vec3) {
	r, g, b, a := jet_shade(color, linalg.normalize(out), eye - tip)
	for i in 0 ..< JET_SIDES {
		j := (i + 1) % JET_SIDES
		ring_vertex(ring[i])
		ring_vertex(ring[j])
		rlgl.Color4ub(r, g, b, a)
		rlgl.Vertex3f(tip.x, tip.y, tip.z)
	}
}
