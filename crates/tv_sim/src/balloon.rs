// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "balloon.rs"
// ============================================================================

//! Recipe validation and the placeholder rules for what a burst balloon does.

use crate::chem::{ChemBackend, Outcome};
use tv_proto::{CompoundId, Recipe, MAX_CHAMBERS};

/// Largest total fill a balloon can hold, in millilitres. Placeholder value.
pub const MAX_TOTAL_VOLUME_ML: u32 = 1000;

/// Why a recipe was refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecipeError {
    /// No chambers at all.
    NoChambers,
    /// More than [`MAX_CHAMBERS`].
    TooManyChambers,
    /// A chamber with zero volume.
    EmptyChamber,
    /// Total fill above [`MAX_TOTAL_VOLUME_ML`].
    OverVolume,
}

/// Checks a recipe against the crafting limits.
pub fn validate_recipe(r: &Recipe) -> Result<(), RecipeError> {
    if r.chambers.is_empty() {
        return Err(RecipeError::NoChambers);
    }
    if r.chambers.len() > MAX_CHAMBERS {
        return Err(RecipeError::TooManyChambers);
    }
    if r.chambers.iter().any(|c| c.volume_ml == 0) {
        return Err(RecipeError::EmptyChamber);
    }
    if total_volume_ml(r) > MAX_TOTAL_VOLUME_ML {
        return Err(RecipeError::OverVolume);
    }
    Ok(())
}

/// Sum of all chamber volumes.
pub fn total_volume_ml(r: &Recipe) -> u32 {
    r.chambers.iter().map(|c| c.volume_ml as u32).sum()
}

/// Compound with the most volume. Ties go to the lowest compound id so the
/// answer does not depend on chamber order.
pub fn dominant_compound(r: &Recipe) -> CompoundId {
    let mut best: Option<(u16, CompoundId)> = None;
    for c in &r.chambers {
        best = match best {
            None => Some((c.volume_ml, c.compound)),
            Some((v, id)) if c.volume_ml > v || (c.volume_ml == v && c.compound < id) => {
                Some((c.volume_ml, c.compound))
            }
            keep => keep,
        };
    }
    best.map(|b| b.1).unwrap_or(0)
}

/// Combined outcome when every membrane breaks at once: the most volatile pair
/// sets volatility, and heat adds up over all pairs. Scaffold rule, expected to
/// be replaced once the reaction design is settled.
pub fn impact_outcome(r: &Recipe, chem: &impl ChemBackend) -> Outcome {
    let mut out = Outcome::default();
    for (i, a) in r.chambers.iter().enumerate() {
        for b in &r.chambers[i + 1..] {
            let o = chem.react(a.compound, b.compound);
            out.volatility = out.volatility.max(o.volatility);
            out.heat += o.heat;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::chem::TableChem;
    use tv_proto::Chamber;

    fn r(parts: &[(u16, u16)]) -> Recipe {
        Recipe {
            chambers: parts
                .iter()
                .map(|&(compound, volume_ml)| Chamber {
                    compound,
                    volume_ml,
                })
                .collect(),
        }
    }

    #[test]
    fn validation_rules() {
        assert_eq!(validate_recipe(&r(&[])), Err(RecipeError::NoChambers));
        assert_eq!(
            validate_recipe(&r(&[(1, 0)])),
            Err(RecipeError::EmptyChamber)
        );
        assert_eq!(
            validate_recipe(&r(&[(1, 1); 5])),
            Err(RecipeError::TooManyChambers)
        );
        assert_eq!(
            validate_recipe(&r(&[(1, 600), (2, 401)])),
            Err(RecipeError::OverVolume)
        );
        assert_eq!(validate_recipe(&r(&[(1, 500), (2, 500)])), Ok(()));
    }

    #[test]
    fn dominant_ignores_chamber_order() {
        assert_eq!(dominant_compound(&r(&[(7, 100), (3, 100), (9, 50)])), 3);
        assert_eq!(dominant_compound(&r(&[(3, 100), (7, 100), (9, 50)])), 3);
        assert_eq!(dominant_compound(&r(&[(7, 10), (3, 100)])), 3);
    }

    #[test]
    fn outcome_takes_max_volatility_and_sums_heat() {
        let t = TableChem::from_entries([
            (
                1,
                2,
                Outcome {
                    volatility: 0.2,
                    heat: 1.0,
                },
            ),
            (
                1,
                3,
                Outcome {
                    volatility: 0.8,
                    heat: 2.0,
                },
            ),
            (
                2,
                3,
                Outcome {
                    volatility: 0.5,
                    heat: 4.0,
                },
            ),
        ]);
        let o = impact_outcome(&r(&[(1, 10), (2, 10), (3, 10)]), &t);
        assert_eq!(
            o,
            Outcome {
                volatility: 0.8,
                heat: 7.0
            }
        );
    }
}
