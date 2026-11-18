// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "jet.odin"
// ============================================================================

package carry

import "core:math"
import "core:math/linalg"

JET_NEVER :: f32(1e9) // the age of a mouth that no liquid has come out of
JET_MIN_SPEED :: f32(0.2) // a drop slower than this is not in a jet, metres a second
JET_ALIGN :: f32(0.8) // how nearly two drops of one jet go the same way: the cosine of the angle between them
JET_REACH :: f32(1.6) // how far apart two drops of one jet may be, in how far they travel in the time between them
JET_SLACK :: f32(0.04) // and this much more, in metres
JET_MOUTH_HOLD :: f32(0.12) // seconds after liquid last came out of a mouth that a jet is still joined to it
JET_MOUTH_REACH :: f32(0.3) // how far the newest drop may be from the mouth for the jet to be joined to it, metres
JET_SUBDIV :: 1 // points made between two drops
JET_FATTEN :: f32(1.4) // how much thicker the jet is drawn than the liquid in it would be, which is thin on a phone
JET_R_MIN :: f32(0.005) // the thinnest and the thickest a jet is drawn, in metres
JET_R_MAX :: f32(0.02)
JET_TIP :: f32(0.7) // how much of its width the end of a jet that is not joined to a mouth is drawn with
MAX_JET_POINTS :: MAX_STREAM * (JET_SUBDIV + 1) + 1

// One point of a jet: where it is, how wide, and the drop whose color it has.
Jet_Point :: struct {
	pos:    Vec3,
	radius: f32,
	drop:   u16,
}

// The liquid in the air as the view draws it: smooth jets, each a run of points from the oldest drop to the
// newest, and the drops that are in no jet, which are drawn on their own.
Jet :: struct {
	points:       [MAX_JET_POINTS]Jet_Point,
	count:        int,
	strand_first: [MAX_STREAM]u16, // where each jet starts in `points`
	strand_len:   [MAX_STREAM]u16, // and how many points it has
	to_mouth:     [MAX_STREAM]bool, // the newest end of the jet is joined to the mouth, so it is not closed off
	strands:      int,
	loose:        [MAX_STREAM]bool, // the drop is in no jet
}

// The drops of the stream in the order they were made, the oldest first, written into `order`. Returns how many.
jet_order :: proc(st: ^Stream, order: []int) -> int {
	n := min(st.sim.count, len(order))
	for i in 0 ..< n {
		order[i] = i
	}
	// Insertion sort, which suits fewer than a hundred and mostly sorted numbers.
	for i in 1 ..< n {
		held := order[i]
		j := i - 1
		for j >= 0 && st.seq[order[j]] > st.seq[held] {
			order[j + 1] = order[j]
			j -= 1
		}
		order[j + 1] = held
	}
	return n
}

// Whether drop `a`, the older, and drop `b`, the newer, are two parts of one jet: both in the air and moving,
// going the same way, and not further apart than they would be after the time between them. A splash scatters
// drops every way, so it is not a jet.
jet_joined :: proc(st: ^Stream, a, b: int) -> bool {
	pa, pb := &st.sim.particles[a], &st.sim.particles[b]
	sa, sb := linalg.length(pa.v), linalg.length(pb.v)
	if sa < JET_MIN_SPEED || sb < JET_MIN_SPEED || st.rest[a] > 0 || st.rest[b] > 0 {
		return false
	}
	if linalg.dot(pa.v, pb.v) < JET_ALIGN * sa * sb {
		return false
	}
	gap := max(st.age[a] - st.age[b], 0)
	return linalg.length(pa.x - pb.x) <= JET_REACH * max(sa, sb) * gap + JET_SLACK
}

// How wide a jet is where its drops are `spacing` apart and each stands for `ml` millilitres: the width of
// a stream that would hold that liquid, made thicker, and kept between the least and the most that is drawn.
jet_radius :: proc(ml, spacing: f32) -> f32 {
	area := ml * 1e-6 / max(spacing, 0.005)
	return clamp(JET_FATTEN * math.sqrt(area / math.PI), JET_R_MIN, JET_R_MAX)
}

// A point on the curve through four points, from the second to the third, at `t` from 0 to 1.
catmull_rom :: proc(p0, p1, p2, p3: Vec3, t: f32) -> Vec3 {
	t2, t3 := t * t, t * t * t
	return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
}

// Builds what the view draws from the drops in the air. The jets are runs of drops in the order they were
// made that are joined to the next, each a smooth curve through them with the width of the liquid in it, and
// the newest end joined to the mouth when liquid is still coming out. Drops in no jet are marked loose.
jet_build :: proc(st: ^Stream, jet: ^Jet) {
	jet^ = {}
	order: [MAX_STREAM]int
	n := jet_order(st, order[:])
	if n == 0 {
		return
	}
	// Whether the jet that ends with the newest drop reaches the mouth.
	newest := order[n - 1]
	mouth_joined := st.mouth_age < JET_MOUTH_HOLD && linalg.length(stream_position(st, newest) - st.mouth) < JET_MOUTH_REACH
	k := 0
	for k < n {
		end := k
		for end + 1 < n && jet_joined(st, order[end], order[end + 1]) {
			end += 1
		}
		attach := mouth_joined && end == n - 1
		if end > k || attach {
			jet_strand(st, jet, order[k:end + 1], attach)
		} else {
			jet.loose[order[k]] = true
		}
		k = end + 1
	}
}

// Adds one jet through `drops`, the oldest first, and to the mouth when `to_mouth` is set.
jet_strand :: proc(st: ^Stream, jet: ^Jet, drops: []int, to_mouth: bool) {
	control: [MAX_STREAM + 1]Vec3
	owner: [MAX_STREAM + 1]u16
	ml: [MAX_STREAM + 1]f32
	m := 0
	for d in drops {
		control[m], owner[m], ml[m] = stream_position(st, d), u16(d), st.ml[d]
		m += 1
	}
	if to_mouth {
		control[m], owner[m], ml[m] = st.mouth, owner[m - 1], ml[m - 1]
		m += 1
	}
	radius: [MAX_STREAM + 1]f32
	for i in 0 ..< m {
		spacing, sides := f32(0), f32(0)
		if i > 0 {
			spacing += linalg.length(control[i] - control[i - 1])
			sides += 1
		}
		if i < m - 1 {
			spacing += linalg.length(control[i + 1] - control[i])
			sides += 1
		}
		radius[i] = jet_radius(ml[i], spacing / sides)
	}
	radius[0] *= JET_TIP
	if to_mouth {
		radius[m - 1] = radius[m - 2] // as wide at the mouth as the newest drop, so there is no neck
	} else {
		radius[m - 1] *= JET_TIP
	}
	jet.strand_first[jet.strands] = u16(jet.count)
	for i in 0 ..< m - 1 {
		// The ends carry on the way the line was going, so a straight jet stays straight to its tips.
		p0 := i > 0 ? control[i - 1] : 2 * control[0] - control[1]
		p3 := i + 2 < m ? control[i + 2] : 2 * control[m - 1] - control[m - 2]
		for s in 0 ..= JET_SUBDIV {
			t := f32(s) / f32(JET_SUBDIV + 1)
			jet.points[jet.count] = {catmull_rom(p0, control[i], control[i + 1], p3, t), radius[i] + (radius[i + 1] - radius[i]) * t, owner[i]}
			jet.count += 1
		}
	}
	jet.points[jet.count] = {control[m - 1], radius[m - 1], owner[m - 1]}
	jet.count += 1
	jet.strand_len[jet.strands] = u16(jet.count) - jet.strand_first[jet.strands]
	jet.to_mouth[jet.strands] = to_mouth
	jet.strands += 1
}
