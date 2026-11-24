// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "mixing.odin"
// ============================================================================

package carry

import "../chem"
import "../chemistry"
import "../lab"

ROOM_C :: f32(20) // the temperature of the lab, and of anything that has stood in it
STOCK_PURITY :: f32(1) // a chemical out of a bottle
SINK_PURITY :: f32(0.25) // water out of a tap: the middle of the band that the pages call sink water

Mix_Kind :: enum {
	Nothing, // nothing worth saying: a drop joined a vessel, or fell in one that was full
	Mixed, // a reaction ran and nothing went wrong
	Spatter, // a splash or fumes: some liquid thrown out, and it stings
	Blast, // a burst: the vessel broke
}

// What a drop did when it went into a container. `a` is what the container mostly held
// before and `b` what was poured in. `product` is the first compound that a reaction made,
// or 0. `volatility` is how violent the worst thing that happened was, from 0 to 1, which is
// what the effects and the damage are worked out from. `heat` is the temperature of the
// container afterwards, in degrees. `damage` is what the player is to take, before anything
// that shields them, and `at` is where it happened, the middle of the container. `steps`
// says what ran, for the book and the readouts.
Mix_Result :: struct {
	kind:       Mix_Kind,
	a, b:       u16,
	product:    u16,
	volatility: f32,
	heat:       f32,
	damage:     f32,
	at:         Vec3,
	steps:      chemistry.Settled,
}

// The purity a compound comes with out of the lab's bottles and taps.
stock_purity :: proc(compound: u16) -> f32 {
	return chemistry.Id(compound) == .Water ? SINK_PURITY : STOCK_PURITY
}

// Makes a container hold `ml` of one compound and nothing else, at `heat_c` degrees. A purity of -1 is the
// purity the compound has out of the lab's bottles. It is how the starting vessels are filled and how the
// tests fill one.
fill_with :: proc(m: ^chemistry.Mixture, compound: u16, ml: f32, heat_c := ROOM_C, purity := f32(-1)) {
	m^ = {}
	if ml > 0 {
		chemistry.mix_add(m, chemistry.Id(compound), ml, purity < 0 ? stock_purity(compound) : purity, heat_c)
	}
}

// How much liquid there is in a container, in millilitres.
ml_of :: proc(m: ^chemistry.Mixture) -> f32 {
	return chemistry.mix_volume(m)
}

// The compound there is most of, as a number, or 0 for an empty container.
main_of :: proc(m: ^chemistry.Mixture) -> u16 {
	return u16(chemistry.dominant(m))
}

// How violent a thing that happened to a mixture is, from 0 to 1, with the pages' events
// standing for the old hazard levels: a splash and fumes and fire spatter, and a burst
// blasts and is more violent the higher the unsafe meter has got.
event_volatility :: proc(e: chemistry.Event, unsafe: f32) -> f32 {
	#partial switch e {
	case .Splash:
		return 0.45
	case .Fumes:
		return 0.4
	case .Fire:
		return 0.55
	case .Burst:
		return 0.65 + 0.35 * clamp(unsafe, 0, 1)
	}
	return 0
}

// Lets a mixture react, after something was poured in or its temperature moved, and says what
// happened as the old kinds of result. A reaction that runs quietly is `.Mixed`. A splash, fumes
// or fire is a spatter, which throws out a share of the liquid and stings. A burst is a blast,
// which leaves the liquid alone and says so: the caller breaks the container. `middle` is the
// middle of the container and `eye` where the player's eye is, for how hard it hits. `poured`
// and `before` are what went in and what the container mostly held. The kind is `.Nothing` when
// nothing ran.
react :: proc(m: ^chemistry.Mixture, middle, eye: Vec3, station: chemistry.Station, poured, before: u16) -> Mix_Result {
	done := chemistry.settle(m, station)
	if done.count == 0 {
		return {}
	}
	result := Mix_Result {
		kind  = .Mixed,
		a     = before,
		b     = poured,
		heat  = m.heat_c,
		at    = middle,
		steps = done,
	}
	for i in 0 ..< m.count {
		if m.items[i].made {
			result.product = u16(m.items[i].compound)
			break
		}
	}
	for i in 0 ..< done.count {
		result.volatility = max(result.volatility, event_volatility(done.steps[i].event, m.unsafe))
	}
	d := middle - eye
	result.damage = chem.damage_of(result.volatility, sqrt_f32(dot(d, d)))
	switch chem.hazard_of(result.volatility) {
	case .Calm:
	case .Spatter:
		chemistry.mix_scale(m, 1 - chem.SPATTER_LOSS)
		result.kind = .Spatter
	case .Blast:
		result.kind = .Blast
	}
	return result
}

// A drop of `compound`, `ml` millilitres, at `purity` and `drop_heat_c` degrees, falls into a
// container that holds `m`, up to `capacity`. It is the rule for every container, vessels and
// the balloon at the fill station alike: the drop joins what is there, the temperature becomes
// the blend, and whatever the pages say should happen then happens (`react`). A drop that
// finds the container full is lost. `station` is what the container is standing on.
mix_into :: proc(m: ^chemistry.Mixture, capacity: f32, middle, eye: Vec3, station: chemistry.Station, compound: u16, ml, purity, drop_heat_c: f32) -> Mix_Result {
	room := capacity - ml_of(m)
	if room <= 0.001 {
		return {}
	}
	before := main_of(m)
	if !chemistry.mix_add(m, chemistry.Id(compound), min(ml, room), purity, drop_heat_c) {
		return {}
	}
	return react(m, middle, eye, station, compound, before)
}

// What a vessel is standing on, in the words of the pages: the hot plate is a hot bath and the
// ice bath a cold bath.
station_of :: proc(pr: Prop, placed: ^lab.Placed = nil) -> chemistry.Station {
	switch station_heat(pr, placed) {
	case 1:
		return .Hot_Bath
	case -1:
		return .Cold_Bath
	}
	return .Any
}

// A drop of `compound`, `ml` millilitres, falls into vessel `target`. The rule is `mix_into`, and
// a blast breaks the vessel and takes the liquid.
apply_droplet :: proc(props: ^Props, target: int, compound: u16, ml: f32, eye: Vec3, drop_heat_c := ROOM_C, purity := STOCK_PURITY) -> Mix_Result {
	t := &props.items[target]
	td := kind_dims(t.kind)
	middle := Vec3{t.pos.x, t.pos.y + td.height * 0.5, t.pos.z}
	result := mix_into(&t.mix, capacity_ml(t.kind), middle, eye, station_of(t^, &props.placed), compound, ml, purity, drop_heat_c)
	if result.kind == .Blast {
		props_remove(props, target)
	}
	return result
}
