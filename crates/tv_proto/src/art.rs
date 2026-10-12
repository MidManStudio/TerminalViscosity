// ============================================================================
// NOTICE: Full documentation, design decisions, and fix history for this file
// live in docs/tv_proto.md, section "art.rs"
// ============================================================================

//! Balloon art: a palette canvas players draw on, sent once per player over a reliable channel.
//!
//! At 256 by 256 pixels a canvas is far larger than one datagram, so it is not
//! sent in snapshots. Players are free to draw whatever they like and nothing
//! here filters content.

use crate::codec::{DecodeError, Reader, Writer};

/// Canvas width in pixels.
pub const ART_W: usize = 256;
/// Canvas height in pixels.
pub const ART_H: usize = 256;
/// Palette entries. Pixels store a 4-bit palette index.
pub const PALETTE_LEN: usize = 16;
/// Pixel count.
pub const ART_PIXELS: usize = ART_W * ART_H;
/// Hard upper bound on an encoded canvas: format byte + palette + packed pixels.
pub const ART_MAX_ENCODED_BYTES: usize = 1 + PALETTE_LEN * 3 + ART_PIXELS / 2;

const FORMAT_RAW: u8 = 0;
const FORMAT_RLE: u8 = 1;

/// A palette-indexed drawing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtCanvas {
    /// RGB palette.
    pub palette: [[u8; 3]; PALETTE_LEN],
    pixels: Vec<u8>,
}

impl ArtCanvas {
    /// A canvas filled with palette index `fill`. Indices above 15 wrap into range.
    pub fn blank(fill: u8) -> Self {
        Self {
            palette: [[0; 3]; PALETTE_LEN],
            pixels: vec![fill & 0x0F; ART_PIXELS],
        }
    }

    /// Sets one pixel. Out-of-range coordinates are ignored.
    pub fn set(&mut self, x: usize, y: usize, index: u8) {
        if x < ART_W && y < ART_H {
            self.pixels[y * ART_W + x] = index & 0x0F;
        }
    }

    /// Reads one pixel, or 0 outside the canvas.
    pub fn get(&self, x: usize, y: usize) -> u8 {
        if x < ART_W && y < ART_H {
            self.pixels[y * ART_W + x]
        } else {
            0
        }
    }

    fn write_palette(&self, w: &mut Writer) {
        for rgb in &self.palette {
            w.bytes(rgb);
        }
    }

    fn encode_raw(&self) -> Vec<u8> {
        let mut w = Writer::with_capacity(ART_MAX_ENCODED_BYTES);
        w.u8(FORMAT_RAW);
        self.write_palette(&mut w);
        for pair in self.pixels.chunks_exact(2) {
            w.u8(pair[0] | (pair[1] << 4));
        }
        w.finish()
    }

    fn encode_rle(&self) -> Vec<u8> {
        let mut w = Writer::with_capacity(256);
        w.u8(FORMAT_RLE);
        self.write_palette(&mut w);
        let mut i = 0;
        while i < ART_PIXELS {
            let idx = self.pixels[i];
            let mut run = 1usize;
            while i + run < ART_PIXELS && self.pixels[i + run] == idx && run < u16::MAX as usize {
                run += 1;
            }
            w.u8(idx);
            w.u16(run as u16);
            i += run;
        }
        w.finish()
    }

    /// Encodes with whichever of raw or run-length is smaller. Never exceeds
    /// [`ART_MAX_ENCODED_BYTES`].
    pub fn encode(&self) -> Vec<u8> {
        let raw = self.encode_raw();
        let rle = self.encode_rle();
        if rle.len() < raw.len() {
            rle
        } else {
            raw
        }
    }

    /// Decodes either format, rejecting malformed or trailing input.
    pub fn decode(bytes: &[u8]) -> Result<Self, DecodeError> {
        let mut r = Reader::new(bytes);
        let format = r.u8()?;
        let mut palette = [[0u8; 3]; PALETTE_LEN];
        for entry in &mut palette {
            let rgb = r.bytes(3)?;
            entry.copy_from_slice(rgb);
        }
        let mut pixels = Vec::with_capacity(ART_PIXELS);
        match format {
            FORMAT_RAW => {
                for b in r.bytes(ART_PIXELS / 2)? {
                    pixels.push(b & 0x0F);
                    pixels.push(b >> 4);
                }
            }
            FORMAT_RLE => {
                while pixels.len() < ART_PIXELS {
                    let idx = r.u8()?;
                    let run = r.u16()? as usize;
                    if idx as usize >= PALETTE_LEN {
                        return Err(DecodeError::BadValue("palette index"));
                    }
                    if run == 0 || pixels.len() + run > ART_PIXELS {
                        return Err(DecodeError::BadValue("run length"));
                    }
                    pixels.resize(pixels.len() + run, idx);
                }
            }
            t => return Err(DecodeError::BadTag(t)),
        }
        r.finish()?;
        Ok(Self { palette, pixels })
    }
}
