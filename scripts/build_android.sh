#!/usr/bin/env bash
# ============================================================================
# NOTICE: Full documentation, design decisions, and fix history for this file
# live in docs/CI.md, section "build_android.sh"
# ============================================================================
# Builds a sideloadable debug APK for 32-bit ARM Android (armeabi-v7a).
#
# Needs on PATH or in the environment:
#   cargo with the armv7-linux-androideabi target, odin, git, make, python3
#   ANDROID_NDK_HOME  Android NDK (r26d is what midnote uses)
#   ANDROID_HOME      Android SDK with platform-tools, build-tools and a platform
#   java and keytool  JDK 17
#
# Stages (run all by default, or name some): raylib rust odin link package
#   bash scripts/build_android.sh
#   bash scripts/build_android.sh odin link package
#
# Settings (environment): TV_ANDROID_API (29), TV_ANDROID_TARGET_SDK (34),
# TV_ANDROID_BUILD_TOOLS (34.0.0), TV_ANDROID_PLATFORM (34), TV_RAYLIB_TAG (6.0)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

API="${TV_ANDROID_API:-29}"
TARGET_SDK="${TV_ANDROID_TARGET_SDK:-34}"
BUILD_TOOLS="${TV_ANDROID_BUILD_TOOLS:-34.0.0}"
PLATFORM="${TV_ANDROID_PLATFORM:-34}"
RAYLIB_TAG="${TV_RAYLIB_TAG:-6.0}"
RUST_TARGET="armv7-linux-androideabi"
ABI="armeabi-v7a"
OUT="$root/build/android"

NDK="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"

log() { printf '\n== %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_tools() {
    if [ -z "$NDK" ] || [ ! -d "$NDK" ]; then
        die "ANDROID_NDK_HOME is not set to an existing NDK directory"
    fi
    TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
    [ -d "$TOOLCHAIN" ] || die "no linux-x86_64 toolchain under $NDK"
    CC="$TOOLCHAIN/bin/armv7a-linux-androideabi${API}-clang"
    AR="$TOOLCHAIN/bin/llvm-ar"
    NM="$TOOLCHAIN/bin/llvm-nm"
    [ -x "$CC" ] || die "missing compiler $CC (is API $API supported by this NDK?)"
}

require_sdk() {
    if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
        die "ANDROID_HOME is not set to an existing SDK directory"
    fi
    BT="$SDK/build-tools/$BUILD_TOOLS"
    ANDROID_JAR="$SDK/platforms/android-$PLATFORM/android.jar"
    for f in "$BT/aapt" "$BT/zipalign" "$BT/apksigner" "$ANDROID_JAR"; do
        [ -e "$f" ] || die "missing $f (install build-tools;$BUILD_TOOLS and platforms;android-$PLATFORM)"
    done
}

stage_raylib() {
    log "raylib $RAYLIB_TAG for Android armv7 (API $API)"
    require_tools
    if [ ! -d "$OUT/raylib" ]; then
        mkdir -p "$OUT"
        git clone --depth 1 --branch "$RAYLIB_TAG" https://github.com/raysan5/raylib.git "$OUT/raylib"
    fi
    make -C "$OUT/raylib/src" clean >/dev/null 2>&1 || true
    make -C "$OUT/raylib/src" \
        PLATFORM=PLATFORM_ANDROID \
        ANDROID_NDK="$NDK" \
        ANDROID_ARCH=arm \
        ANDROID_API_VERSION="$API" \
        RAYLIB_LIBTYPE=STATIC \
        -j"$(nproc)"
    [ -f "$OUT/raylib/src/libraylib.a" ] || die "raylib did not produce libraylib.a"
    ls -la "$OUT/raylib/src/libraylib.a"
}

stage_rust() {
    log "tv_ffi for $RUST_TARGET"
    require_tools
    export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$CC"
    export CC_armv7_linux_androideabi="$CC"
    export AR_armv7_linux_androideabi="$AR"
    cargo build --release -p tv_ffi --target "$RUST_TARGET"
    ls -la "target/$RUST_TARGET/release/libtv_ffi.a"
}

stage_odin() {
    log "client as armv7 Android objects"
    require_tools
    [ -n "$SDK" ] || die "ANDROID_HOME must be set, Odin reads it for -subtarget:android"
    rm -rf "$OUT/obj"
    mkdir -p "$OUT/obj"
    # Notes on the flags:
    #  -build-mode:object  Odin only compiles. Linking is done below with the NDK.
    #  -no-entry-point     android/entry.c provides `main`.
    #  -o:minimal          this Odin release crashes inside LLVM with -o:speed and
    #                      -o:aggressive on 32-bit ARM Android.
    #  -define:TV_LIB      foreign import paths must be relative to the source file.
    ODIN_ANDROID_NDK="$NDK" ODIN_ANDROID_SDK="$SDK" odin build client/src \
        -target:linux_arm32 -subtarget:android -minimum-os-version:"$API" \
        -build-mode:object -no-entry-point -reloc-mode:pic -o:minimal \
        -vet -strict-style \
        -define:TV_LIB="../../target/$RUST_TARGET/release/libtv_ffi.a" \
        -out:"$OUT/obj/tv_client"
    local count
    count="$(find "$OUT/obj" -name '*.o' | wc -l)"
    [ "$count" -gt 0 ] || die "Odin produced no object files"
    echo "$count object files"
}

stage_link() {
    log "link libmain.so"
    require_tools
    local glue="$NDK/sources/android/native_app_glue/android_native_app_glue.c"
    [ -f "$glue" ] || die "native app glue not found at $glue"
    mkdir -p "$OUT/stage/lib/$ABI"
    "$CC" -fPIC -c "$glue" -I"$(dirname "$glue")" -o "$OUT/native_app_glue.o"
    "$CC" -fPIC -c android/entry.c -o "$OUT/entry.o"
    # --no-undefined makes missing symbols fail here instead of at app start.
    "$CC" -shared -o "$OUT/stage/lib/$ABI/libmain.so" \
        "$OUT"/obj/*.o "$OUT/entry.o" "$OUT/native_app_glue.o" \
        "$OUT/raylib/src/libraylib.a" "target/$RUST_TARGET/release/libtv_ffi.a" \
        -u ANativeActivity_onCreate \
        -Wl,--no-undefined -Wl,--gc-sections \
        -llog -landroid -lEGL -lGLESv2 -lOpenSLES -lm -ldl -lc
    ls -la "$OUT/stage/lib/$ABI/libmain.so"
    echo "exported entry points:"
    "$NM" -D --defined-only "$OUT/stage/lib/$ABI/libmain.so" | grep -E "ANativeActivity_onCreate|android_main" || die "native activity entry points missing from libmain.so"
}

stage_package() {
    log "package, align, sign"
    require_sdk
    command -v keytool >/dev/null 2>&1 || die "keytool not found, install a JDK"
    local stage="$OUT/stage" unsigned="$OUT/unsigned.apk" aligned="$OUT/aligned.apk"
    local ks="$OUT/debug.keystore" apk="$OUT/terminal-viscosity-armv7-debug.apk"
    [ -f "$stage/lib/$ABI/libmain.so" ] || die "libmain.so not built yet (run the link stage)"

    sed -e "s/@MIN_SDK@/$API/" -e "s/@TARGET_SDK@/$TARGET_SDK/" \
        android/AndroidManifest.xml > "$stage/AndroidManifest.xml"
    # Only the OpenGL ES shaders go in the APK, raylib opens them as assets.
    rm -rf "$stage/assets"
    mkdir -p "$stage/assets/shaders"
    cp -r client/shaders/glsl100 "$stage/assets/shaders/glsl100"

    rm -f "$unsigned" "$aligned" "$apk"
    "$BT/aapt" package -f -M "$stage/AndroidManifest.xml" -I "$ANDROID_JAR" \
        -A "$stage/assets" -F "$unsigned"
    (cd "$stage" && "$BT/aapt" add "$unsigned" "lib/$ABI/libmain.so")
    "$BT/zipalign" -f -p 4 "$unsigned" "$aligned"

    # Throwaway debug key, regenerated on every clean run. No secrets involved.
    if [ ! -f "$ks" ]; then
        keytool -genkeypair -keystore "$ks" -storepass android -keypass android \
            -alias tvdebug -keyalg RSA -keysize 2048 -validity 10000 \
            -dname "CN=Terminal Viscosity Debug"
    fi
    "$BT/apksigner" sign --ks "$ks" --ks-pass pass:android --key-pass pass:android \
        --ks-key-alias tvdebug --out "$apk" "$aligned"
    "$BT/apksigner" verify --verbose "$apk"
    ls -la "$apk"
    echo "contents:"
    unzip -l "$apk" | grep -E "AndroidManifest|libmain|heat_distort" || true
}

stages=("$@")
if [ "${#stages[@]}" -eq 0 ]; then
    stages=(raylib rust odin link package)
fi
for s in "${stages[@]}"; do
    case "$s" in
        raylib|rust|odin|link|package) "stage_$s" ;;
        -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "unknown stage '$s' (raylib rust odin link package)" ;;
    esac
done
log "done"
