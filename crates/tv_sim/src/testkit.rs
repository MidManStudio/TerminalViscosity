// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "testkit.rs"
// ============================================================================

//! Reproducible command scripts and synthetic chemistry, shared by tests,
//! benchmarks, and the server self-test. Not used by the game itself.

use crate::chem::{Outcome, TableChem};
use crate::rng::SplitMix64;
use tv_proto::{Chamber, Command, CompoundId, PlayerId, Recipe, MAX_CHAMBERS};

/// A fully populated table over `compounds` ids. Values are derived from the
/// seed only, and carry no chemical meaning.
pub fn synthetic_chem(compounds: u16, seed: u64) -> TableChem {
    let mut rng = SplitMix64::new(seed);
    let mut items = Vec::new();
    for a in 0..compounds {
        for b in a..compounds {
            let volatility = rng.below(1000) as f32 / 1000.0;
            items.push((
                a as CompoundId,
                b as CompoundId,
                Outcome {
                    volatility,
                    heat: volatility * 50.0,
                },
            ));
        }
    }
    TableChem::from_entries(items)
}

/// A random but valid recipe drawn from compounds `0..compounds`.
pub fn random_recipe(rng: &mut SplitMix64, compounds: u16) -> Recipe {
    let n = 1 + rng.below(MAX_CHAMBERS as u32) as usize;
    Recipe {
        chambers: (0..n)
            .map(|_| Chamber {
                compound: rng.below(compounds.max(1) as u32) as CompoundId,
                volume_ml: 10 + rng.below(200) as u16,
            })
            .collect(),
    }
}

/// Commands for one tick: every fifth tick a random player throws a random balloon.
pub fn scripted_commands(
    rng: &mut SplitMix64,
    tick: u32,
    players: u8,
    compounds: u16,
) -> Vec<(PlayerId, Command)> {
    if tick % 5 != 0 {
        return Vec::new();
    }
    let player = rng.below(players.max(1) as u32) as PlayerId;
    let dir = [
        rng.below(2001) as i16 - 1000,
        200 + rng.below(800) as i16,
        rng.below(2001) as i16 - 1000,
    ];
    let power = 50 + rng.below(150) as u8;
    vec![(
        player,
        Command::Throw {
            recipe: random_recipe(rng, compounds),
            dir,
            power,
        },
    )]
}
