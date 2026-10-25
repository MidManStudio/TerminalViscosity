// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mixing.odin"
// ============================================================================

package carry

import "../chem"

MIX_SLACK :: f32(0.06) // how far off center the held vessel may be, beyond the target's radius
MIX_BELOW :: f32(0.10) // how far the base of the held vessel may be below the target's rim
MIX_ABOVE :: f32(0.35) // and how far above it

Mix_Kind :: enum {
	Nothing, // there was nothing to pour, or nowhere to pour it
	Poured, // into an empty vessel, or one with the same liquid, so no reaction
	Mixed, // two liquids met and made something calm
	Spatter, // a violent reaction: some liquid thrown out, and it stings
	Blast, // a very violent one: the target broke
}

// What one press of the mix button did. `a` is what the target held and `b`
// what was poured in. `damage` is what the player is to take.
Mix_Result :: struct {
	kind:       Mix_Kind,
	a, b:       u16,
	product:    u16,
	ml:         f32,
	volatility: f32,
	heat:       f32,
	damage:     f32,
}

// The vessel the held one is over, or -1: close to centered over its mouth, with
// the base of the held vessel not far above its rim. A full vessel cannot be
// poured into, and an empty one cannot be poured from.
mix_target :: proc(props: ^Props) -> int {
	if props.held == -1 || props.items[props.held].ml <= 0 {
		return -1
	}
	src := props.items[props.held]
	best := -1
	best_gap := f32(1e9)
	for i in 0 ..< props.count {
		if i == props.held {
			continue
		}
		t := props.items[i]
		td := kind_dims(t.kind)
		dx, dz := src.pos.x - t.pos.x, src.pos.z - t.pos.z
		reach := td.radius + MIX_SLACK
		if dx * dx + dz * dz > reach * reach {
			continue
		}
		gap := src.pos.y - (t.pos.y + td.height)
		if gap < -MIX_BELOW || gap > MIX_ABOVE {
			continue
		}
		if t.ml >= capacity_ml(t.kind) - 0.5 {
			continue
		}
		if gap < best_gap {
			best, best_gap = i, gap
		}
	}
	return best
}

// Pours the held vessel into the one under it, as much as fits, and lets the
// two liquids react. `eye` is where the player's eye is, for how hard a violent
// reaction hits. A calm reaction leaves the product in the target. A spatter
// loses part of it. A blast breaks the target and takes the liquid with it.
mix :: proc(props: ^Props, eye: Vec3) -> Mix_Result {
	target := mix_target(props)
	if target == -1 {
		return {}
	}
	src := &props.items[props.held]
	dst := &props.items[target]
	td := kind_dims(dst.kind)
	moved := min(src.ml, capacity_ml(dst.kind) - dst.ml)
	result := Mix_Result {
		a  = dst.compound,
		b  = src.compound,
		ml = moved,
	}

	outcome := chem.react(dst.compound, src.compound)
	result.product = outcome.product
	result.volatility = outcome.volatility
	result.heat = outcome.heat
	total := dst.ml + moved

	src.ml -= moved
	if src.ml < 0.01 {
		src.ml = 0
		src.compound = 0
	}

	if !outcome.reacted {
		dst.compound = outcome.product
		dst.ml = total
		result.kind = .Poured
		return result
	}

	middle := Vec3{dst.pos.x, dst.pos.y + td.height * 0.5, dst.pos.z}
	d := middle - eye
	result.damage = chem.damage_of(outcome.volatility, sqrt_f32(dot(d, d)))
	switch chem.hazard_of(outcome.volatility) {
	case .Calm:
		dst.compound = outcome.product
		dst.ml = total
		result.kind = .Mixed
	case .Spatter:
		dst.compound = outcome.product
		dst.ml = total * (1 - chem.SPATTER_LOSS)
		result.kind = .Spatter
	case .Blast:
		props_remove(props, target)
		result.kind = .Blast
	}
	return result
}
