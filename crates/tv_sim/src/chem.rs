// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "chem.rs"
// ============================================================================

//! The seam between the simulation and whatever decides what two compounds do
//! when they meet.

use tv_proto::CompoundId;

/// Result of two compounds meeting.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Outcome {
    /// 0.0 is inert, 1.0 is as volatile as the game allows.
    pub volatility: f32,
    /// Released energy in arbitrary game units.
    pub heat: f32,
}

/// Anything that can say what happens when compound `a` meets compound `b`.
/// Implementations must be pure: same inputs, same output.
pub trait ChemBackend {
    /// Outcome of `a` meeting `b`. Order of the arguments does not matter.
    fn react(&self, a: CompoundId, b: CompoundId) -> Outcome;
}

/// Backend where nothing ever reacts.
#[derive(Debug, Clone, Copy, Default)]
pub struct NullChem;

impl ChemBackend for NullChem {
    fn react(&self, _a: CompoundId, _b: CompoundId) -> Outcome {
        Outcome::default()
    }
}

/// Lookup table of pair outcomes. Stored as a sorted vector so lookups are a
/// binary search and nothing depends on hash iteration order.
#[derive(Debug, Clone, Default)]
pub struct TableChem {
    entries: Vec<((CompoundId, CompoundId), Outcome)>,
}

impl TableChem {
    /// Builds a table. When a pair appears twice the later entry wins.
    pub fn from_entries(
        items: impl IntoIterator<Item = (CompoundId, CompoundId, Outcome)>,
    ) -> Self {
        let mut entries: Vec<_> = items
            .into_iter()
            .map(|(a, b, o)| ((a.min(b), a.max(b)), o))
            .collect();
        entries.sort_by_key(|e| e.0); // stable, so equal keys keep input order
        let mut out: Vec<((CompoundId, CompoundId), Outcome)> = Vec::with_capacity(entries.len());
        for e in entries {
            match out.last_mut() {
                Some(last) if last.0 == e.0 => *last = e,
                _ => out.push(e),
            }
        }
        Self { entries: out }
    }

    /// Number of distinct pairs stored.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// True when no pair is stored.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

impl ChemBackend for TableChem {
    fn react(&self, a: CompoundId, b: CompoundId) -> Outcome {
        let key = (a.min(b), a.max(b));
        match self.entries.binary_search_by_key(&key, |e| e.0) {
            Ok(i) => self.entries[i].1,
            Err(_) => Outcome::default(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn o(v: f32) -> Outcome {
        Outcome {
            volatility: v,
            heat: v * 10.0,
        }
    }

    #[test]
    fn lookup_ignores_argument_order() {
        let t = TableChem::from_entries([(2, 1, o(0.5)), (3, 3, o(0.9))]);
        assert_eq!(t.react(1, 2), o(0.5));
        assert_eq!(t.react(2, 1), o(0.5));
        assert_eq!(t.react(3, 3), o(0.9));
        assert_eq!(t.react(1, 3), Outcome::default());
    }

    #[test]
    fn later_duplicate_wins() {
        let t = TableChem::from_entries([(1, 2, o(0.1)), (2, 1, o(0.7))]);
        assert_eq!(t.len(), 1);
        assert_eq!(t.react(1, 2), o(0.7));
    }

    #[test]
    fn null_backend_is_inert() {
        assert_eq!(NullChem.react(1, 2), Outcome::default());
    }
}
