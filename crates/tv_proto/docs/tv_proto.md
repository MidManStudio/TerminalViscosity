# tv_proto

## Overview

Wire protocol and balloon art codec for Terminal Viscosity. The crate has no dependencies and no unsafe code. Every decoder returns an error on bad input and never panics, so the same functions can be pointed at untrusted network bytes.

All numbers are little-endian. Positions travel as fixed-point millimetres and velocities as centimetres per second, which makes one balloon exactly 24 bytes inside a snapshot.

## Modules

### `Cargo.toml`
**What it does:** Package manifest. No dependencies, opts into the workspace lint table.

**Decisions:**
- `rust-version = "1.75"` matches the floor the rest of the workspace keeps.
- Version stays at `0.0.1` while in development, per the Rust guidelines.

### `lib.rs`
**What it does:** Declares the modules and the protocol constants: `PROTOCOL_VERSION`, `MAX_PAYLOAD_BYTES` (1200), `MAX_BALLOONS_PER_SNAPSHOT` (48), `MAX_CHAMBERS` (4).

**Decisions:**
- 1200 bytes is the datagram budget. It stays under the usual path MTU after IP and UDP or QUIC headers, so a snapshot never fragments.
- 48 balloons follows from the budget: 6 header bytes plus 48 times 24 is 1158 bytes.
- `MAX_CHAMBERS = 4` is a proposal. The design notes mention two-chamber and three-cell balloons, and four leaves room above that. Change it in this one place.

### `codec.rs`
**What it does:** `Writer` appends little-endian values. `Reader` reads them with bounds checks. `DecodeError` and `EncodeError` describe failures.

**Decisions:**
- Hand-written instead of serde or bincode, to keep the crate dependency free and the byte layout explicit.
- `Reader::finish` rejects trailing bytes so two different byte strings can never decode to the same message.

### `wire.rs`
**What it does:** `Command`, `Event`, `Snapshot`, `Recipe`, `Chamber`, `BalloonState`, and their encode and decode functions.

**Decisions:**
- A throw carries its whole recipe until an inventory design exists. Once the server owns crafted balloons, the command can shrink to a slot number.
- Soft-body nodes are never sent. Clients run the jiggle locally from the high-level state.
- Events travel in a count-prefixed list with a tag per event, so new event kinds can be added without changing the framing.
- Detonation volatility is quantized to one byte.

**Tests:** `tests/wire_tests.rs`.

### `art.rs`
**What it does:** `ArtCanvas`, a 256 by 256 canvas with a 16-colour palette, and its codec.

**Decisions:**
- Raw form is a format byte, 48 palette bytes, and 32768 bytes of packed 4-bit pixels, 32817 bytes at most. A run-length form (palette index plus a 16-bit run length) is chosen automatically when it is smaller, so a blank canvas costs 55 bytes.
- The canvas was expanded from 64 by 64 on the owner's instruction, and nothing filters what players draw. That is deliberate. Player art is far larger than one datagram, so it must travel on a reliable stream, once per player, and never inside snapshots.
- Size and palette are constants at the top of the file. A 256-colour palette would need one byte per pixel and is not done.

**Benchmarks:** see `benches/benches/proto_bench.rs` (group `art_256x256`).

**Tests:** `tests/art_tests.rs`.

### `wire_tests.rs`
**What it does:** Round trips for every message, the 1200-byte snapshot budget, rejection of every truncated prefix, bad tags, bad counts, trailing bytes, and 20,000 pseudo-random inputs that must never panic.

### `art_tests.rs`
**What it does:** Round trips for blank, noisy, and hand-drawn canvases, the raw-size upper bound, malformed RLE input, and pseudo-random input that must never panic.

## CI and Workflows

- `.github/workflows/ci.yml` job `rust` builds, tests, lints, and formats this crate on Rust 1.75 and stable.
- `.github/workflows/bench.yml` runs `benches/benches/proto_bench.rs`.

## Fixes and Problems

### `wire.rs`
- None recorded yet.

### `art.rs`
- None recorded yet.
