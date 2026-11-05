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
**What it does:** Declares the modules and the protocol constants: `PROTOCOL_VERSION` (2), `MAX_PAYLOAD_BYTES` (1200), `MAX_BALLOONS_PER_SNAPSHOT` (40), `MAX_PLAYERS` (8), `MAX_CHAMBERS` (4).

**Decisions:**
- 1200 bytes is the datagram budget. It stays under the usual path MTU after IP and UDP or QUIC headers, so a snapshot never fragments.
- 40 balloons and 8 players follow from the budget: 7 header bytes plus 8 times 16 plus 40 times 24 is 1095 bytes, which leaves 105 bytes spare. Version 1 had no players and held 48 balloons.
- The protocol version is 3. Version 2 added players to the snapshot, the input command, and the slot in a throw. Version 3 added the buttons byte to the input command, which a version 2 peer cannot read.
- `MAX_CHAMBERS = 4` is a proposal. The design notes mention two-chamber and three-cell balloons, and four leaves room above that. Change it in this one place.

### `codec.rs`
**What it does:** `Writer` appends little-endian values, including one signed byte. `Reader` reads them with bounds checks. `DecodeError` and `EncodeError` describe failures.

**Decisions:**
- Hand-written instead of serde or bincode, to keep the crate dependency free and the byte layout explicit.
- `Reader::finish` rejects trailing bytes so two different byte strings can never decode to the same message.

### `wire.rs`
**What it does:** `Command`, `Event`, `Snapshot`, `Recipe`, `Chamber`, `BalloonState`, `PlayerState`, and their encode and decode functions, and the heading helpers `yaw_to_q` and `q_to_yaw`. A snapshot holds the players, 16 bytes each, then the balloons. A command is a throw, which names the loadout slot the balloon comes from, or an input, which is the stick, the heading, and the buttons held. `BUTTON_JUMP` is the first bit of the buttons.

**Decisions:**
- A throw carries its whole recipe until an inventory design exists. Once the server owns crafted balloons, the command can shrink to a slot number.
- Soft-body nodes are never sent. Clients run the jiggle locally from the high-level state.
- Events travel in a count-prefixed list with a tag per event, so new event kinds can be added without changing the framing.
- Detonation volatility is quantized to one byte.
- The simulation moves the players, so the client sends a stick and a heading and not a position. The heading is a `u16` in which a full turn is 65536, so it wraps by itself and resolves to about 0.005 degrees. Zero faces -z and a quarter turn faces +x, the way the lab's player turns.
- The input carries no pitch. A throw already carries its own direction, so the simulation has no use for where the head tilts, and other players' pitch can be added when they are drawn.
- The slot of a throw comes back in the `flags` byte of the balloon, so every client can find the drawing that goes with a balloon in flight from its owner and slot.
- A jump is a button held and sent with every input, and not a command of its own, because the client already sends its input every tick, so a button held is not lost with one packet and the simulation does not need to remember presses. The buttons are one byte, so there are seven more bits for other buttons. Bits nobody has given a meaning are ignored.
- The stick is `i8` from -127 to 127. -128 is not a stick value, and the FFI refuses it.

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
**What it does:** Round trips for every message, including input with both signs, with no button, and with every bit of the buttons, and the heading helpers (wrapping, negative turns, and a round trip of the wire value), the 1200-byte snapshot budget with 8 players and 40 balloons, rejection of every truncated prefix of a throw, an input, and a snapshot, bad tags, bad player and balloon counts, trailing bytes, and 20,000 pseudo-random inputs that must never panic.

### `art_tests.rs`
**What it does:** Round trips for blank, noisy, and hand-drawn canvases, the raw-size upper bound, malformed RLE input, and pseudo-random input that must never panic.

## CI and Workflows

- `.github/workflows/ci.yml` job `rust` builds, tests, lints, and formats this crate on Rust 1.75 and stable.
- `.github/workflows/bench.yml` runs `benches/benches/proto_bench.rs`.

## Fixes and Problems

### `wire.rs`
- Version 2 was written to give the arena players. The first sketch kept hit points, a selected slot, and pitch in the player state, 18 bytes each. None of them has a use before the combat rules exist, and the owner has not specified the rules, so the state was cut to id, position, heading, and a reserved byte.
- Version 3 was written to give the arena a jump. The input grew from five bytes to six.
- The test that fed a short snapshot header to the decoder had to change when the header grew by a byte: the old bytes now read as a player count of 200, so it checks the player limit and the balloon limit separately.

### `art.rs`
- None recorded yet.
