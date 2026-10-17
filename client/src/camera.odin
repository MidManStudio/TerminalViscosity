// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/client.md, section "camera.odin"
// ============================================================================

package main

import "core:math"
import rl "vendor:raylib"
import bl "balloon"

Vec3 :: [3]f32

// An orbit camera: it looks at `target` from `distance` away, at a heading
// `yaw` around the vertical axis and an elevation `pitch` above the horizon.
Camera_Rig :: struct {
	target:   Vec3,
	yaw:      f32, // radians
	pitch:    f32, // radians
	distance: f32,
	fovy:     f32, // degrees, vertical
}

PITCH_MIN :: f32(0.06)
PITCH_MAX :: f32(1.25)
DISTANCE_MIN :: f32(4)
DISTANCE_MAX :: f32(18)

camera_default :: proc() -> Camera_Rig {
	return {target = {0, 2.3, 0}, yaw = 0, pitch = 0.28, distance = 10.5, fovy = 35}
}

camera_eye :: proc(c: ^Camera_Rig) -> Vec3 {
	cp := math.cos(c.pitch)
	return c.target + Vec3{cp * math.sin(c.yaw), math.sin(c.pitch), cp * math.cos(c.yaw)} * c.distance
}

// Turns the camera around its target. dx and dy are pointer movements in pixels.
camera_orbit :: proc(c: ^Camera_Rig, dx, dy: f32) {
	c.yaw -= dx * 0.006
	c.pitch = clamp(c.pitch + dy * 0.006, PITCH_MIN, PITCH_MAX)
}

camera_zoom :: proc(c: ^Camera_Rig, wheel: f32) {
	c.distance = clamp(c.distance * math.pow(0.92, wheel), DISTANCE_MIN, DISTANCE_MAX)
}

// What the camera needs to know to turn pixels into rays and points into
// pixels, worked out once per frame. It matches how raylib builds the
// perspective for BeginMode3D, so the two always agree about the screen.
Camera_Frame :: struct {
	eye:     Vec3,
	right:   Vec3,
	up:      Vec3,
	forward: Vec3,
	half:    f32, // tan of half the vertical field of view
	w, h:    f32, // size of the render target in pixels
}

camera_frame :: proc(c: ^Camera_Rig, w, h: f32) -> Camera_Frame {
	f: Camera_Frame
	f.eye = camera_eye(c)
	f.forward = bl.normalize3(c.target - f.eye)
	f.right = bl.normalize3(bl.cross3(f.forward, {0, 1, 0}))
	f.up = bl.cross3(f.right, f.forward)
	f.half = math.tan(c.fovy * 0.5 * math.RAD_PER_DEG)
	f.w = w
	f.h = h
	return f
}

// Direction of the ray from the eye through the pixel (px, py).
frame_ray :: proc(f: ^Camera_Frame, px, py: f32) -> Vec3 {
	nx := (2 * px / f.w - 1) * f.half * (f.w / f.h)
	ny := (1 - 2 * py / f.h) * f.half
	return bl.normalize3(f.forward + f.right * nx + f.up * ny)
}

// Pixel where a world point lands. `ok` is false for points behind the camera.
frame_project :: proc(f: ^Camera_Frame, p: Vec3) -> (x, y: f32, ok: bool) {
	rel := p - f.eye
	depth := bl.dot3(rel, f.forward)
	if depth < 0.1 {
		return 0, 0, false
	}
	nx := bl.dot3(rel, f.right) / (depth * f.half * (f.w / f.h))
	ny := bl.dot3(rel, f.up) / (depth * f.half)
	return (nx * 0.5 + 0.5) * f.w, (0.5 - ny * 0.5) * f.h, true
}

camera_to_raylib :: proc(c: ^Camera_Rig) -> rl.Camera3D {
	return rl.Camera3D{position = camera_eye(c), target = c.target, up = {0, 1, 0}, fovy = c.fovy, projection = .PERSPECTIVE}
}
