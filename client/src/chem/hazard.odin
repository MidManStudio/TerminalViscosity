// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "hazard.odin"
// ============================================================================

package chem

SPATTER_AT :: f32(0.3) // volatility from which a mix spatters
BLAST_AT :: f32(0.6) // volatility from which a mix is a blast

BLAST_DAMAGE_MIN :: f32(30) // the most a blast just over the limit does, point blank
BLAST_DAMAGE_MAX :: f32(100) // and the most the strongest one does
BLAST_RADIUS_MIN :: f32(2) // metres
BLAST_RADIUS_MAX :: f32(4)
SPATTER_DAMAGE_MIN :: f32(5)
SPATTER_DAMAGE_MAX :: f32(15)
SPATTER_RADIUS :: f32(1.5)
SPATTER_LOSS :: f32(0.2) // the share of the liquid that is thrown out of the vessel

Hazard :: enum {
	Calm, // nothing to worry about
	Spatter, // hurts a little close up, and some liquid is lost
	Blast, // hurts a lot and the vessel breaks
}

hazard_of :: proc(volatility: f32) -> Hazard {
	if volatility >= BLAST_AT {
		return .Blast
	}
	if volatility >= SPATTER_AT {
		return .Spatter
	}
	return .Calm
}

// 0 for a blast just over the limit and 1 for the strongest possible.
blast_power :: proc(volatility: f32) -> f32 {
	return clamp((volatility - BLAST_AT) / (1 - BLAST_AT), 0, 1)
}

// How much a blast hurts someone `distance` metres from it, falling in a
// straight line from the most at point blank to nothing at the edge.
blast_damage :: proc(volatility: f32, distance: f32) -> f32 {
	power := blast_power(volatility)
	most := BLAST_DAMAGE_MIN + (BLAST_DAMAGE_MAX - BLAST_DAMAGE_MIN) * power
	radius := BLAST_RADIUS_MIN + (BLAST_RADIUS_MAX - BLAST_RADIUS_MIN) * power
	if distance >= radius {
		return 0
	}
	return most * (1 - max(distance, 0) / radius)
}

spatter_damage :: proc(volatility: f32, distance: f32) -> f32 {
	if distance >= SPATTER_RADIUS {
		return 0
	}
	t := clamp((volatility - SPATTER_AT) / (BLAST_AT - SPATTER_AT), 0, 1)
	most := SPATTER_DAMAGE_MIN + (SPATTER_DAMAGE_MAX - SPATTER_DAMAGE_MIN) * t
	return most * (1 - max(distance, 0) / SPATTER_RADIUS)
}

// The damage of whatever a reaction does, at a distance. A calm mix does none.
damage_of :: proc(volatility: f32, distance: f32) -> f32 {
	switch hazard_of(volatility) {
	case .Calm:
		return 0
	case .Spatter:
		return spatter_damage(volatility, distance)
	case .Blast:
		return blast_damage(volatility, distance)
	}
	return 0
}
