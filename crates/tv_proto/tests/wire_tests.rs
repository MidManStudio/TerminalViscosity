// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_proto.md, section "wire_tests.rs"
// ============================================================================

//! Wire protocol tests: round trips, the datagram size budget, and hostile input.
use tv_proto::wire::{
    decode_events, encode_events, BalloonState, Chamber, Command, Event, Recipe, Snapshot,
    BALLOON_STATE_BYTES, SNAPSHOT_HEADER_BYTES,
};
use tv_proto::{DecodeError, MAX_BALLOONS_PER_SNAPSHOT, MAX_CHAMBERS, MAX_PAYLOAD_BYTES};

fn recipe(n: usize) -> Recipe {
    Recipe {
        chambers: (0..n)
            .map(|i| Chamber {
                compound: i as u16 + 1,
                volume_ml: 100 + i as u16,
            })
            .collect(),
    }
}

fn balloon(i: u16) -> BalloonState {
    BalloonState {
        id: i,
        owner: (i % 8) as u8,
        compound: i * 3,
        pos_mm: [i as i32 * 1000, -(i as i32) * 7, 1_500_000],
        vel_cms: [i as i16, -(i as i16), 900],
        flags: 0,
    }
}

fn full_snapshot() -> Snapshot {
    Snapshot {
        tick: 123_456,
        balloons: (0..MAX_BALLOONS_PER_SNAPSHOT as u16).map(balloon).collect(),
    }
}

#[test]
fn command_roundtrip() {
    let cmd = Command::Throw {
        recipe: recipe(3),
        dir: [100, -200, 300],
        power: 200,
    };
    assert_eq!(Command::decode(&cmd.encode()), Ok(cmd));
}

#[test]
fn snapshot_roundtrip() {
    let snap = full_snapshot();
    let bytes = snap.encode().unwrap();
    assert_eq!(Snapshot::decode(&bytes), Ok(snap));
}

#[test]
fn events_roundtrip() {
    let events = vec![
        Event::Detonate {
            balloon: 1,
            compound: 2,
            volatility_q: 255,
            pos_mm: [1, -2, 3],
            radius_mm: 4,
        },
        Event::Detonate {
            balloon: 9,
            compound: 8,
            volatility_q: 0,
            pos_mm: [-1, 0, 7],
            radius_mm: 600,
        },
    ];
    let bytes = encode_events(&events).unwrap();
    assert_eq!(decode_events(&bytes), Ok(events));
}

#[test]
fn full_snapshot_fits_one_datagram() {
    let bytes = full_snapshot().encode().unwrap();
    assert_eq!(
        bytes.len(),
        SNAPSHOT_HEADER_BYTES + MAX_BALLOONS_PER_SNAPSHOT * BALLOON_STATE_BYTES
    );
    assert!(
        bytes.len() <= MAX_PAYLOAD_BYTES,
        "snapshot is {} bytes",
        bytes.len()
    );
}

#[test]
fn one_event_per_balloon_fits_one_datagram() {
    let e = Event::Detonate {
        balloon: 0,
        compound: 0,
        volatility_q: 0,
        pos_mm: [0; 3],
        radius_mm: 0,
    };
    let events = vec![e; MAX_BALLOONS_PER_SNAPSHOT];
    assert!(encode_events(&events).unwrap().len() <= MAX_PAYLOAD_BYTES);
}

#[test]
fn oversized_snapshot_is_refused() {
    let mut snap = full_snapshot();
    snap.balloons.push(balloon(999));
    assert!(snap.encode().is_err());
}

#[test]
fn every_truncation_fails_without_panicking() {
    let cmd = Command::Throw {
        recipe: recipe(MAX_CHAMBERS),
        dir: [1, 2, 3],
        power: 9,
    }
    .encode();
    for len in 0..cmd.len() {
        assert!(
            Command::decode(&cmd[..len]).is_err(),
            "command prefix {len} decoded"
        );
    }
    let snap = full_snapshot().encode().unwrap();
    for len in 0..snap.len() {
        assert!(
            Snapshot::decode(&snap[..len]).is_err(),
            "snapshot prefix {len} decoded"
        );
    }
}

#[test]
fn trailing_bytes_are_rejected() {
    let mut bytes = Command::Throw {
        recipe: recipe(1),
        dir: [0; 3],
        power: 1,
    }
    .encode();
    bytes.push(0);
    assert_eq!(Command::decode(&bytes), Err(DecodeError::Trailing(1)));
}

#[test]
fn bad_tags_and_counts_are_rejected() {
    assert_eq!(Command::decode(&[0xFF]), Err(DecodeError::BadTag(0xFF)));
    assert_eq!(
        Snapshot::decode(&[0x01, 0, 0, 0, 0, 200]),
        Err(DecodeError::TooMany {
            got: 200,
            max: MAX_BALLOONS_PER_SNAPSHOT
        })
    );
    // zero chambers
    assert!(Command::decode(&[0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).is_err());
    // five chambers
    assert!(matches!(
        Command::decode(&[0x10, 5]),
        Err(DecodeError::TooMany { .. })
    ));
}

#[test]
fn hostile_event_count_does_not_allocate_huge() {
    assert_eq!(decode_events(&[0x21, 255]), Err(DecodeError::UnexpectedEnd));
}

#[test]
fn random_bytes_never_panic() {
    // Small xorshift so the test needs no dependencies and stays reproducible.
    let mut s: u64 = 0x2545_F491_4F6C_DD1D;
    for _ in 0..20_000 {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        let len = (s % 64) as usize;
        let buf: Vec<u8> = (0..len)
            .map(|i| (s >> ((i % 8) * 8)) as u8 ^ i as u8)
            .collect();
        let _ = Command::decode(&buf);
        let _ = Snapshot::decode(&buf);
        let _ = decode_events(&buf);
    }
}
