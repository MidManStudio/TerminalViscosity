// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "sink_test.odin"
// ============================================================================

package carry

import "../lab"
import "core:testing"

// A view from 0.8 m in front of the soap, looking at it along the counter.
soap_view :: proc() -> View {
	return View{eye = {lab.SOAP_AT.x, lab.SOAP_AT.y + 0.1, lab.SOAP_AT.z + 0.8}, back = {0, 0, 1}}
}

@(test)
the_soap_is_aimed_at_when_the_crosshair_is_on_it_within_reach :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	sp: Soap
	props.aimed = -1
	testing.expect(t, soap_aim(&sp, props, soap_view()), "on it")
	testing.expect(t, sp.aimed, "and remembered")
	v := soap_view()
	v.eye.x += 0.5 // aimed past the side of it
	testing.expect(t, !soap_aim(&sp, props, v), "beside it")
	testing.expect(t, !sp.aimed, "so not aimed")
	v = soap_view()
	v.eye.z += 5 // too far
	testing.expect(t, !soap_aim(&sp, props, v), "out of reach")
	v = soap_view()
	v.back = {0, 0, -1} // looking away
	testing.expect(t, !soap_aim(&sp, props, v), "looking the other way")
}

@(test)
a_vessel_under_the_crosshair_comes_before_the_soap :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	sp: Soap
	props.aimed = 0
	testing.expect(t, !soap_aim(&sp, props, soap_view()), "the vessel is aimed at")
}

@(test)
the_soap_can_be_used_only_when_aimed_with_empty_hands_and_not_while_washing :: proc(t: ^testing.T) {
	l, p, props := make_scene()
	defer free_scene(l, p, props)
	sp: Soap
	props.held = -1
	testing.expect(t, !soap_use_ready(&sp, props), "not aimed")
	sp.aimed = true
	testing.expect(t, soap_use_ready(&sp, props), "aimed, hands empty")
	props.held = 0
	testing.expect(t, !soap_use_ready(&sp, props), "a vessel in the hands")
	props.held = -1
	sp.washing = 1
	testing.expect(t, !soap_use_ready(&sp, props), "already washing")
}

@(test)
washing_hands_takes_its_time_and_ends_once :: proc(t: ^testing.T) {
	sp: Soap
	testing.expect(t, soap_use(&sp), "begins")
	testing.expect_value(t, sp.washing, SOAP_WASH_TIME)
	testing.expect(t, !soap_use(&sp), "not twice at once")
	testing.expect_value(t, soap_progress(&sp), f32(0))
	testing.expect(t, !soap_update(&sp, SOAP_WASH_TIME * 0.5), "half way")
	testing.expect(t, near(soap_progress(&sp), 0.5, 1e-5), "half done")
	testing.expect(t, soap_update(&sp, SOAP_WASH_TIME), "done, in a longer step than was left")
	testing.expect_value(t, sp.washing, f32(0))
	testing.expect(t, !soap_update(&sp, 1), "and not again")
	testing.expect_value(t, soap_progress(&sp), f32(0))
	testing.expect(t, soap_use(&sp), "they can be washed again")
}

@(test)
nothing_moves_on_when_hands_are_not_being_washed :: proc(t: ^testing.T) {
	sp: Soap
	testing.expect(t, !soap_update(&sp, 1), "no washing, no end")
	testing.expect_value(t, sp.washing, f32(0))
}
