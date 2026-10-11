// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_proto.md, section "art_tests.rs"
// ============================================================================

use tv_proto::art::{ArtCanvas, ART_H, ART_MAX_ENCODED_BYTES, ART_PIXELS, ART_W};

fn noisy() -> ArtCanvas {
    let mut c = ArtCanvas::blank(0);
    let mut s: u32 = 12345;
    for y in 0..ART_H {
        for x in 0..ART_W {
            s = s.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            c.set(x, y, (s >> 24) as u8);
        }
    }
    for (i, p) in c.palette.iter_mut().enumerate() {
        *p = [i as u8 * 16, 255 - i as u8 * 16, i as u8];
    }
    c
}

#[test]
fn blank_canvas_compresses_to_a_few_dozen_bytes() {
    let bytes = ArtCanvas::blank(3).encode();
    assert!(bytes.len() < 200, "blank canvas took {} bytes", bytes.len());
    assert_eq!(ArtCanvas::decode(&bytes).unwrap(), ArtCanvas::blank(3));
}

#[test]
fn noisy_canvas_never_exceeds_raw_bound() {
    let c = noisy();
    let bytes = c.encode();
    assert!(bytes.len() <= ART_MAX_ENCODED_BYTES);
    assert_eq!(ArtCanvas::decode(&bytes).unwrap(), c);
}

#[test]
fn simple_drawing_roundtrips() {
    let mut c = ArtCanvas::blank(1);
    for i in 0..ART_W {
        c.set(i, i % ART_H, 7);
        c.set(ART_W - 1 - i, i % ART_H, 9);
    }
    assert_eq!(ArtCanvas::decode(&c.encode()).unwrap(), c);
    assert_eq!(c.get(0, 0), 7);
    assert_eq!(c.get(ART_W, 0), 0);
}

#[test]
fn malformed_input_is_rejected() {
    let good = ArtCanvas::blank(2).encode();
    for len in 0..good.len() {
        assert!(
            ArtCanvas::decode(&good[..len]).is_err(),
            "prefix {len} decoded"
        );
    }
    let mut extra = good.clone();
    extra.push(0);
    assert!(ArtCanvas::decode(&extra).is_err());

    // RLE run past the end of the canvas
    let mut bad = vec![1u8];
    bad.extend_from_slice(&[0u8; 48]);
    for _ in 0..(ART_PIXELS / 255 + 2) {
        bad.extend_from_slice(&[0, 255]);
    }
    assert!(ArtCanvas::decode(&bad).is_err());

    // RLE palette index out of range
    let mut bad_idx = vec![1u8];
    bad_idx.extend_from_slice(&[0u8; 48]);
    bad_idx.extend_from_slice(&[16, 1]);
    assert!(ArtCanvas::decode(&bad_idx).is_err());

    // unknown format byte
    let mut bad_fmt = good;
    bad_fmt[0] = 9;
    assert!(ArtCanvas::decode(&bad_fmt).is_err());
}

#[test]
fn random_bytes_never_panic() {
    let mut s: u64 = 0x9E37_79B9_7F4A_7C15;
    for _ in 0..5_000 {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        let len = (s % 400) as usize;
        let mut buf: Vec<u8> = (0..len).map(|i| (s >> ((i % 8) * 8)) as u8).collect();
        if let Some(first) = buf.first_mut() {
            *first %= 3;
        }
        let _ = ArtCanvas::decode(&buf);
    }
}
