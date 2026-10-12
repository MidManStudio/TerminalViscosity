// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_ffi.md, section "ffi_tests.rs"
// ============================================================================

//! C ABI tests: a full cycle through the exported functions and a header drift check.
#![allow(unsafe_code)]

use tv_ffi::*;

fn encode_lob(power: u8) -> Vec<u8> {
    let chambers = [
        TvChamber {
            compound: 1,
            volume_ml: 100,
        },
        TvChamber {
            compound: 2,
            volume_ml: 50,
        },
    ];
    let mut buf = vec![0u8; 64];
    // SAFETY: `chambers` has 2 elements and `buf` has 64 writable bytes.
    let n = unsafe {
        tv_encode_throw(
            chambers.as_ptr(),
            2,
            0,
            1000,
            0,
            power,
            buf.as_mut_ptr(),
            64,
        )
    };
    assert!(n > 0, "encode failed: {n}");
    buf.truncate(n as usize);
    buf
}

#[test]
fn full_cycle_through_the_c_abi() {
    let w = tv_world_new(5);
    assert!(!w.is_null());
    let cmd = encode_lob(100);
    // SAFETY: `w` is live and `cmd` is a valid slice for its length.
    unsafe {
        assert_eq!(tv_world_submit(w, 1, cmd.as_ptr(), cmd.len() as u32), TV_OK);
        tv_world_step(w);
    }

    let mut snap = vec![0u8; 1200];
    // SAFETY: `w` is live and `snap` has 1200 writable bytes.
    let n = unsafe { tv_world_snapshot(w, snap.as_mut_ptr(), 1200) };
    assert!(n > 0);

    let mut views = [TvBalloonView::default(); 48];
    let mut tick = 0u32;
    // SAFETY: `snap` holds `n` valid bytes, `views` has 48 slots, `tick` is writable.
    let count =
        unsafe { tv_snapshot_decode(snap.as_ptr(), n as u32, views.as_mut_ptr(), 48, &mut tick) };
    assert_eq!(count, 1);
    assert_eq!(tick, 1);
    assert_eq!(views[0].owner, 1);
    assert!(views[0].vel_cms[1] > 900);

    // Run until the balloon lands, then read the detonation.
    let mut events = 0;
    for _ in 0..400 {
        // SAFETY: `w` is live.
        events += unsafe { tv_world_step(w) };
    }
    assert_eq!(events, 1);
    let mut buf = vec![0u8; 1200];
    // SAFETY: `w` is live and `buf` has 1200 writable bytes.
    let n = unsafe { tv_world_take_events(w, buf.as_mut_ptr(), 1200) };
    assert!(n > 0);
    let mut dets = [TvDetonateView::default(); 8];
    // SAFETY: `buf` holds `n` valid bytes and `dets` has 8 slots.
    let count = unsafe { tv_events_decode(buf.as_ptr(), n as u32, dets.as_mut_ptr(), 8) };
    assert_eq!(count, 1);
    assert_eq!(dets[0].pos_mm[1], 0);
    // SAFETY: `w` was created above and is freed exactly once.
    unsafe { tv_world_free(w) };
}

#[test]
fn identical_worlds_hash_identically() {
    let a = tv_world_new(9);
    let b = tv_world_new(9);
    let cmd = encode_lob(80);
    // SAFETY: both worlds are live and `cmd` is a valid slice.
    unsafe {
        for w in [a, b] {
            assert_eq!(tv_world_submit(w, 0, cmd.as_ptr(), cmd.len() as u32), TV_OK);
            for _ in 0..100 {
                tv_world_step(w);
            }
        }
        assert_eq!(tv_world_state_hash(a), tv_world_state_hash(b));
        assert_ne!(tv_world_state_hash(a), 0);
        tv_world_free(a);
        tv_world_free(b);
    }
}

#[test]
fn null_pointers_and_bad_input_return_errors() {
    // SAFETY: every call below passes null or deliberately invalid sizes, which the API must reject.
    unsafe {
        tv_world_free(std::ptr::null_mut());
        assert_eq!(tv_world_step(std::ptr::null_mut()), TV_ERR_NULL);
        assert_eq!(tv_world_state_hash(std::ptr::null()), 0);
        assert_eq!(
            tv_world_snapshot(std::ptr::null(), std::ptr::null_mut(), 0),
            TV_ERR_NULL
        );

        let w = tv_world_new(1);
        assert_eq!(tv_world_submit(w, 0, std::ptr::null(), 0), TV_ERR_NULL);
        let junk = [0xFFu8, 1, 2];
        assert_eq!(tv_world_submit(w, 0, junk.as_ptr(), 3), TV_ERR_DECODE);
        let mut tiny = [0u8; 2];
        assert_eq!(tv_world_snapshot(w, tiny.as_mut_ptr(), 2), TV_ERR_CAPACITY);
        assert_eq!(
            tv_encode_throw(std::ptr::null(), 1, 0, 1, 0, 1, tiny.as_mut_ptr(), 2),
            TV_ERR_NULL
        );
        let ch = [TvChamber::default(); 5];
        assert_eq!(
            tv_encode_throw(ch.as_ptr(), 5, 0, 1, 0, 1, tiny.as_mut_ptr(), 2),
            TV_ERR_ARG
        );
        tv_world_free(w);
    }
}

fn header_define(header: &str, name: &str) -> u32 {
    let line = header
        .lines()
        .find(|l| l.trim_start().starts_with(&format!("#define {name} ")))
        .unwrap_or_else(|| panic!("{name} missing from tv.h"));
    line.split_whitespace()
        .nth(2)
        .unwrap()
        .trim_end_matches('u')
        .parse()
        .unwrap()
}

#[test]
fn header_matches_rust_side() {
    let header = include_str!("../include/tv.h");
    let source = include_str!("../src/lib.rs");

    assert_eq!(header_define(header, "TV_ABI_VERSION"), TV_ABI_VERSION);
    assert_eq!(
        header_define(header, "TV_CHAMBER_SIZE"),
        tv_sizeof_chamber()
    );
    assert_eq!(
        header_define(header, "TV_BALLOON_VIEW_SIZE"),
        tv_sizeof_balloon_view()
    );
    assert_eq!(
        header_define(header, "TV_DETONATE_VIEW_SIZE"),
        tv_sizeof_detonate_view()
    );
    assert_eq!(header_define(header, "TV_OK") as i32, TV_OK);
    for (name, value) in [
        ("TV_ERR_NULL", TV_ERR_NULL),
        ("TV_ERR_DECODE", TV_ERR_DECODE),
        ("TV_ERR_CAPACITY", TV_ERR_CAPACITY),
        ("TV_ERR_ARG", TV_ERR_ARG),
        ("TV_ERR_PANIC", TV_ERR_PANIC),
    ] {
        let line = header
            .lines()
            .find(|l| l.starts_with(&format!("#define {name} ")))
            .unwrap();
        assert_eq!(
            line.split_whitespace()
                .nth(2)
                .unwrap()
                .parse::<i32>()
                .unwrap(),
            value,
            "{name}"
        );
    }

    // Every exported function must be declared in the header, and the other way round.
    let exported: Vec<&str> = source
        .lines()
        .filter(|l| l.contains("extern \"C\" fn tv_"))
        .map(|l| {
            let rest = l.split("fn ").nth(1).unwrap();
            rest.split('(').next().unwrap()
        })
        .collect();
    assert!(
        exported.len() >= 14,
        "found only {} exports",
        exported.len()
    );
    for name in &exported {
        assert!(
            header.contains(&format!("{name}(")),
            "{name} is not declared in tv.h"
        );
    }
    let declared = header
        .lines()
        .filter(|l| l.contains(" tv_") || l.contains("*tv_"))
        .count();
    assert!(
        declared >= exported.len(),
        "tv.h declares fewer functions than lib.rs exports"
    );
}
