// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "sink.odin"
// ============================================================================

package carry

import "../lab"

SOAP_WASH_TIME :: f32(2.5) // seconds that washing hands takes. A first guess.

// The soap by the sink, and washing hands with it. Washing hands has no effect on anything: it is something to do
// at the sink, as the owner has it, with the soap there for washing hands and for nothing else.
Soap :: struct {
	washing: f32, // seconds of washing left, 0 when the hands are not being washed
	aimed:   bool, // the crosshair is on the soap, within reach, with nothing nearer
}

// Whether the crosshair is on the soap within reach. A vessel under the crosshair comes first.
soap_aim :: proc(sp: ^Soap, props: ^Props, v: View) -> bool {
	t, hit := ray_box(v.eye, -v.back, lab.SOAP_AIM_LOW, lab.SOAP_AIM_HIGH)
	sp.aimed = hit && t <= REACH && props.aimed == -1
	return sp.aimed
}

// Whether the grab button would wash hands now: the soap is aimed at, the hands are empty, and they are not being
// washed already.
soap_use_ready :: proc(sp: ^Soap, props: ^Props) -> bool {
	return sp.aimed && props.held == -1 && sp.washing <= 0
}

// Begins washing hands. False if they are being washed already.
soap_use :: proc(sp: ^Soap) -> bool {
	if sp.washing > 0 {
		return false
	}
	sp.washing = SOAP_WASH_TIME
	return true
}

// Moves the washing on. Returns true in the frame that it finishes, and only then.
soap_update :: proc(sp: ^Soap, dt: f32) -> (done: bool) {
	if sp.washing <= 0 {
		return false
	}
	sp.washing = max(sp.washing - dt, 0)
	return sp.washing == 0
}

// How far through washing hands it is, from 0 to 1, and 0 when they are not being washed.
soap_progress :: proc(sp: ^Soap) -> f32 {
	if sp.washing <= 0 {
		return 0
	}
	return 1 - sp.washing / SOAP_WASH_TIME
}
