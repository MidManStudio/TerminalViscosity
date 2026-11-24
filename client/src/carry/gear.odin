// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "gear.odin"
// ============================================================================

package carry

import "../chemistry"
import "../lab"

// What the first aid cabinet and the scale of the lab do. Where they stand is in package lab.

// ---- The first aid cabinet ----

FIRST_AID_COOLDOWN :: f32(30) // seconds before the cabinet can be used again. A first guess.

// The cabinet: using it puts the player back at full health at once, which the slow healing
// of the lab would take much longer to do, and then it has to be left alone for a while.
First_Aid :: struct {
	cooldown: f32, // seconds until it can be used again, 0 when it can
	aimed:    bool, // the crosshair is on it, within reach, with nothing nearer
}

first_aid_update :: proc(fa: ^First_Aid, dt: f32) {
	fa.cooldown = max(fa.cooldown - dt, 0)
}

// Whether the crosshair is on the cabinet within reach. A vessel under the crosshair comes first.
first_aid_aim :: proc(fa: ^First_Aid, props: ^Props, v: View) -> bool {
	t, hit := ray_box(v.eye, -v.back, lab.FIRST_AID_AIM_LOW, lab.FIRST_AID_AIM_HIGH)
	fa.aimed = hit && t <= REACH && props.aimed == -1
	return fa.aimed
}

// Whether using it would do anything: the player is hurt, and it has not been used lately.
first_aid_ready :: proc(fa: ^First_Aid, h: ^Health) -> bool {
	return fa.cooldown <= 0 && h.hp < HEALTH_MAX - 0.5
}

// Whether the grab button would use it now: it is aimed at, the hands are empty, and it is ready.
first_aid_use_ready :: proc(fa: ^First_Aid, props: ^Props, h: ^Health) -> bool {
	return fa.aimed && props.held == -1 && first_aid_ready(fa, h)
}

// Uses it: full health, the red flash gone, and the cooldown begins. False if it was not ready.
first_aid_use :: proc(fa: ^First_Aid, h: ^Health) -> bool {
	if !first_aid_ready(fa, h) {
		return false
	}
	h.hp = HEALTH_MAX
	h.flash = 0
	fa.cooldown = FIRST_AID_COOLDOWN
	return true
}

// ---- The scale ----

// How heavy each kind of glass is, in grams. First guesses.
glass_grams :: proc(k: Kind) -> f32 {
	switch k {
	case .Beaker:
		return 60
	case .Flask:
		return 85
	case .Bottle:
		return 110
	case .Vial:
		return 8
	}
	return 0
}

// How heavy a millilitre of a compound is, in grams. Nothing in the compound table says, so every
// compound weighs what water does until the table has a density. The one place to change it.
compound_density :: proc(id: u16) -> f32 {
	return 1
}

// The mass of a vessel and what is in it, in grams.
vessel_grams :: proc(pr: Prop) -> f32 {
	grams := glass_grams(pr.kind)
	for i in 0 ..< pr.mix.count {
		grams += pr.mix.items[i].ml * compound_density(u16(pr.mix.items[i].compound))
	}
	return grams
}

// The scale reads everything that stands on its plate, less the tare: the weight that was on it
// when it was zeroed. The tare is kept until the plate is empty, so a vessel taken off a zeroed
// scale makes the display read less than nothing, as a real scale does.
Scale :: struct {
	tare:  f32, // grams the display has been zeroed at
	aimed: bool,
}

// Whether vessel `i` is standing on the plate of the scale: not held, with its middle over the
// plate, and resting on it.
scale_on :: proc(props: ^Props, i: int) -> bool {
	if i < 0 || i >= props.count || i == props.held {
		return false
	}
	pr := props.items[i]
	rest := lab.COUNTER_HEIGHT + lab.SCALE_PLATE_TOP
	return lab.on_station(&props.placed, .Scale, pr.pos.x, pr.pos.z) && pr.pos.y <= rest + 0.01
}

// The mass in grams of every vessel on the plate, and how many there are.
scale_load :: proc(props: ^Props) -> (grams: f32, count: int) {
	for i in 0 ..< props.count {
		if scale_on(props, i) {
			grams += vessel_grams(props.items[i])
			count += 1
		}
	}
	return
}

// What the display shows, in grams, and whether there is anything on the plate.
scale_reading :: proc(sc: ^Scale, props: ^Props) -> (grams: f32, loaded: bool) {
	load, count := scale_load(props)
	if count == 0 {
		return 0, false
	}
	return load - sc.tare, true
}

// Clears the tare when the plate is empty. Call it every frame.
scale_update :: proc(sc: ^Scale, props: ^Props) {
	if _, count := scale_load(props); count == 0 {
		sc.tare = 0
	}
}

// Whether the crosshair is on the scale within reach. A vessel under the crosshair comes first.
scale_aim :: proc(sc: ^Scale, props: ^Props, v: View) -> bool {
	nearest, any := f32(0), false
	for i in 0 ..< props.placed.count {
		if props.placed.items[i].kind == .Scale {
			low, high := lab.station_aim_box(props.placed.items[i])
			if t, hit := ray_box(v.eye, -v.back, low, high); hit && (!any || t < nearest) {
				nearest, any = t, true
			}
		}
	}
	sc.aimed = any && nearest <= REACH && props.aimed == -1
	return sc.aimed
}

// Whether the grab button would zero it now: aimed at, empty hands, and a reading that is not
// already zero, which an empty plate always is.
scale_zero_ready :: proc(sc: ^Scale, props: ^Props) -> bool {
	grams, _ := scale_reading(sc, props)
	return sc.aimed && props.held == -1 && abs(grams) > 0.05
}

// Zeroes the display at what is on the plate. False if it was not ready.
scale_zero :: proc(sc: ^Scale, props: ^Props) -> bool {
	if !scale_zero_ready(sc, props) {
		return false
	}
	sc.tare, _ = scale_load(props)
	return true
}

// ---- The shelves ----

// The colours of the bottles on the shelves, from the compounds in turn, and over again when
// there are fewer compounds than there are bottles.
shelf_colors :: proc() -> [lab.SHELF_BOTTLES][4]u8 {
	colors: [lab.SHELF_BOTTLES][4]u8
	for i in 0 ..< lab.SHELF_BOTTLES {
		c := chemistry.compound_of(chemistry.Id(i % chemistry.COMPOUND_COUNT + 1)).color
		colors[i] = {c.r, c.g, c.b, 255}
	}
	return colors
}
