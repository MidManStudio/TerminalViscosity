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

- Odin dev-2026-10 lists `linux_arm32` as a target and has a `-subtarget:android` option. It needs the environment variable `ODIN_ANDROID_NDK` to be set.
- With that variable pointing at a placeholder folder, `odin check` of the whole client for `linux_arm32` with the Android subtarget passed. The soft-body package built to real ARM EABI5 32-bit object files. Linking was not tried, because it needs the NDK.
- raylib 6.0's Makefile supports `PLATFORM_ANDROID`. `ANDROID_ARCH=arm` selects `armv7a-linux-androideabi<API>-clang` from the NDK. It defaults to OpenGL ES 2.0, so the `glsl100` shaders in `client/shaders/` are the ones to use. Its default API level is 29.
- raylib's Android backend defines `android_main`, which calls the program's own C `main`. Assets come through Android's asset manager. Per a source comment, it maps touch point 0 to mouse input, which is what the lab's drag interaction uses. The mouse button state mapping was not checked.
- raylib's own Android template links `-lm -lc -lraylib -llog -landroid -lEGL -lGLESv2 -lOpenSLES -ldl` into a shared library and packages it with `aapt`.

## What is not verified

- Linking Odin objects, raylib, the native app glue, and the Rust static library into one shared library with the NDK.
- Building `tv_ffi` for `armv7-linux-androideabi`. The Rust crates have only been built and tested on 64-bit x86. They avoid pointer-sized assumptions in their data formats, but that has not been run on a 32-bit target.
- APK packaging and running on the device.
- `mid-net` on 32-bit ARM Android.
- Whether the A13 really only installs armeabi-v7a. This comes from comments in the midnote workflow and was not checked against the device.

## Plan

1. A manual Android workflow modelled on midnote's: free disk, JDK 17, SDK with build-tools 34.0.0, NDK r26d, Rust with `armv7-linux-androideabi`.
2. Build raylib 6.0 from source for `ANDROID_ARCH=arm`.
3. Build `tv_ffi` as a static library for `armv7-linux-androideabi` with `cargo` and the NDK linker.
4. Build the client with `-target:linux_arm32 -subtarget:android -build-mode:obj`, using a client entry that does not open a desktop window.
5. Link everything into `libmain.so` with the NDK, add the native app glue and the Android libraries above.
6. Package, sign with a throwaway debug keystore, verify, and upload the APK.
7. Install on the phone and check the lab.

The first run of such a workflow is expected to need fixes. The midnote workflow's history shows the same pattern.

## Code changes the plan implies

- A branch in `client/src/tv_ffi.odin` for the Android foreign import, keyed on `ODIN_PLATFORM_SUBTARGET == .Android`, since the current import lists Linux desktop libraries.
- Shader loading from the APK's assets, since the desktop path resolves files next to the executable.
- Touch-friendly controls for the lab.
