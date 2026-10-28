// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "oven_view.odin"
// ============================================================================

package main

import "carry"
import "chem"
import "lab"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

OVEN_OFF :: [4]u8{46, 54, 64, 255}

// The color of a light that shows a liquid: the color of the liquid, brighter the
// fuller the port, and dark for an empty one.
liquid_light :: proc(compound: u16, ml, capacity: f32) -> [4]u8 {
	if ml <= 0 {
		return OVEN_OFF
	}
	c := chem.compound_color(compound)
	k := 0.45 + 0.55 * clamp(ml / capacity, 0, 1)
	return {u8(c.r * k * 255), u8(c.g * k * 255), u8(c.b * k * 255), 255}
}

// The parts of the reaction oven that change from frame to frame, drawn over the
// front of the box: a light for each port in the color of what it holds, a strip of
// ten lights that fills while a run goes, a light for the product in the tank, and a
// glow in the window while it runs. The window pulses so the oven looks busy.
oven_draw :: proc(o: ^carry.Oven) {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableBackfaceCulling()
	rlgl.Begin(rlgl.TRIANGLES)

	for i in 0 ..< lab.MIXER_PORTS {
		p := o.ports[i]
		draw_flat_box(lab.mixer_port_light(i), {0.14, 0.05, 0.012}, liquid_light(p.compound, p.ml, carry.PORT_CAPACITY))
	}
	draw_flat_box(lab.mixer_tank_light(), {0.14, 0.18, 0.012}, liquid_light(o.tank.compound, o.tank.ml, carry.TANK_CAPACITY * 0.5))

	running := o.state == .Running
	if running {
		pulse := 0.65 + 0.35 * f32(rl.GetTime() * 7 - f64(i32(rl.GetTime() * 7))) // a sawtooth, cheap and busy
		glow := [4]u8{u8(255 * pulse), u8(140 * pulse), u8(40 * pulse), 255}
		w := lab.MIXER
		draw_flat_box({(w.min_x + w.max_x) * 0.5 - 0.1, 1.24, w.max_z + 0.008}, {0.98, 0.16, 0.004}, glow)
	}
	progress := carry.oven_progress(o)
	for i in 0 ..< lab.MIXER_PROGRESS_LIGHTS {
		lit := progress > f32(i) / f32(lab.MIXER_PROGRESS_LIGHTS)
		color := lit ? [4]u8{255, 190, 60, 255} : [4]u8{70, 52, 40, 255}
		if !running {
			color = OVEN_OFF
		}
		draw_flat_box(lab.mixer_progress_light(i), {0.07, 0.07, 0.012}, color)
	}

	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rlgl.EnableBackfaceCulling()
}
