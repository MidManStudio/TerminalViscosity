// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "blueprint_view.odin"
// ============================================================================

package main

import "carry"
import "lab"
import rlgl "vendor:raylib/rlgl"

BLUEPRINT_EDGE :: f32(0.004) // how thick the edges of the copy are drawn, in metres

// Where the corners of a box are, from its middle and its size.
Blueprint_Box :: struct {
	x0, y0, z0, x1, y1, z1: f32,
}

blueprint_box_of :: proc(cx, cy, cz, sx, sy, sz: f32) -> Blueprint_Box {
	return {cx - sx * 0.5, cy - sy * 0.5, cz - sz * 0.5, cx + sx * 0.5, cy + sy * 0.5, cz + sz * 0.5}
}

// The six faces of a box as quads, in the color that is current. Back faces are drawn too, so the order of the corners
// does not matter.
blueprint_box_quads :: proc(b: Blueprint_Box, c: [4]u8) {
	rlgl.Color4ub(c.r, c.g, c.b, c.a)
	// Top and bottom.
	rlgl.Vertex3f(b.x0, b.y1, b.z0)
	rlgl.Vertex3f(b.x0, b.y1, b.z1)
	rlgl.Vertex3f(b.x1, b.y1, b.z1)
	rlgl.Vertex3f(b.x1, b.y1, b.z0)
	rlgl.Vertex3f(b.x0, b.y0, b.z0)
	rlgl.Vertex3f(b.x1, b.y0, b.z0)
	rlgl.Vertex3f(b.x1, b.y0, b.z1)
	rlgl.Vertex3f(b.x0, b.y0, b.z1)
	// North and south.
	rlgl.Vertex3f(b.x0, b.y0, b.z0)
	rlgl.Vertex3f(b.x0, b.y1, b.z0)
	rlgl.Vertex3f(b.x1, b.y1, b.z0)
	rlgl.Vertex3f(b.x1, b.y0, b.z0)
	rlgl.Vertex3f(b.x0, b.y0, b.z1)
	rlgl.Vertex3f(b.x1, b.y0, b.z1)
	rlgl.Vertex3f(b.x1, b.y1, b.z1)
	rlgl.Vertex3f(b.x0, b.y1, b.z1)
	// West and east.
	rlgl.Vertex3f(b.x0, b.y0, b.z0)
	rlgl.Vertex3f(b.x0, b.y0, b.z1)
	rlgl.Vertex3f(b.x0, b.y1, b.z1)
	rlgl.Vertex3f(b.x0, b.y1, b.z0)
	rlgl.Vertex3f(b.x1, b.y0, b.z0)
	rlgl.Vertex3f(b.x1, b.y1, b.z0)
	rlgl.Vertex3f(b.x1, b.y1, b.z1)
	rlgl.Vertex3f(b.x1, b.y0, b.z1)
}

// The colors of the copy: a cold blue-green while it can be put down, and red while it cannot.
blueprint_colors :: proc(ok: bool) -> (fill, foot, edge: [4]u8) {
	if ok {
		return {60, 230, 215, 60}, {60, 230, 215, 120}, {120, 255, 245, 255}
	}
	return {240, 60, 60, 80}, {240, 60, 60, 150}, {255, 110, 110, 255}
}

// The box that the copy is drawn as: the body of the station, turned, over its middle, as high as the station.
blueprint_box_for :: proc(bp: ^carry.Blueprint) -> Blueprint_Box {
	body := lab.turn_rect(lab.station_body(bp.kind), bp.quarter)
	h := lab.station_height(bp.kind)
	return blueprint_box_of(bp.x + (body.min_x + body.max_x) * 0.5, lab.COUNTER_HEIGHT + h * 0.5, bp.z + (body.min_z + body.max_z) * 0.5, body.max_x - body.min_x, h, body.max_z - body.min_z)
}

// Draws the carried station: a see-through box the size of the station, its footprint on the counter, bright edges, and a
// bar on the side that the front of the station is turned to. It is drawn without writing depth, so it never hides what
// is behind it, and with both faces, so it shows from inside as well.
blueprint_draw :: proc(bp: ^carry.Blueprint) {
	if !bp.active || bp.kind == .None {
		return
	}
	fill, foot, edge := blueprint_colors(bp.ok)
	b := blueprint_box_for(bp)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.DisableDepthMask()
	rlgl.Begin(rlgl.QUADS)
	blueprint_box_quads(b, fill)
	blueprint_box_quads({b.x0, lab.COUNTER_HEIGHT, b.z0, b.x1, lab.COUNTER_HEIGHT + 0.006, b.z1}, foot)
	t := BLUEPRINT_EDGE
	for y in ([2]f32{b.y0, b.y1}) {
		for z in ([2]f32{b.z0, b.z1} ) {
			blueprint_box_quads({b.x0 - t, y - t, z - t, b.x1 + t, y + t, z + t}, edge) // the four along x
		}
		for x in ([2]f32{b.x0, b.x1}) {
			blueprint_box_quads({x - t, y - t, b.z0 - t, x + t, y + t, b.z1 + t}, edge) // the four along z
		}
	}
	for x in ([2]f32{b.x0, b.x1}) {
		for z in ([2]f32{b.z0, b.z1}) {
			blueprint_box_quads({x - t, b.y0 - t, z - t, x + t, b.y1 + t, z + t}, edge) // the four up
		}
	}
	// The front: a bar along the middle of the face that the display of a scale is on.
	front := lab.station_body(bp.kind)
	fx, fz := lab.turn_xz(0, front.max_z, bp.quarter)
	bar := Blueprint_Box{bp.x + fx - 0.15, b.y0, bp.z + fz - 0.15, bp.x + fx + 0.15, b.y1 + 0.02, bp.z + fz + 0.15}
	if bp.quarter % 2 == 0 {
		bar.z0, bar.z1 = bp.z + fz - 0.012, bp.z + fz + 0.012
	} else {
		bar.x0, bar.x1 = bp.x + fx - 0.012, bp.x + fx + 0.012
	}
	blueprint_box_quads(bar, edge)
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	rlgl.EnableBackfaceCulling()
}
