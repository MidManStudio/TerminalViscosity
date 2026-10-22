# android

## Overview

Everything specific to the Android build that is not Odin or Rust source: the manifest and the C shim that starts the game. The build itself is `scripts/build_android.sh`, run by `.github/workflows/android.yml`. The target is 32-bit ARM (`armeabi-v7a`), because that is the only ABI the Galaxy A13 reports as installable. See `docs/ANDROID.md` for requirements, what was verified, and what was not.

The pipeline: raylib 6.0 is built from source for Android, `tv_ffi` is built for `armv7-linux-androideabi`, Odin compiles the client to plain object files, the NDK linker joins them with the C shim and raylib (whose archive already contains the native app glue) into `libmain.so`, and `aapt`, `zipalign`, and `apksigner` produce a signed debug APK.

## Modules

### `AndroidManifest.xml`
**What it does:** Declares the app as a native activity with no Java code. The activity loads `libmain.so` through the `android.app.lib_name` meta-data.

**Decisions:**
- Package id `com.midmanstudio.terminalviscosity`, following the `com.midmanstudio.midnote` pattern.
- `android:hasCode="false"`, so no `classes.dex` is needed.
- `android:exported="true"` on the launcher activity, which Android 12 and newer require.
- Landscape orientation, and `configChanges` for rotation and resize so the native activity is not recreated.
- OpenGL ES 2.0 is required. That matches raylib's default Android backend and the `glsl100` shaders.
- `@MIN_SDK@` and `@TARGET_SDK@` are placeholders that the build script fills in. The defaults are 29 and 34.

### `entry.c`
**What it does:** Defines the C `main` that raylib's `android_main` calls, and forwards to `tv_odin_main`, which the Odin client exports from `client/src/android_entry.odin`. It also holds `tv_android_mouse_position` and `tv_android_touch_position`, wrappers around raylib's `GetMousePosition` and `GetTouchPosition`.

**Decisions:**
- Odin's `-build-mode:shared` for Android defines its own `main` that returns immediately, and starts the program from a library init hook. Either would conflict with raylib's startup. Building plain objects and supplying `main` here avoids both.
- The touch wrapper exists for the same reason. The lab's joystick and look controls read two fingers at once, and `GetTouchPosition` returns a `Vector2`.
- The mouse wrapper exists because Odin and the NDK disagree about returning a struct of two floats. Odin returns it in registers, and the NDK's ABI returns it through a hidden pointer, so a direct call from Odin makes raylib write through a garbage pointer. Compiling the call in C uses the NDK's own convention. The same applies to any raylib function returning `Vector2`, `Vector3`, `Vector4`, `Quaternion`, `Rectangle`, or `Matrix`, and `scripts/check_android_abi.py` fails the build if the Odin objects call one directly.

## CI and Workflows

- `.github/workflows/android.yml` runs on demand and uploads the signed APK as an artifact.

## Fixes and Problems

### `AndroidManifest.xml`
- None recorded yet. The packaging steps were run locally with the Ubuntu builds of `aapt`, `zipalign`, and `apksigner` against a stand-in library. `aapt dump badging` reported the launcher activity, `armeabi-v7a`, and minimum SDK 29, and `zipalign` and `apksigner` verified the result.

### `entry.c`
- The first installed build crashed immediately on launch. A comparison of Odin's calling-convention lowering with the NDK compiler's for all 33 raylib functions the client calls found exactly one difference, `GetMousePosition`, which the client calls every frame. The wrapper in this file is the fix. It was confirmed on the device: the app runs.
