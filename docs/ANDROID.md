# Android

Android is a requirement. The target device is a Samsung Galaxy A13. This page records what is known, what was verified, and the plan.

## Requirements taken from the midnote build workflow

These come from `.github/workflows/build-andriod.yml` in the midnote repository, which already produces an installable APK for the same phone.

| Item | Value in midnote |
|---|---|
| ABI | `armeabi-v7a`, Rust target `armv7-linux-androideabi`. The workflow comments say the A13 ships a 32-bit OS and reports only armeabi-v7a as installable, even though its chip is 64-bit capable. |
| NDK | r26d via `nttld/setup-ndk@v1` with `link-to-sdk: true`. r28 or newer is only needed for the 16 KB page-size rule on Play Store submissions. |
| Java | Temurin 17 |
| SDK | `android-actions/setup-android@v3` with `platform-tools` and `build-tools;34.0.0` (the default set has no `apksigner`) |
| Signing | A throwaway debug keystore generated on every run with `keytool`, then `apksigner sign` and `apksigner verify`. No secrets. |
| Trigger | Manual (`workflow_dispatch`), debug build for sideloading |
| Disk | `jlumbroso/free-disk-space` first, because several ABIs exhausted the runner earlier. One ABI only. |
| Output | The signed APK as an artifact |

The 32-bit point is the one to keep in mind. Everything native has to build for 32-bit ARM: the Rust library, raylib, and the Odin code.

## What was checked

- Odin dev-2026-10 lists `linux_arm32` as a target and has a `-subtarget:android` option. It needs `ODIN_ANDROID_NDK` set, and `ODIN_ANDROID_SDK` for some modes.
- The whole client, including raylib bindings and the Rust FFI bindings, compiles to 45 real ARM EABI5 object files for `armv7a-linux-androideabi`. The LLVM target triple matches the NDK's, so the float calling convention matches the NDK-built raylib.
- Only 71 symbols are unresolved across those objects. 14 are `tv_*` functions (`libtv_ffi.a`), 32 are raylib functions (`libraylib.a`), and the rest are bionic libc and libm functions and compiler runtime helpers that the NDK's clang supplies.
- Odin has no `main` or other conflicting entry in these objects. The one exported entry is `tv_odin_main`.
- raylib 6.0's Makefile supports `PLATFORM_ANDROID`. `ANDROID_ARCH=arm` selects `armv7a-linux-androideabi<API>-clang` from the NDK. It defaults to OpenGL ES 2.0, so the `glsl100` shaders are the ones to use.
- raylib's Android backend defines `android_main`, which calls the program's own C `main`. Assets come through Android's asset manager. Per a source comment, it maps touch point 0 to mouse input.
- The packaging stage of the build script ran locally with Ubuntu's `aapt`, `zipalign`, and `apksigner` and a stand-in library. `aapt dump badging` showed the launcher `NativeActivity`, `native-code: 'armeabi-v7a'`, and minimum SDK 29. `zipalign -c` and `apksigner verify` passed.

## Findings about Odin on Android

- `-o:speed` and `-o:aggressive` crash the compiler inside LLVM for 32-bit ARM Android. `-o:minimal` and `-o:size` work.
- `-build-mode:executable` is rejected for the Android subtarget. `-build-mode:shared` is accepted, but it defines a `main` that returns immediately and starts from a library init hook, which would stop raylib's `android_main` from starting the game.
- Foreign import paths must be relative to the source file. Absolute paths are rejected.
- `vendor:raylib` has no Android branch, so it would link the desktop library. That does not matter here, because Odin only compiles and the NDK does the link.

## First CI run

The first run of the Android workflow, on GitHub's runner with NDK r26d, passed three stages: raylib 6.0 built for armv7 (a 2.4 MB static library), `tv_ffi` built for `armv7-linux-androideabi` (a 20 MB static library), and the client compiled to 45 Odin objects. The link failed on `undefined symbol: __real_fopen`. raylib's Android backend wraps `fopen` to read assets from the APK, which needs `-Wl,--wrap=fopen` on the final link. That flag, and the rest of raylib's Android link flags, are now in the script.

## First install and the crash on launch

The build succeeded and the APK installed on the phone, but the app crashed as soon as it opened. There is no logcat on this workflow, so the cause was narrowed down by reading the code and comparing calling conventions.

- Odin compiled the client for an ARMv6 CPU (`arm1176jzf-s`) by default. The build now passes `-microarch:cortex-a7`.
- For all 33 raylib functions the client calls, Odin's lowering was compared with what the NDK compiler produces for the same C prototypes. Exactly one differs: `GetMousePosition`, which returns an 8-byte struct of floats. The NDK's ABI passes a hidden return pointer in `r0`, and Odin returns the value in registers. raylib therefore writes through whatever `r0` held, and the client calls it every frame. That fits a crash right after start-up.
- The fix is a C wrapper (`tv_android_mouse_position` in `android/entry.c`) and `scripts/check_android_abi.py`, which fails the build if Odin calls a raylib function with this kind of return type directly.

This is the leading explanation, not a confirmed one. It still needs a run on the device.

## What is not verified

- Linking everything into `libmain.so` (the first attempt failed on a missing flag, now fixed and not yet re-run), and whether the Odin objects start correctly without the Odin runtime start-up.
- The Rust crates compile for `armv7-linux-androideabi`, but their tests have only been run on 64-bit x86, not on a 32-bit target.
- Installing and running on the phone.
- `mid-net` on 32-bit ARM Android.
- Whether the A13 really only installs armeabi-v7a. This comes from comments in the midnote workflow and was not checked against the device.

## Pipeline

`scripts/build_android.sh` runs five stages, and `.github/workflows/android.yml` runs them in CI. Both are described in `docs/CI.md`.

1. `raylib`: build raylib 6.0 from source with the NDK for `ANDROID_ARCH=arm`.
2. `rust`: build `tv_ffi` as a static library for `armv7-linux-androideabi`.
3. `odin`: compile the client to object files with `-target:linux_arm32 -subtarget:android -build-mode:object -o:minimal`.
4. `link`: link the objects, `android/entry.c`, raylib (which already contains the NDK's native app glue), and the Rust library into `libmain.so`.
5. `package`: `aapt`, `zipalign`, and `apksigner` with a throwaway debug key.

The first run of this workflow is expected to need fixes, mainly in stages 1, 2, and 4, which need the NDK. The midnote workflow's history shows the same pattern.

## Known gaps in the client on Android

- The lab has no touch-specific controls. It relies on raylib's mapping of the first touch to the mouse, and whether button presses are mapped as well was not checked. The 3D lab was written so a single pointer does everything: pressing on the balloon grabs it, pressing elsewhere turns the camera. Zooming is by mouse wheel only, so there is no zoom on a phone yet.
- The balloon physics costs about 0.5 ms per frame with `-o:minimal` on a desktop core. A phone core is several times slower. The lab overlay prints the real figure, which a screenshot will show. Lowering `frequency` in `balloon.default_config` is the first remedy, and `TV_OPT=size` for the build is the second.
- The 3D draw calls (`BeginMode3D`, `DrawMesh`, `UploadMesh`, `UpdateMeshBuffer`) pass structs larger than 16 bytes by value. Odin and clang were compared and describe them identically. The first sight of them running on the phone is still the real test.
- The lab renders with OpenGL ES 2.0 shaders, which compiled and rendered correctly only on a desktop software renderer. A different GPU driver could still reject something.
- `os.args` is empty on Android, and the Odin runtime start-up is not run, so code on the Android path must not use package-level initializers.
- Rotation and resize are handled by the manifest, and the layout reads the screen size once at start.
