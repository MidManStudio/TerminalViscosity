// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "effects_view.odin"
// ============================================================================

package main

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "effects"

SOFT_SIZE :: 32 // pixels across the soft dot texture and the ring texture

// The two small textures every particle is drawn with: a soft round dot, and a
// ring. Both are white with a changing alpha, and are made here, so there is no
// file to load.
Effects_View :: struct {
	soft: rl.Texture2D,
	ring: rl.Texture2D,
}

// Where the blast light's two values live in a shader that uses it.
Blast_Locs :: struct {
	pos:   rl.ShaderLocationIndex,
	color: rl.ShaderLocationIndex,
}

// The alpha of the soft dot at distance `r` from its middle, 1 at the edge of the
// texture: bright in the middle and gone at the rim.
soft_alpha :: proc(r: f32) -> f32 {
	if r >= 1 {
		return 0
	}
	k := 1 - r
	return k * k
}

// The alpha of the ring: a thin band near the rim.
ring_alpha :: proc(r: f32) -> f32 {
	k := 1 - abs(r - 0.82) / 0.14
	if k <= 0 {
		return 0
	}
	return k * k
}

make_texture :: proc(ring: bool) -> rl.Texture2D {
	pixels := cast([^]u8)rl_alloc(SOFT_SIZE * SOFT_SIZE * 4)
	for y in 0 ..< SOFT_SIZE {
		for x in 0 ..< SOFT_SIZE {
			dx := (f32(x) + 0.5) / SOFT_SIZE * 2 - 1
			dy := (f32(y) + 0.5) / SOFT_SIZE * 2 - 1
			r := math.sqrt(dx * dx + dy * dy)
			a := ring ? ring_alpha(r) : soft_alpha(r)
			i := (y * SOFT_SIZE + x) * 4
			pixels[i + 0], pixels[i + 1], pixels[i + 2] = 255, 255, 255
			pixels[i + 3] = u8(clamp(a, 0, 1) * 255)
		}
	}
	img := rl.Image {
		data    = rawptr(pixels),
		width   = SOFT_SIZE,
		height  = SOFT_SIZE,
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	tex := rl.LoadTextureFromImage(img)
	rl.MemFree(rawptr(pixels))
	rl.SetTextureFilter(tex, .BILINEAR)
	return tex
}

effects_view_init :: proc(v: ^Effects_View) {
	v.soft = make_texture(false)
	v.ring = make_texture(true)
}

effects_view_unload :: proc(v: ^Effects_View) {
	rl.UnloadTexture(v.soft)
	rl.UnloadTexture(v.ring)
	v^ = {}
}

// Looks up where the blast light goes in a shader. A shader without it gives -1,
// which raylib ignores when a value is set.
blast_locs :: proc(shader: rl.Shader) -> Blast_Locs {
	return {pos = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "blastPos")), color = rl.ShaderLocationIndex(rl.GetShaderLocation(shader, "blastColor"))}
}

// Gives a shader the light of the current blast: where it is and how far it
// reaches, its color, and how bright it is now. With no blast going the reach and
// the brightness are zero and the room is lit as usual.
blast_light_set :: proc(shader: rl.Shader, locs: Blast_Locs, e: ^effects.Effects) {
	intensity := effects.light_intensity(e)
	pos := [4]f32{e.light.pos.x, e.light.pos.y, e.light.pos.z, intensity > 0 ? e.light.radius : 0}
	color := [4]f32{e.light.color.r, e.light.color.g, e.light.color.b, intensity}
	rl.SetShaderValue(shader, locs.pos, &pos, .VEC4)
	rl.SetShaderValue(shader, locs.color, &color, .VEC4)
}

// One flat square of side 2 * `size` facing the viewer, with the texture on it.
quad :: proc(c, right, up: Vec3, size: f32, color: [3]f32, alpha: f32) {
	rlgl.Color4ub(u8(clamp(color.r, 0, 1) * 255), u8(clamp(color.g, 0, 1) * 255), u8(clamp(color.b, 0, 1) * 255), u8(clamp(alpha, 0, 1) * 255))
	r, u := right * size, up * size
	a, b, d, e := c - r - u, c + r - u, c + r + u, c - r + u
	rlgl.TexCoord2f(0, 1)
	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.TexCoord2f(1, 1)
	rlgl.Vertex3f(b.x, b.y, b.z)
	rlgl.TexCoord2f(1, 0)
	rlgl.Vertex3f(d.x, d.y, d.z)
	rlgl.TexCoord2f(0, 1)
	rlgl.Vertex3f(a.x, a.y, a.z)
	rlgl.TexCoord2f(1, 0)
	rlgl.Vertex3f(d.x, d.y, d.z)
	rlgl.TexCoord2f(0, 0)
	rlgl.Vertex3f(e.x, e.y, e.z)
}

// Draws the particles and rings as squares that face the viewer, with the soft dot
// or the ring on them. Smoke, liquid, and mist are blended over the picture first.
// Fire, sparks, and the rings are added to it afterwards, so they glow. Nothing
// writes depth, so particles overlap without cutting each other, and the room still
// hides them. `right` and `up` are the viewer's own directions.
effects_draw :: proc(v: ^Effects_View, e: ^effects.Effects, right, up: Vec3) {
	if e.count == 0 && e.ring_count == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	rlgl.DisableBackfaceCulling()

	rlgl.SetTexture(v.soft.id)
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< e.count {
		p := &e.particles[i]
		if p.kind == .Smoke || p.kind == .Liquid || p.kind == .Mist {
			quad(p.pos, right, up, p.size, effects.tint(p), effects.opacity(p))
		}
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()

	rl.BeginBlendMode(.ADDITIVE)
	rlgl.SetTexture(v.soft.id)
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< e.count {
		p := &e.particles[i]
		if p.kind == .Fire || p.kind == .Spark {
			quad(p.pos, right, up, p.size, effects.tint(p), effects.opacity(p))
		}
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()

	rlgl.SetTexture(v.ring.id)
	rlgl.Begin(rlgl.TRIANGLES)
	for i in 0 ..< e.ring_count {
		radius, alpha := effects.ring_state(&e.rings[i])
		quad(e.rings[i].pos, right, up, max(radius, 0.01), e.rings[i].color, alpha)
	}
	rlgl.End()
	rlgl.DrawRenderBatchActive()
	rl.EndBlendMode()

	rlgl.SetTexture(0)
	rlgl.EnableBackfaceCulling()
	rlgl.EnableDepthMask()
}
