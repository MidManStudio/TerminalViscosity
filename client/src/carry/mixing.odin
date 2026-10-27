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
// was poured in. `damage` is what the player is to take, before anything that
// shields them, and `at` is where it happened, the middle of the container.
Mix_Result :: struct {
	kind:       Mix_Kind,
	a, b:       u16,
	product:    u16,
	volatility: f32,
	heat:       f32,
	damage:     f32,
	at:         Vec3,
}

// A drop of `compound`, `ml` millilitres, falls into a container that holds
// `compound_at` and `ml_at`, up to `capacity`. It is the rule for every container,
// vessels and the balloon at the fill station alike. A drop into an empty one, or
// one with the same liquid, simply joins it. When two different liquids meet, they
// react once for the whole pour: the contents become the product, and drops that
// follow in the same pour, as far as the session `s` remembers it under `key`,
// join that product as it is. A calm reaction leaves the product, a spatter loses a
// share of it and stings, and a blast leaves the contents alone and says so: the
// caller breaks the container. `middle` is the middle of the container and `eye`
// where the player's eye is, for how hard a violent reaction hits. The result is
// `.Nothing` except for the drop that starts a meeting.
mix_into :: proc(compound_at: ^u16, ml_at: ^f32, capacity: f32, middle, eye: Vec3, s: ^Session, key: int, compound: u16, ml: f32) -> Mix_Result {
	room := capacity - ml_at^
	if room <= 0.001 {
		return {} // the container is full, so the drop is lost
	}
	amount := min(ml, room)

	if s.target == key && s.src == compound && s.timer > 0 {
		ml_at^ += amount
		s.timer = SESSION_HOLD
		return {}
	}
	if compound_at^ == 0 || compound_at^ == compound {
		compound_at^ = compound
		ml_at^ += amount
		return {}
	}

	outcome := chem.react(compound_at^, compound)
	result := Mix_Result {
		a          = compound_at^,
		b          = compound,
		product    = outcome.product,
		volatility = outcome.volatility,
		heat       = outcome.heat,
		at         = middle,
	}
	d := middle - eye
	result.damage = chem.damage_of(outcome.volatility, sqrt_f32(dot(d, d)))
	total := ml_at^ + amount
	s^ = {
		target  = key,
		src     = compound,
		product = outcome.product,
		timer   = SESSION_HOLD,
	}
	switch chem.hazard_of(outcome.volatility) {
	case .Calm:
		compound_at^ = outcome.product
		ml_at^ = total
		result.kind = .Mixed
	case .Spatter:
		compound_at^ = outcome.product
		ml_at^ = total * (1 - chem.SPATTER_LOSS)
		result.kind = .Spatter
	case .Blast:
		result.kind = .Blast
	}
	return result
}

// A drop of `compound`, `ml` millilitres, falls into vessel `target`. The rule is
// `mix_into`, and a blast breaks the vessel and takes the liquid.
apply_droplet :: proc(props: ^Props, target: int, compound: u16, ml: f32, eye: Vec3) -> Mix_Result {
	t := &props.items[target]
	td := kind_dims(t.kind)
	middle := Vec3{t.pos.x, t.pos.y + td.height * 0.5, t.pos.z}
	result := mix_into(&t.compound, &t.ml, capacity_ml(t.kind), middle, eye, &props.session, target, compound, ml)
	if result.kind == .Blast {
		props_remove(props, target)
	}
	return result
}
