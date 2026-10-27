// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "workstation.odin"
// ============================================================================

package carry

import "../lab"

HOOD_SHIELD :: f32(0.2) // the share of a blast's damage that gets out of the fume hood

// Whether a point is inside the fume hood: over its floor and under its top.
in_hood :: proc(at: Vec3) -> bool {
	return lab.in_rect(lab.HOOD, at.x, at.z) && at.y < lab.HOOD_TOP
}

// How much of a violent reaction's force reaches the player: all of it in the
// open, and a fifth of it when it happens in the fume hood.
shield_factor :: proc(at: Vec3) -> f32 {
	return in_hood(at) ? HOOD_SHIELD : 1
}

// The damage the player takes from a reaction, once the hood is counted.
felt_damage :: proc(r: Mix_Result) -> f32 {
	return r.damage * shield_factor(r.at)
}

// How open a reaction was, from 0 for shut in to 1 for in the open, for how big the
// blast looks.
openness :: proc(r: Mix_Result) -> f32 {
	return in_hood(r.at) ? 0 : 1
}

// Takes the drops that have fallen into the sink basin, near the counter top, down
// the drain. Returns how many.
stream_drain :: proc(st: ^Stream) -> int {
	n := 0
	for i := st.sim.count - 1; i >= 0; i -= 1 {
		w := stream_position(st, i)
		if lab.in_rect(lab.SINK_BASIN, w.x, w.z) && w.y < lab.SINK_DRAIN_TOP {
			stream_remove(st, i)
			n += 1
		}
	}
	return n
}
