# Open decisions

Things the scaffold deliberately does not settle. Each one is a real choice, not a technical default, so none of them was picked silently.

## Chemistry

- **Which level the game uses.** `chemistry_core` in unity-chem-sim is an atom-level simulation (Lennard-Jones dynamics and bonding behind a handle-based C API). `nuclear_core` works on macroscopic samples. A thrown balloon needs a compound-level answer, which neither crate provides directly. The seam is `ChemBackend` in `tv_sim`. One option is a table-driven backend for normal compounds, with `nuclear_core` for nuclear balloons and the atom simulation for lab visuals.
- **The compound list.** `unity-chem-sim` points to `grand-theft-grimoire-gameplay-reference.md` for its predefined compounds. That file was not in any of the reference repositories, so no real compounds exist in this repo yet. The simulation tests use synthetic data.
- **Toolchain for the adapter.** `chemistry_core` needs Rust 1.83 or newer. The adapter crate would sit outside the root workspace, the way `benches/` does, so the 1.75 floor keeps holding for everything else.

## Networking

- **Transport.** Options are ENet (vendored with Odin as `vendor:ENet`), finishing the C interface of `mid-net` (QUIC, and today only its packet codec is exposed through C), or WebSocket or WebTransport. Browsers cannot open raw UDP sockets, so if playtesting from a phone browser matters, native-only transports cannot talk to browser clients.
- **Server shape.** Dedicated headless server, listen server, or both. The simulation does not care.
- **Tick and snapshot rates.** The sim ticks at 60 Hz. The snapshot rate is not chosen.

## Game rules still placeholders

- Total balloon volume (1000 ml), chamber count (4), the burst combining rule, the blast radius formula, launch speed per unit of power, and spawn positions are scaffold values in `tv_sim`.
- Players, hit detection against players, and the arena do not exist in the simulation yet.

## Art

- Canvas size (64 by 64) and palette (16 colours) are proposals in `tv_proto/src/art.rs`. Whether player art needs moderation or a fixed template set is open.

## Browser build

- `vendor:raylib` in the pinned Odin release ships a prebuilt web library (`wasm/libraylib.web.a`) and a `RAYLIB_WASM_LIB` setting, so Odin has raylib support for WebAssembly. The rest of the path is not built or tested: the Emscripten link step, the browser main loop, linking the Rust library built for `wasm32-unknown-emscripten`, and hosting. Shaders for it already exist in `client/shaders/glsl100/`. If the path turns out too fragile, the fallback is writing the client in C, where raylib's web target is first class.

## Housekeeping

- **License.** No license file or `license` field exists. See the workspace notes in the Rust guidelines.
- **Operating systems.** The Odin foreign import lists Linux libraries only.
- **Codespaces or devcontainer.** Not set up.
