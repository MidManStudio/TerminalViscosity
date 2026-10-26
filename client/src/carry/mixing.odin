// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mixing.odin"
// ============================================================================

package carry

import "../chem"

SESSION_HOLD :: f32(0.6) // how long after the last drop a pour still counts as the same pour

Mix_Kind :: enum {
	Nothing, // nothing worth saying: a drop joined a vessel, or fell in one that was full
	Mixed, // two liquids met and made something calm
	Spatter, // a violent reaction: some liquid thrown out, and it stings
	Blast, // a very violent one: the vessel broke
}

// What a meeting of two liquids did. `a` is what the vessel held and `b` what
// was poured in. `damage` is what the player is to take.
Mix_Result :: struct {
	kind:       Mix_Kind,
	a, b:       u16,
	product:    u16,
	volatility: f32,
	heat:       f32,
	damage:     f32,
}

// A drop of `compound`, `ml` millilitres, falls into vessel `target`. A drop into
// an empty vessel, or one with the same liquid, simply joins it. When two
// different liquids meet, they react once for the whole pour: the contents of
// the vessel become the product, and drops that follow in the same pour join
// that product as it is. A calm reaction leaves the product, a spatter loses a
// share of it and stings, and a blast breaks the vessel and takes the liquid.
// `eye` is where the player's eye is, for how hard a violent reaction hits. The
// result is `.Nothing` except for the drop that starts a meeting.
apply_droplet :: proc(props: ^Props, target: int, compound: u16, ml: f32, eye: Vec3) -> Mix_Result {
	t := &props.items[target]
	room := capacity_ml(t.kind) - t.ml
	if room <= 0.001 {
		return {} // the vessel is full, so the drop is lost
	}
	amount := min(ml, room)

	s := &props.session
	if s.target == target && s.src == compound && s.timer > 0 {
		t.ml += amount
		s.timer = SESSION_HOLD
		return {}
	}
	if t.compound == 0 || t.compound == compound {
		t.compound = compound
		t.ml += amount
		return {}
	}

	outcome := chem.react(t.compound, compound)
	result := Mix_Result {
		a          = t.compound,
		b          = compound,
		product    = outcome.product,
		volatility = outcome.volatility,
		heat       = outcome.heat,
	}
	td := kind_dims(t.kind)
	middle := Vec3{t.pos.x, t.pos.y + td.height * 0.5, t.pos.z}
	d := middle - eye
	result.damage = chem.damage_of(outcome.volatility, sqrt_f32(dot(d, d)))
	total := t.ml + amount
	props.session = {
		target  = target,
		src     = compound,
		product = outcome.product,
		timer   = SESSION_HOLD,
	}
	switch chem.hazard_of(outcome.volatility) {
	case .Calm:
		t.compound = outcome.product
		t.ml = total
		result.kind = .Mixed
	case .Spatter:
		t.compound = outcome.product
		t.ml = total * (1 - chem.SPATTER_LOSS)
		result.kind = .Spatter
	case .Blast:
		props_remove(props, target)
		result.kind = .Blast
	}
	return result
}
