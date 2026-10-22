# Terminal Viscosity

A multiplayer-first 3D water-balloon fight where the balloons are filled with liquid chemicals you craft beforehand. Simple shapes, heavy shader effects.

Status: scaffold. The simulation core, wire protocol, C ABI, CI, benchmarks, and a crafting-lab prototype (a walkable first-person chemistry lab room, a 3D water balloon with jiggle held by a tied tip, a scene system, and a local database check on DixScript) exist. The arena, networking, chemistry integration, and balloon painting do not.

## Layout

- `crates/` Rust: `tv_proto`, `tv_sim`, `tv_ffi`, `tv_server`
- `client/` Odin and raylib client
- `benches/` Criterion benchmarks (separate Cargo workspace)
- `scripts/` repository checks, benchmark tools, client build
- `docs/` architecture, CI, benchmarks, open decisions, and copied reference docs

## Try it

```
cargo test --workspace
cargo run --release -p tv_server -- selftest
python3 scripts/check_headers.py
bash scripts/build_client.sh --selftest   # needs odin on PATH
```

Start with `docs/ARCHITECTURE.md`, then `docs/OPEN_DECISIONS.md`. Android is a requirement, see `docs/ANDROID.md`.

## License

Proprietary. Copyright (c) 2026 MidManStudio. All rights reserved. See `LICENSE`.
