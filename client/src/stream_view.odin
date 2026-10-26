// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "stream_view.odin"
// ============================================================================

package main

import rlgl "vendor:raylib/rlgl"
import "carry"
import "chem"

DROP_RADIUS :: f32(0.012) // metres, a little over what a drop's share of liquid would fill

// Draws the liquid in the air as small solid diamonds in the color of the liquid,
// lighter on top and darker underneath. They are drawn by the batch renderer
// with no lighting, which is cheap enough for the few dozen there are, and
// without back-face culling so their winding does not matter.
stream_draw :: proc(st: ^carry.Stream) {
	if st.sim.count == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.TRIANGLES)
	r := DROP_RADIUS
	for i in 0 ..< st.sim.count {
		p := carry.stream_position(st, i)
		c := chem.compound_color(st.compound[i])
		top, bottom := Vec3{p.x, p.y + r, p.z}, Vec3{p.x, p.y - r, p.z}
		ring := [4]Vec3{{p.x + r, p.y, p.z}, {p.x, p.y, p.z + r}, {p.x - r, p.y, p.z}, {p.x, p.y, p.z - r}}
		shades := [4]f32{1.0, 0.92, 0.84, 0.95}
		for k in 0 ..< 4 {
			a, b := ring[k], ring[(k + 1) % 4]
			drop_face(top, a, b, c, shades[k])
			drop_face(bottom, b, a, c, shades[k] * 0.6)
		}
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
}

drop_face :: proc(a, b, c: Vec3, color: [3]f32, shade: f32) {
	rlgl.Color4ub(u8(clamp(color.r * shade, 0, 1) * 255), u8(clamp(color.g * shade, 0, 1) * 255), u8(clamp(color.b * shade, 0, 1) * 255), 255)
	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.Vertex3f(c.x, c.y, c.z)
}
