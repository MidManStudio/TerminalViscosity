// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/android.md, section "entry.c"
// ============================================================================

// raylib's Android backend implements `android_main` and calls a C function
// named `main` from it. The Odin client is built as plain object files with no
// entry point of its own, so this shim provides `main` and forwards to the
// procedure the Odin side exports (client/src/android_entry.odin). It also holds
// small wrappers for raylib calls whose struct return value Odin gets wrong on
// 32-bit ARM Android.

extern void tv_odin_main(void);

// Same layout as raylib's Vector2.
typedef struct {
    float x;
    float y;
} TvVec2;

extern TvVec2 GetMousePosition(void);
extern TvVec2 GetTouchPosition(int index);

// Odin's 32-bit ARM backend returns an 8-byte struct of floats in registers,
// but the NDK's ABI returns it through a hidden pointer, so calling
// GetMousePosition from Odin makes raylib write through a garbage pointer.
// Calling it from C uses the right convention. Any raylib function that returns
// Vector2, Vector3, Vector4, Quaternion, Rectangle, or Matrix needs a shim like
// this one. scripts/check_android_abi.py fails the build if one is called directly.
void tv_android_mouse_position(float *out_x, float *out_y)
{
    TvVec2 p = GetMousePosition();
    *out_x = p.x;
    *out_y = p.y;
}

// The same problem and the same remedy for a touch point. The lab's joystick
// and look controls read two fingers at once.
void tv_android_touch_position(int index, float *out_x, float *out_y)
{
    TvVec2 p = GetTouchPosition(index);
    *out_x = p.x;
    *out_y = p.y;
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    tv_odin_main();
    return 0;
}
