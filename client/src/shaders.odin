// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "shaders.odin"
// ============================================================================

package main

import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

// Browser and Android builds run on OpenGL ES, which needs the `#version 100` shaders.
when ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32 || ODIN_PLATFORM_SUBTARGET == .Android {
	SHADER_DIR :: "shaders/glsl100/"
} else {
	SHADER_DIR :: "shaders/glsl330/"
}

HeatShader :: struct {
	shader:       rl.Shader,
	valid:        bool,
	time_loc:     rl.ShaderLocationIndex,
	strength_loc: rl.ShaderLocationIndex,
}

// Full path of a shader file for the active GLSL version, as a C string the
// caller deletes.
shader_path :: proc(name: string) -> cstring {
	// Desktop: shaders are copied next to the executable by scripts/build_client.sh.
	// Android: they live in the APK's assets, which raylib opens by relative path.
	when ODIN_PLATFORM_SUBTARGET == .Android {
		path := strings.concatenate({SHADER_DIR, name})
	} else {
		path := strings.concatenate({string(rl.GetApplicationDirectory()), SHADER_DIR, name})
	}
	defer delete(path)
	return strings.clone_to_cstring(path)
}

// Loads the heat-distortion post effect. If it fails to compile, `valid` stays
// false and draw_scene falls back to a plain blit, so the lab still runs.
load_heat_shader :: proc() -> HeatShader {
	fx: HeatShader
	cpath := shader_path("heat_distort.fs")
	defer delete(cpath)
	fx.shader = rl.LoadShader(nil, cpath)
	fx.valid = rl.IsShaderValid(fx.shader)
	if fx.valid {
		fx.time_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(fx.shader, "time"))
		fx.strength_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(fx.shader, "strength"))
	}
	return fx
}

// Loads the balloon shader. `ok` is false if it fails to compile, and the
// balloon is then drawn flat with raylib's default shader.
load_balloon_shader :: proc() -> (shader: rl.Shader, ok: bool) {
	vs := shader_path("balloon.vs")
	defer delete(vs)
	fs := shader_path("balloon.fs")
	defer delete(fs)
	shader = rl.LoadShader(vs, fs)
	ok = rl.IsShaderValid(shader)
	return
}

unload_heat_shader :: proc(fx: ^HeatShader) {
	if fx.valid {
		rl.UnloadShader(fx.shader)
	}
}

// Draws the off-screen scene to the window. Render textures are stored upside
// down, so the source rectangle has a negative height.
draw_scene :: proc(fx: ^HeatShader, scene: rl.RenderTexture2D) {
	src := rl.Rectangle{0, 0, f32(scene.texture.width), -f32(scene.texture.height)}
	// The scene covers the whole screen, so it is copied without blending. A
	// translucent object leaves less than 1 in the scene's alpha channel, and
	// blending that onto black would darken it.
	rlgl.DrawRenderBatchActive()
	rlgl.DisableColorBlend()
	defer rlgl.EnableColorBlend()
	if fx.valid {
		t := f32(rl.GetTime())
		strength := f32(1.0)
		rl.SetShaderValue(fx.shader, fx.time_loc, &t, .FLOAT)
		rl.SetShaderValue(fx.shader, fx.strength_loc, &strength, .FLOAT)
		rl.BeginShaderMode(fx.shader)
		rl.DrawTextureRec(scene.texture, src, {0, 0}, rl.WHITE)
		rl.EndShaderMode()
	} else {
		rl.DrawTextureRec(scene.texture, src, {0, 0}, rl.WHITE)
	}
	rlgl.DrawRenderBatchActive()
}
