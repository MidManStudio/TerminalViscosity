# Reference docs

Verbatim copies of docs from sibling MidManStudio / Mid-D-Man repos that
Terminal Viscosity builds on. They are snapshots, not live links: if a source
repo moves on, these drift. Re-sync by replacing the tarball in
`.mdix/replacements/` and running the `Apply replacements` workflow.

| Folder | Source repo | Branch | Commit | What is here |
|---|---|---|---|---|
| `unity-chem-sim/` | MidManStudio/unity-chem-sim | main | `0c5ce9e` | `chemistry_core` (atom-level LJ + bonding sim) and `nuclear_core` (decay, fission, fusion) docs, FFI surface, architecture |
| `mid-engine/` | Mid-D-Man/mid-engine | main | `74713a0` | architecture, `mid-net` (QUIC netcode + wire codec FFI), `mid-math`, roadmap, design mandates |
| `MidManStudio_Unity/` | MidManStudio/MidManStudio_Unity | master | `9732bd3` | `projectile_core` (Rust projectile sim) and the Unity netcode / projectile package docs |
| `DixScript-Rust/` | Mid-D-Man/DixScript-Rust | master | `be92f34` | DixScript language docs, `mdix-odin` bindings, `mdix-cli` commands |
| `guidelines/` | shared across the repos | n/a | n/a | documentation / commenting rules and Rust crate rules |

## Notes

- `guidelines/DOCUMENTATION_AND_COMMENTING_GUIDELINES.md` and
  `guidelines/RUST_AND_CRATE_GUIDELINES.md` are byte-identical in
  unity-chem-sim, MidManStudio_Unity and DixScript-Rust, so they appear once.
  `mid-engine` ships a different `RUST_AND_CRATE_GUIDELINES.md`; it is kept as
  `RUST_AND_CRATE_GUIDELINES.mid-engine.md`.
- Toolchain floors stated in these docs: `chemistry_core` needs Rust 1.83 or
  newer (see `unity-chem-sim/architecture.md`); `nuclear_core` declares 1.75.
- Left out on purpose (large or off-topic here): `mid-engine/docs/mid-ecs.md`,
  `DixScript-Rust/docs/dixscript/utilities.md` and `arena-ast.md`, the
  per-platform `NOTE.md` placeholders, and the Unity-only sample / scene-setup
  docs.
- `grand-theft-grimoire-gameplay-reference.md` (the predefined compound list
  that `unity-chem-sim` points to) was not in any of these repos, so it is not
  included.
