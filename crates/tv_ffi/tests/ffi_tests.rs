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
            1,
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
    let mut people = [TvPlayerView::default(); 8];
    let mut tick = 0u32;
    // SAFETY: `snap` holds `n` valid bytes, `views` has 48 slots, `tick` is writable.
    let count =
        unsafe { tv_snapshot_decode(snap.as_ptr(), n as u32, views.as_mut_ptr(), 48, &mut tick) };
    assert_eq!(count, 1);
    assert_eq!(tick, 1);
    assert_eq!(views[0].owner, 1);
    assert_eq!(
        views[0].flags, 1,
        "the slot of the throw comes back in flags"
    );
    assert!(views[0].vel_cms[1] > 900);
    // SAFETY: `snap` holds `n` valid bytes and `people` has 8 slots.
    let players =
        unsafe { tv_snapshot_decode_players(snap.as_ptr(), n as u32, people.as_mut_ptr(), 8) };
    assert_eq!(players, 1);
    assert_eq!(people[0].id, 1);

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

fn encode_input(forward: i8, strafe: i8, yaw_mrad: i32, buttons: u8) -> Vec<u8> {
    let mut buf = vec![0u8; 16];
    // SAFETY: `buf` has 16 writable bytes.
    let n = unsafe { tv_encode_input(forward, strafe, yaw_mrad, buttons, buf.as_mut_ptr(), 16) };
    assert!(n > 0, "encode failed: {n}");
    buf.truncate(n as usize);
    buf
}

fn encode_walk(forward: i8, strafe: i8, yaw_mrad: i32) -> Vec<u8> {
    encode_input(forward, strafe, yaw_mrad, 0)
}

fn players_of(w: *mut TvWorld) -> Vec<TvPlayerView> {
    let mut snap = vec![0u8; 1200];
    let mut views = [TvPlayerView::default(); 8];
    // SAFETY: `w` is live, `snap` has 1200 writable bytes and `views` has 8 slots.
    unsafe {
        let n = tv_world_snapshot(w, snap.as_mut_ptr(), 1200);
        assert!(n > 0);
        let count = tv_snapshot_decode_players(snap.as_ptr(), n as u32, views.as_mut_ptr(), 8);
        assert!(count >= 0, "decode failed: {count}");
        views[..count as usize].to_vec()
    }
}

#[test]
fn walking_through_the_c_abi_moves_the_decoded_player() {
    let w = tv_world_new(1);
    // A quarter turn (1571 mrad) faces +x; player 0 starts at x = 0, z = 14 m.
    let cmd = encode_walk(127, 0, 1571);
    for _ in 0..60 {
        // SAFETY: `w` is live and `cmd` is a valid slice for its length.
        unsafe {
            assert_eq!(tv_world_submit(w, 0, cmd.as_ptr(), cmd.len() as u32), TV_OK);
            tv_world_step(w);
        }
    }
    let p = players_of(w)[0];
    assert!((p.pos_mm[0] - 3200).abs() < 40, "x = {}", p.pos_mm[0]);
    assert!((p.pos_mm[2] - 14_000).abs() < 40, "z = {}", p.pos_mm[2]);
    assert!((p.yaw_mrad - 1571).abs() <= 1, "yaw = {}", p.yaw_mrad);
    // SAFETY: `w` was created above and is freed exactly once.
    unsafe { tv_world_free(w) };
}

#[test]
fn headings_wrap_and_negative_ones_come_back_positive() {
    let w = tv_world_new(1);
    let cmd = encode_walk(0, 0, -1571); // a quarter turn to the left
                                        // SAFETY: `w` is live and `cmd` is a valid slice for its length.
    unsafe {
        assert_eq!(tv_world_submit(w, 0, cmd.as_ptr(), cmd.len() as u32), TV_OK);
        tv_world_step(w);
    }
    let yaw = players_of(w)[0].yaw_mrad;
    assert!((yaw - 4712).abs() <= 2, "yaw = {yaw}, wanted 3/4 of a turn");
    let cmd = encode_walk(0, 0, 6283 + 500); // a full turn and a bit
                                             // SAFETY: as above.
    unsafe {
        assert_eq!(tv_world_submit(w, 0, cmd.as_ptr(), cmd.len() as u32), TV_OK);
        tv_world_step(w);
    }
    let yaw = players_of(w)[0].yaw_mrad;
    assert!(
        (yaw - 500).abs() <= 3,
        "yaw = {yaw}, wanted 500 after a full turn"
    );
    // SAFETY: `w` was created above and is freed exactly once.
    unsafe { tv_world_free(w) };
}

#[test]
fn decoding_players_needs_room_and_a_valid_snapshot() {
    let w = tv_world_new(1);
    let cmd = encode_walk(0, 0, 0);
    let mut views = [TvPlayerView::default(); 1];
    let mut snap = vec![0u8; 1200];
    // SAFETY: `w` is live; each buffer is as large as the size passed with it.
    unsafe {
        for id in 0..2u8 {
            assert_eq!(
                tv_world_submit(w, id, cmd.as_ptr(), cmd.len() as u32),
                TV_OK
            );
        }
        tv_world_step(w);
        let n = tv_world_snapshot(w, snap.as_mut_ptr(), 1200);
        assert_eq!(
            tv_snapshot_decode_players(snap.as_ptr(), n as u32, views.as_mut_ptr(), 1),
            TV_ERR_CAPACITY
        );
        assert_eq!(
            tv_snapshot_decode_players(snap.as_ptr(), 3, views.as_mut_ptr(), 1),
            TV_ERR_DECODE
        );
        assert_eq!(
            tv_snapshot_decode_players(std::ptr::null(), 0, views.as_mut_ptr(), 1),
            TV_ERR_NULL
        );
        assert_eq!(
            tv_encode_input(1, 1, 0, 0, std::ptr::null_mut(), 8),
            TV_ERR_NULL
        );
        let mut tiny = [0u8; 2];
        assert_eq!(
            tv_encode_input(1, 1, 0, 0, tiny.as_mut_ptr(), 2),
            TV_ERR_CAPACITY
        );
        assert_eq!(
            tv_encode_input(-128, 0, 0, 0, tiny.as_mut_ptr(), 2),
            TV_ERR_ARG
        );
        tv_world_free(w);
    }
}

#[test]
fn joining_through_the_c_abi_spawns_the_player_facing_the_middle() {
    let w = tv_world_new(1);
    // SAFETY: `w` is live until freed below, and null is handled.
    unsafe {
        assert_eq!(tv_world_join(w, 2), TV_OK);
        assert_eq!(tv_world_join(w, 2), TV_OK);
        assert_eq!(tv_world_join(w, 8), TV_ERR_ARG);
        assert_eq!(tv_world_join(std::ptr::null_mut(), 0), TV_ERR_NULL);
    }
    let people = players_of(w);
    assert_eq!(people.len(), 1);
    assert_eq!(people[0].id, 2);
    assert_eq!(people[0].pos_mm, [14_000, 0, 0]);
    // A quarter of a turn to the left of -z faces -x, which is three quarters of a turn.
    assert!(
        (people[0].yaw_mrad - 4712).abs() <= 2,
        "yaw = {}",
        people[0].yaw_mrad
    );
    // SAFETY: `w` was created above and is freed exactly once.
    unsafe { tv_world_free(w) };
}

#[test]
fn holding_jump_through_the_c_abi_lifts_the_decoded_player_and_it_lands() {
    let w = tv_world_new(1);
    let jump = encode_input(0, 0, 0, TV_BUTTON_JUMP);
    let mut peak = 0;
    for tick in 0..60 {
        // The button is held for the first tick only, as a tap would be.
        let cmd = if tick == 0 {
            jump.clone()
        } else {
            encode_input(0, 0, 0, 0)
        };
        // SAFETY: `w` is live and `cmd` is a valid slice for its length.
        unsafe {
            assert_eq!(tv_world_submit(w, 0, cmd.as_ptr(), cmd.len() as u32), TV_OK);
            tv_world_step(w);
        }
        peak = peak.max(players_of(w)[0].pos_mm[1]);
    }
    assert!(peak > 400 && peak < 480, "peaked at {peak} mm");
    assert_eq!(players_of(w)[0].pos_mm[1], 0, "and landed");
    // SAFETY: `w` was created above and is freed exactly once.
    unsafe { tv_world_free(w) };
}

#[test]
fn the_client_can_ask_how_big_the_arena_is() {
    assert_eq!(tv_arena_radius_mm(), 20_000);
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
            tv_encode_throw(std::ptr::null(), 1, 0, 0, 1, 0, 1, tiny.as_mut_ptr(), 2),
            TV_ERR_NULL
        );
        let ch = [TvChamber::default(); 5];
        assert_eq!(
            tv_encode_throw(ch.as_ptr(), 5, 0, 0, 1, 0, 1, tiny.as_mut_ptr(), 2),
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
    assert_eq!(
        header_define(header, "TV_PLAYER_VIEW_SIZE"),
        tv_sizeof_player_view()
    );
    assert_eq!(
        header_define(header, "TV_BUTTON_JUMP"),
        TV_BUTTON_JUMP as u32
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
        exported.len() >= 19,
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
