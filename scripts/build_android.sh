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
# Stages (run all by default, or name some): raylib rust odin link mdix package
#   bash scripts/build_android.sh
#   bash scripts/build_android.sh odin link mdix package
#
# Settings (environment): TV_ANDROID_API (29), TV_ANDROID_TARGET_SDK (34),
# TV_ANDROID_BUILD_TOOLS (34.0.0), TV_ANDROID_PLATFORM (34), TV_RAYLIB_TAG (6.0),
# TV_OPT (minimal), the Odin optimization level for the client,
# TV_MDIX_COMMIT and TV_MDIX_SHA256, which pin the DixScript library the APK carries
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

API="${TV_ANDROID_API:-29}"
TARGET_SDK="${TV_ANDROID_TARGET_SDK:-34}"
BUILD_TOOLS="${TV_ANDROID_BUILD_TOOLS:-34.0.0}"
PLATFORM="${TV_ANDROID_PLATFORM:-34}"
RAYLIB_TAG="${TV_RAYLIB_TAG:-6.0}"
OPT="${TV_OPT:-minimal}"
# DixScript's own CI publishes a prebuilt libmdix_ffi.so for armeabi-v7a in its
# repository. The APK carries that exact file, found by commit and checked by
# checksum, so no Rust is compiled for it here. To move to a newer DixScript,
# change both values together.
MDIX_COMMIT="${TV_MDIX_COMMIT:-35ae2d23a62a0ad6b97ca0016fda0ef01c8e0584}"
MDIX_SHA256="${TV_MDIX_SHA256:-68814f5a23db4291273bed36a8b41f7015d948211d759776e2e3ba7929a4f2b0}"
MDIX_URL="https://raw.githubusercontent.com/Mid-D-Man/DixScript-Rust/$MDIX_COMMIT/com.midmanstudio.mdix/Runtime/Plugins/Android/armeabi-v7a/libmdix_ffi.so"
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
    #                      -o:aggressive on 32-bit ARM Android. minimal is the level
    #                      known to run on the phone. TV_OPT=size also compiles and is
    #                      about five times faster for the balloon physics, but it has
    #                      not been tried on a device.
    #  -microarch          Odin's 32-bit ARM default is an ARMv6 CPU (arm1176jzf-s).
    #                      cortex-a7 is plain ARMv7-A, which every armeabi-v7a phone,
    #                      including the A13's cores in 32-bit mode, can run.
    #  -define:TV_LIB      foreign import paths must be relative to the source file.
    ODIN_ANDROID_NDK="$NDK" ODIN_ANDROID_SDK="$SDK" odin build client/src \
        -target:linux_arm32 -subtarget:android -minimum-os-version:"$API" \
        -build-mode:object -no-entry-point -reloc-mode:pic -o:"$OPT" -microarch:cortex-a7 \
        -vet -strict-style \
        -define:TV_LIB="../../target/$RUST_TARGET/release/libtv_ffi.a" \
        -out:"$OUT/obj/tv_client"
    local count
    count="$(find "$OUT/obj" -name '*.o' | wc -l)"
    [ "$count" -gt 0 ] || die "Odin produced no object files"
    echo "$count object files"
    # Odin and the NDK disagree on how a struct of floats is returned. See the script.
    ls "$OUT/raylib/src/raylib.h" >/dev/null 2>&1 || die "raylib.h not found, run the raylib stage first"
    python3 scripts/check_android_abi.py "$OUT/raylib/src/raylib.h" "$NM" "$OUT"/obj/*.o
}

stage_link() {
    log "link libmain.so"
    require_tools
    mkdir -p "$OUT/stage/lib/$ABI"
    # The NDK's native app glue is already inside libraylib.a: raylib's Makefile
    # compiles it into the archive, and -u ANativeActivity_onCreate pulls it in.
    "$CC" -fPIC -c android/entry.c -o "$OUT/entry.o"
    # Flags follow raylib's own Android template. --wrap=fopen is required by raylib:
    # its Android backend redirects fopen to read from the APK's assets, and the
    # wrapper calls __real_fopen, which only exists when the final link passes
    # this flag. --no-undefined makes missing symbols fail here instead of when
    # the app starts.
    "$CC" -shared -o "$OUT/stage/lib/$ABI/libmain.so" \
        "$OUT"/obj/*.o "$OUT/entry.o" \
        "$OUT/raylib/src/libraylib.a" "target/$RUST_TARGET/release/libtv_ffi.a" \
        -u ANativeActivity_onCreate \
        -Wl,--wrap=fopen \
        -Wl,-soname,libmain.so -Wl,--exclude-libs,libatomic.a -Wl,--build-id \
        -Wl,--no-undefined -Wl,--gc-sections \
        -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -Wl,--warn-shared-textrel \
        -llog -landroid -lEGL -lGLESv2 -lOpenSLES -lm -ldl -lc
    ls -la "$OUT/stage/lib/$ABI/libmain.so"
    echo "exported entry point:"
    "$NM" -D --defined-only "$OUT/stage/lib/$ABI/libmain.so" | grep "ANativeActivity_onCreate" || die "ANativeActivity_onCreate is not exported from libmain.so"
}

stage_mdix() {
    log "libmdix_ffi.so from DixScript commit ${MDIX_COMMIT:0:10}"
    command -v curl >/dev/null 2>&1 || die "curl not found"
    command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found"
    local dest="$OUT/stage/lib/$ABI/libmdix_ffi.so"
    mkdir -p "$OUT/stage/lib/$ABI"
    curl -sSfL -o "$dest" "$MDIX_URL" || die "could not download $MDIX_URL"
    local got
    got="$(sha256sum "$dest" | cut -d' ' -f1)"
    [ "$got" = "$MDIX_SHA256" ] || die "libmdix_ffi.so checksum is $got, expected $MDIX_SHA256"
    # The game loads the library by name at start-up, so check it is the right
    # kind of file and has the entry points the game looks up.
    require_tools
    local readelf="$TOOLCHAIN/bin/llvm-readelf" nm="$TOOLCHAIN/bin/llvm-nm"
    # Capture the output first: grep -q stops reading early, and with pipefail
    # the tool's broken pipe would then count as a failed check.
    local header exports symbol
    header="$("$readelf" -h "$dest")"
    exports="$("$nm" -D --defined-only "$dest")"
    grep -q "Machine:.*ARM" <<<"$header" || die "libmdix_ffi.so is not an ARM library"
    grep -q "Class:.*ELF32" <<<"$header" || die "libmdix_ffi.so is not 32-bit"
    for symbol in mdix_version mdix_load_str mdix_builder_new mdix_builder_to_string; do
        grep -q " T $symbol\$" <<<"$exports" || die "libmdix_ffi.so does not export $symbol"
    done
    echo "needs: $("$readelf" -d "$dest" | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/' | tr '\n' ' ')"
    ls -la "$dest"
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
    [ -f "$stage/lib/$ABI/libmdix_ffi.so" ] || die "libmdix_ffi.so not fetched yet (run the mdix stage)"
    (cd "$stage" && "$BT/aapt" add "$unsigned" "lib/$ABI/libmain.so" "lib/$ABI/libmdix_ffi.so")
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
    unzip -l "$apk" | grep -E "AndroidManifest|libmain|libmdix|heat_distort|balloon" || true
}

stages=("$@")
if [ "${#stages[@]}" -eq 0 ]; then
    stages=(raylib rust odin link mdix package)
fi
for s in "${stages[@]}"; do
    case "$s" in
        raylib|rust|odin|link|mdix|package) "stage_$s" ;;
        -h|--help) sed -n '2,19p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "unknown stage '$s' (raylib rust odin link mdix package)" ;;
    esac
done
log "done"
