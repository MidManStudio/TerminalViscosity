# CI and tooling

## Overview

Two GitHub Actions workflows and four scripts. The workflow files are not part of the replacements archive. The token that runs the replacements workflow cannot create files under `.github/workflows/`, so those two files are added to the repository by hand.

## Workflows

- `.github/workflows/ci.yml` runs on pushes to `main`, on pull requests, and on demand.
  - `rust` builds and tests the workspace on Rust 1.75 and on stable. On stable it also checks formatting, runs clippy with warnings denied, and builds the docs with warnings denied.
  - `determinism` builds `tv_server`, runs the self-test twice with seed 1 in separate processes and requires identical output, then requires that seed 2 gives different output.
  - `docs` runs `scripts/check_headers.py`.
  - `odin` installs a pinned Odin release (`ODIN_TAG` at the top of the file), type-checks the client, runs the soft-body tests, validates both shader files with glslang, builds the client and runs its self-test, then renders one headless screenshot under a virtual display and keeps it as the `lab-screenshot` artifact.
- `.github/workflows/bench.yml` runs on demand and on pushes to `main` that touch code or benchmark files. It runs the Criterion benchmarks and the Odin benchmark, merges them with `scripts/bench_summary.py`, compares against `benches/baseline.json` with `scripts/bench_compare.py`, and uploads `bench-results`. Comparison only reports by default. The `fail_pct` input turns a regression above that percentage into a failure.

- `.github/workflows/android.yml` runs on demand only. It sets up Java 17, the Android SDK with build-tools 34.0.0, NDK r26d, Rust with the `armv7-linux-androideabi` target, and Odin, runs `scripts/build_android.sh`, and uploads a signed debug APK named `terminal-viscosity-armv7-debug.apk`. The setup mirrors the working midnote Android workflow.

Not covered yet: the browser (WebAssembly) build, any server networking, and chemistry adapters. See `docs/OPEN_DECISIONS.md`.

## Modules

### `check_headers.py`
**What it does:** Enforces the documentation guidelines. Every `.rs`, `.odin`, `.h`, `.fs`, `.py`, `.sh`, and `.toml` file must open with the NOTICE header, the doc file it names must exist, that doc must have a section for the file, crate docs must end with Fixes and Problems, and docs must avoid em dashes and filler words.

**Decisions:**
- `docs/references/` and `.mdix/` are skipped, since those hold copied material.
- The doc root for a file is the nearest ancestor directory that has a `docs/` folder.
- Run it with `python3 scripts/check_headers.py` from the repository root.

### `bench_summary.py`
**What it does:** Reads Criterion output and the Odin benchmark text file, writes `bench_results.json`, and prints a markdown table, which it also appends to the job summary when running in Actions.

**Decisions:** Results are keyed `rust/<criterion id>` and `odin/<name>`, and compared by median.

### `bench_compare.py`
**What it does:** Compares two result files and flags changes beyond `--warn-pct` (25 by default). With `--fail-pct` above zero it exits non-zero on a larger regression.

**Decisions:** Report-only by default, because hosted runners are noisy. A missing baseline is not an error.

### `build_client.sh`
**What it does:** Builds the Rust static library, builds the Odin client into `build/`, copies the shaders next to it, and optionally runs `--selftest`.

### `check_android_abi.py`
**What it does:** Reads the undefined symbols of the Odin object files, matches them against the prototypes in `raylib.h`, and fails if any raylib function that Odin calls returns a struct made only of floats (`Vector2`, `Vector3`, `Vector4`, `Quaternion`, `Rectangle`, `Matrix`, and similar).

**Decisions:**
- Odin's 32-bit ARM backend returns those in registers and the NDK returns them through a hidden pointer, so a direct call crashes. Such calls must go through a C wrapper in `android/entry.c`.
- Integer-only structs such as `Color` and `Shader` are lowered the same way on both sides and are allowed.
- It was tested against the objects from before the fix, where it flags `GetMousePosition`, and against the fixed objects, where it passes.

### `build_android.sh`
**What it does:** Builds the Android debug APK in five stages that can be run separately: `raylib`, `rust`, `odin`, `link`, `package`. Output goes to `build/android/`.

**Decisions:**
- Odin only compiles. The final link is done with the NDK's clang, because Odin's own Android link modes did not fit raylib's startup, see `android/docs/android.md`.
- The link flags follow raylib's own Android template. `-Wl,--wrap=fopen` is mandatory, because raylib's Android backend reads assets through a wrapped `fopen`. `-Wl,--no-undefined` makes a missing symbol fail in CI instead of when the app starts.
- Packaging follows raylib's own Android recipe: `aapt package`, then `aapt add` for the library, `zipalign`, then `apksigner` with a throwaway debug key. No secrets are involved.
- The Odin objects are built with `-microarch:cortex-a7`, because Odin's 32-bit ARM default is an ARMv6 CPU. After the Odin stage, `scripts/check_android_abi.py` runs.
- Settings come from environment variables (`TV_ANDROID_API`, `TV_ANDROID_TARGET_SDK`, `TV_ANDROID_BUILD_TOOLS`, `TV_ANDROID_PLATFORM`, `TV_RAYLIB_TAG`).

## Fixes and Problems

### `check_headers.py`
- None recorded yet.

### `bench_summary.py`
- None recorded yet.

### `bench_compare.py`
- None recorded yet.

### `build_client.sh`
- The shaders were first read from the working directory. The script now copies them next to the executable, and the client resolves them from there.

### `build_android.sh`
- First CI run: the `raylib`, `rust`, and `odin` stages passed on the real NDK (raylib 6.0 built for armv7, `tv_ffi` built for `armv7-linux-androideabi`, 45 Odin objects). The `link` stage failed with `undefined symbol: __real_fopen`, because the link line lacked `-Wl,--wrap=fopen`, which raylib's source says every final link must pass. Added, together with the other flags from raylib's Android template.
- raylib's Makefile redefines `__ANDROID_API__` on the command line, which prints a harmless macro-redefinition warning for every file.
- The `package` stage was run locally with Ubuntu's `aapt`, `zipalign`, and `apksigner`. It has not yet run in CI.

### `check_android_abi.py`
- Written after the first installed build crashed on launch. See `client/docs/client.md`, section `android_entry.odin`.

