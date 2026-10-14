// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "shaders.odin"
// ============================================================================

package main

import "core:strings"
import rl "vendor:raylib"

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

// Loads the heat-distortion post effect. If it fails to compile, `valid` stays
// false and draw_scene falls back to a plain blit, so the lab still runs.
load_heat_shader :: proc() -> HeatShader {
	fx: HeatShader
	// Desktop: shaders are copied next to the executable by scripts/build_client.sh.
	// Android: they live in the APK's assets, which raylib opens by relative path.
	when ODIN_PLATFORM_SUBTARGET == .Android {
		path := strings.clone(SHADER_DIR + "heat_distort.fs")
	} else {
		path := strings.concatenate({string(rl.GetApplicationDirectory()), SHADER_DIR, "heat_distort.fs"})
	}
	defer delete(path)
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	fx.shader = rl.LoadShader(nil, cpath)
	fx.valid = rl.IsShaderValid(fx.shader)
	if fx.valid {
		fx.time_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(fx.shader, "time"))
		fx.strength_loc = rl.ShaderLocationIndex(rl.GetShaderLocation(fx.shader, "strength"))
	}
	return fx
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
}
