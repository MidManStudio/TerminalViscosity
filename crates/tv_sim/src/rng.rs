// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_sim.md, section "rng.rs"
// ============================================================================

//! SplitMix64 generator with a state that can be hashed and restored.

/// Small, fast, seedable generator. Not for cryptography.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SplitMix64 {
    state: u64,
}

impl SplitMix64 {
    /// Starts a stream from `seed`.
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    /// Current internal state, for hashing or snapshotting.
    pub fn state(&self) -> u64 {
        self.state
    }

    /// Next 64 random bits.
    pub fn next_u64(&mut self) -> u64 {
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform value in `0..n`. Returns 0 when `n` is 0.
    pub fn below(&mut self, n: u32) -> u32 {
        if n == 0 {
            return 0;
        }
        // Multiply-shift range reduction, bias is negligible for game use.
        (((self.next_u64() >> 32) * n as u64) >> 32) as u32
    }

    /// Uniform float in `[0, 1)` with 24 bits of precision.
    pub fn next_f32(&mut self) -> f32 {
        (self.next_u64() >> 40) as f32 / (1u64 << 24) as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Reference values from an independent Python implementation of the
    // published SplitMix64 algorithm.
    #[test]
    fn matches_reference_vectors() {
        let mut g = SplitMix64::new(0);
        assert_eq!(g.next_u64(), 0xe220a8397b1dcdaf);
        assert_eq!(g.next_u64(), 0x6e789e6aa1b965f4);
        assert_eq!(g.next_u64(), 0x06c45d188009454f);
        let mut g = SplitMix64::new(1234567);
        assert_eq!(g.next_u64(), 0x599ed017fb08fc85);
        assert_eq!(g.next_u64(), 0x2c73f08458540fa5);
        assert_eq!(g.next_u64(), 0x883ebce5a3f27c77);
    }

    #[test]
    fn below_stays_in_range_and_handles_zero() {
        let mut g = SplitMix64::new(7);
        assert_eq!(g.below(0), 0);
        for _ in 0..10_000 {
            assert!(g.below(13) < 13);
        }
    }

    #[test]
    fn floats_stay_in_unit_interval() {
        let mut g = SplitMix64::new(99);
        for _ in 0..10_000 {
            let f = g.next_f32();
            assert!((0.0..1.0).contains(&f));
        }
    }
}
