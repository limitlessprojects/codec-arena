// codec.zig — a real (if tiny) hybrid video codec whose every behavior is
// controlled by a genome: 16 effector genes (8x8 DCT, zigzag, deadzone
// quantization, integer motion estimation with half-pel refinement, intra
// refresh, adaptive Q, DC/band/low-frequency shaping) + 6 REGULATOR genes
// (GRN v1) that modulate quantizer behavior per block/frame as a function of
// decoder-derivable context: motion magnitude, GOP position, block row, and
// intra flag. Regulation is one shared code path on both sides — encoder and
// decoder can never disagree. Encode -> bitstream -> decode as INDEPENDENT
// paths; PSNR is measured on decoded output.

const std = @import("std");
const yuv = @import("yuv.zig");
const gen = @import("genome.zig");
const msssim = @import("msssim.zig");

pub const EvalOpts = struct {
    fast_sad: bool = true, // sample every 2nd pixel during motion search
    // v0.6a metric debugging: if set, decoded planes are written here as
    // DIR/<clip.name>.recon.yuv (planar, loadClip-compatible).
    dump_recon: ?[]const u8 = null,
};

pub const ClipStats = struct {
    bytes: u64,
    psnr_y: f32,
    // v0.5d: chroma visibility. U/V quality is MEASURED and reported so the
    // chroma-blind spot (CfL / chroma_q invisibility) can be analyzed.
    psnr_u: f32,
    psnr_v: f32,
    // v0.6a: perceptual metric (MS-SSIM, Wang 2003) on the Y plane, mean over
    // frames. The selection signal lives on the MS-SSIM dB scale now
    // (brain/config.json q_metric); psnr_y stays as the reporting + BD-rate
    // instrument so anchors stay comparable.
    msssim_y: f32,
    enc_ms: f32,
    enc_mops: f32, // (dct+idct calls)*64 / 1e6
    dec_mops: f32, // idct calls*64 / 1e6
};

// ---------------------------------------------------------------- DCT tables

var dct_tab: [64]f32 = undefined; // t[u*8 + x] = c(u)/2 * cos((2x+1)u*pi/16)
var dct16_tab: [256]f32 = undefined; // v0.8: t[u*16 + x] = c(u)/2 * cos((2x+1)u*pi/32)
var dct_ready = false;

fn initDct() void {
    if (dct_ready) return;
    const pi: f32 = 3.14159265358979;
    for (0..8) |u| {
        const cu: f32 = if (u == 0) @sqrt(0.5) else 1.0;
        for (0..8) |x| {
            const ang = pi * (2.0 * @as(f32, @floatFromInt(x)) + 1.0) * @as(f32, @floatFromInt(u)) / 16.0;
            dct_tab[u * 8 + x] = 0.5 * cu * @cos(ang);
        }
    }
    for (0..16) |u| {
        const cu: f32 = if (u == 0) @sqrt(0.5) else 1.0;
        for (0..16) |x| {
            const ang = pi * (2.0 * @as(f32, @floatFromInt(x)) + 1.0) * @as(f32, @floatFromInt(u)) / 32.0;
            dct16_tab[u * 16 + x] = 0.5 * cu * @cos(ang);
        }
    }
    dct_ready = true;
}

// zigzag order: ZZ[k] = raster index of k-th scanned coefficient
const ZZ = [64]u8{
    0,  1,  8,  16, 9,  2,  3,  10,
    17, 24, 32, 25, 18, 11, 4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13, 6,  7,  14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
};

fn zzBand(k: usize) usize {
    return if (k < 8) 0 else if (k < 16) 1 else 2;
}

// v0.8: 16x16 zigzag (same diagonal snake, scaled) + band map. Bands keep
// the legacy 8x8 proportions (12.5% / 12.5% / 75%) so the evolved bandScale
// genes transfer their meaning to the big transform.
const ZZ16: [256]u16 = blk: {
    @setEvalBranchQuota(10000);
    var t: [256]u16 = undefined;
    var k: usize = 0;
    var s: i32 = 0;
    while (s < 31) : (s += 1) {
        if (@mod(s, 2) == 0) {
            var r: i32 = if (s < 16) s else 15;
            var c: i32 = s - r;
            while (r >= 0 and c < 16) {
                t[k] = @intCast(r * 16 + c);
                k += 1;
                r -= 1;
                c += 1;
            }
        } else {
            var c: i32 = if (s < 16) s else 15;
            var r: i32 = s - c;
            while (c >= 0 and r < 16) {
                t[k] = @intCast(r * 16 + c);
                k += 1;
                c -= 1;
                r += 1;
            }
        }
    }
    break :blk t;
};

fn zzBand16(k: usize) usize {
    return if (k < 32) 0 else if (k < 64) 1 else 2;
}

// --------------------------------------------------------- bit writer/reader

const BW = struct {
    buf: []u8,
    n: usize = 0,
    bacc: u32 = 0, // bit accumulator (v0.4 mode codes)
    bn: u5 = 0,

    fn put(self: *BW, b: u8) void {
        self.flushBits(); // byte-level writes are always byte-aligned
        self.buf[self.n] = b;
        self.n += 1;
    }
    /// Append w (<= 8) bits of v. Byte flush happens lazily on the next
    /// byte-level put — mode codes pack contiguously.
    fn putBits(self: *BW, v: u8, w: u5) void {
        self.bacc = (self.bacc << w) | v;
        self.bn += w;
        while (self.bn >= 8) {
            self.bn -= 8;
            self.buf[self.n] = @intCast((self.bacc >> self.bn) & 0xFF);
            self.n += 1;
        }
    }
    fn flushBits(self: *BW) void {
        if (self.bn > 0) {
            const pad: u5 = 8 - self.bn;
            const b: u8 = @intCast((self.bacc << pad) & 0xFF);
            self.buf[self.n] = b;
            self.n += 1;
            self.bn = 0;
            self.bacc = 0;
        }
    }
    fn putUvarint(self: *BW, v0: u64) void {
        var v = v0;
        while (true) {
            const byte: u8 = @intCast(v & 0x7F);
            v >>= 7;
            if (v != 0) {
                self.put(byte | 0x80);
            } else {
                self.put(byte);
                break;
            }
        }
    }
    fn putSvarint(self: *BW, v: i64) void {
        const z: u64 = @bitCast((v << 1) ^ (v >> 63));
        self.putUvarint(z);
    }
    fn putU8(self: *BW, v: u8) void {
        self.put(v);
    }
};

const BR = struct {
    buf: []const u8,
    p: usize = 0,
    bacc: u32 = 0,
    bn: u5 = 0,

    /// Read w (<= 8) bits. Consumes whole bytes from the stream as needed;
    /// the remainder of the last partial byte stays in the accumulator.
    fn getBits(self: *BR, w: u5) !u8 {
        while (self.bn < w) {
            if (self.p >= self.buf.len) return error.Eof;
            self.bacc = (self.bacc << 8) | self.buf[self.p];
            self.p += 1;
            self.bn += 8;
        }
        const shift: u5 = self.bn - w;
        const mask: u32 = (@as(u32, 1) << w) - 1;
        const v: u8 = @intCast((self.bacc >> shift) & mask);
        self.bn = shift;
        return v;
    }
    /// Byte-level reads are byte-aligned: drop any partial byte (it is the
    /// encoder's zero padding, skipped symmetrically).
    inline fn syncByte(self: *BR) void {
        self.bn = 0;
    }
    fn getUvarint(self: *BR) !u64 {
        self.syncByte();
        var shift: u6 = 0;
        var v: u64 = 0;
        while (true) {
            if (self.p >= self.buf.len) return error.Eof;
            const b = self.buf[self.p];
            self.p += 1;
            v |= @as(u64, b & 0x7F) << shift;
            if (b & 0x80 == 0) break;
            shift += 7;
            if (shift > 56) return error.Corrupt;
        }
        return v;
    }
    fn getSvarint(self: *BR) !i64 {
        self.syncByte();
        const z = try self.getUvarint();
        const v: i64 = @bitCast(z >> 1);
        return if (z & 1 != 0) ~v + 1 else v;
    }
    fn getU8(self: *BR) !u8 {
        self.syncByte();
        if (self.p >= self.buf.len) return error.Eof;
        const b = self.buf[self.p];
        self.p += 1;
        return b;
    }
};

// --------------------------------------------------- adaptive entropy coder
// v0.5 — learned from the AV1 lineup (daala EC / CABAC / LZMA rc): when the
// entropy gene is on, the per-plane block stream (markers, motion vectors,
// (run,level) pairs) is coded with a binary adaptive arithmetic coder instead
// of byte varints. One adaptive 11-bit probability per decision context
// (LZMA update rule: p += (target - p) >> 5); the engine is the carry-
// propagating range coder both sides mirror exactly. The mode map keeps its
// bit-packed form (already narrow). Gene 0 = byte-exact legacy stream.

const PROB_BITS: u5 = 11;
const PROB_ONE: u16 = 1 << PROB_BITS; // 2048 == P(bit=0) == 1
const PROB_INIT: u16 = PROB_ONE / 2;
const RC_TOP: u32 = 1 << 24;

/// Adaptive probability states, reset per plane on both sides.
const Probs = [64]u16;

inline fn pUpdate(p: *u16, bit: u1) void {
    // LZMA rule, truncated: p moves 1/32 of the way toward the target bit.
    // @divTrunc (NOT an arithmetic shift of the negative delta) never
    // overshoots, and the clamps guarantee 1 <= p <= 2047 so the coded
    // subinterval can never vanish — a zero probability would zero the
    // range and spin the renormalization loop forever.
    const target: i32 = if (bit == 0) PROB_ONE else 0;
    const d: i32 = @divTrunc(target - @as(i32, p.*), 1 << PROB_MOVE);
    var np: i32 = @as(i32, p.*) + d;
    if (np < 1) np = 1;
    if (np > PROB_ONE - 1) np = PROB_ONE - 1;
    p.* = @intCast(np);
}
const PROB_MOVE: u5 = 5;

// decision-context layout (both sides share the constants)
const CX_MARK_A: usize = 0; // block marker: skip?
const CX_MARK_B: usize = 1; // block marker: intra (vs inter)?
const CX_MV_SIGN: usize = 2;
const CX_MV_U0: usize = 3; // MV magnitude unary (>0,>1,>2)
const CX_MV_B0: usize = 6; // MV magnitude raw 4 bits (mag-3)
const CX_SP_B0: usize = 10; // subpel code: 4 bits legacy half | 5 bits v0.5b quarter
const CX_NP_U0: usize = 14; // npairs unary (>0..>3)
const CX_NP_B0: usize = 18; // npairs raw 6 bits (np-4)
const CX_RN_U0: usize = 22; // run unary (>0..>3)
const CX_RN_B0: usize = 26; // run raw 6 bits (run-4)
const CX_LV_U0: usize = 30; // level abs-1 unary (>0,>1,>2)
const CX_LV_ESC: usize = 33; // level big-escape flag
const CX_LV_B0: usize = 34; // level raw bits (12, +16 on escape)
const CX_LV_SIGN: usize = 46;
const CX_MARK_C: usize = 62; // v0.8 sb16 wide-marker third bit (gene-gated)

const ACEnc = struct {
    buf: []u8,
    n: usize = 0,
    low: u64 = 0,
    range: u32 = 0xFFFF_FFFF,
    cache: u8 = 0,
    cache_size: u32 = 1,

    /// LZMA-style delayed-carry byte flush.
    fn shiftLow(self: *ACEnc) void {
        const carry: u8 = @truncate(self.low >> 32);
        if (self.low < 0xFF00_0000 or carry != 0) {
            var temp = self.cache;
            while (true) {
                if (self.n >= self.buf.len) return; // guarded by buffer sizing
                self.buf[self.n] = temp +% carry;
                self.n += 1;
                temp = 0xFF;
                self.cache_size -= 1;
                if (self.cache_size == 0) break;
            }
            self.cache = @truncate(self.low >> 24);
        }
        self.cache_size += 1;
        self.low = (self.low << 8) & 0xFFFF_FFFF;
    }

    fn encodeBit(self: *ACEnc, ps: *Probs, ci: usize, bit: u1) void {
        const p = &ps[ci];
        const bound: u32 = (self.range >> PROB_BITS) * @as(u32, p.*);
        if (bit == 0) {
            self.range = bound;
        } else {
            self.low += bound;
            self.range -= bound;
        }
        while (self.range < RC_TOP) {
            self.range <<= 8;
            self.shiftLow();
        }
        pUpdate(p, bit);
    }

    fn flush(self: *ACEnc) void {
        for (0..5) |_| self.shiftLow();
    }
};

const ACDec = struct {
    br: *BR,
    range: u32 = 0xFFFF_FFFF,
    code: u32 = 0,

    fn init(self: *ACDec) !void {
        _ = try self.br.getU8(); // encoder's initial cache byte — skipped
        for (0..4) |_| {
            self.code = (self.code << 8) | try self.br.getU8();
        }
    }

    fn decodeBit(self: *ACDec, ps: *Probs, ci: usize) !u1 {
        const p = &ps[ci];
        const bound: u32 = (self.range >> PROB_BITS) * @as(u32, p.*);
        var bit: u1 = 0;
        if (self.code < bound) {
            self.range = bound;
        } else {
            self.code -= bound;
            self.range -= bound;
            bit = 1;
        }
        while (self.range < RC_TOP) {
            self.range <<= 8;
            self.code = (self.code << 8) | try self.br.getU8();
        }
        pUpdate(p, bit);
        return bit;
    }
};

/// Raw big-endian bit tuple through the arithmetic coder (MSB first).
fn encUBits(ac: *ACEnc, ps: *Probs, base: usize, nb: u5, v: u32) void {
    var i: u5 = nb;
    while (i > 0) {
        i -= 1;
        ac.encodeBit(ps, base + (nb - 1 - i), @truncate((v >> i) & 1));
    }
}
fn decUBits(ac: *ACDec, ps: *Probs, base: usize, nb: u5) !u32 {
    var v: u32 = 0;
    for (0..nb) |k| {
        const b = try ac.decodeBit(ps, base + k);
        v = (v << 1) | b;
    }
    return v;
}
/// Truncated unary: `v` ones (capped at n_units) then a zero — unless v
/// equals n_units, where the terminator is omitted; the decoder counts the
/// same way, so both sides consume identical decisions.
fn encUnary(ac: *ACEnc, ps: *Probs, base: usize, v: u32, n_units: usize) void {
    var k: u32 = 0;
    while (k < n_units) : (k += 1) {
        const one: u1 = @intFromBool(v > k);
        ac.encodeBit(ps, base + k, one);
        if (one == 0) break;
    }
}
fn decUnary(ac: *ACDec, ps: *Probs, base: usize, n_units: usize) !u32 {
    var v: u32 = 0;
    while (v < n_units) {
        if (try ac.decodeBit(ps, base + v) == 0) break;
        v += 1;
    }
    return v;
}

fn encMarker(ac: *ACEnc, ps: *Probs, m: u8) void {
    if (m == 1) { // skip
        ac.encodeBit(ps, CX_MARK_A, 1);
        return;
    }
    ac.encodeBit(ps, CX_MARK_A, 0);
    ac.encodeBit(ps, CX_MARK_B, if (m == 2) 1 else 0);
}
fn decMarker(ac: *ACDec, ps: *Probs) !u8 {
    if (try ac.decodeBit(ps, CX_MARK_A) == 1) return 1;
    return if (try ac.decodeBit(ps, CX_MARK_B) == 1) 2 else 0;
}
// v0.8 wide markers: when the sb16 gene is on, a non-skip marker carries one
// extra context bit — 1 = superblock-unified follows (value 3), 0 = the
// legacy {0,2} fork. Gene off => the tree is bit-exact legacy (the extra bit
// is never read nor adapted), so pre-v0.8 genomes decode byte-for-byte.
fn encMarkerWide(ac: *ACEnc, ps: *Probs, m: u8) void {
    if (m == 1) {
        ac.encodeBit(ps, CX_MARK_A, 1);
        return;
    }
    ac.encodeBit(ps, CX_MARK_A, 0);
    ac.encodeBit(ps, CX_MARK_B, if (m == 2) 1 else 0);
    ac.encodeBit(ps, CX_MARK_C, if (m == 3) 1 else 0);
}
fn decMarkerWide(ac: *ACDec, ps: *Probs) !u8 {
    if (try ac.decodeBit(ps, CX_MARK_A) == 1) return 1;
    const b = try ac.decodeBit(ps, CX_MARK_B);
    if (try ac.decodeBit(ps, CX_MARK_C) == 1) return 3;
    return if (b == 1) 2 else 0;
}

fn encMV(ac: *ACEnc, ps: *Probs, d: i32) void {
    ac.encodeBit(ps, CX_MV_SIGN, if (d < 0) 1 else 0);
    const mag: u32 = @intCast(@abs(d));
    encUnary(ac, ps, CX_MV_U0, mag, 3);
    if (mag > 2) encUBits(ac, ps, CX_MV_B0, 4, mag - 3);
}
fn decMV(ac: *ACDec, ps: *Probs) !i32 {
    const s = try ac.decodeBit(ps, CX_MV_SIGN);
    var mag = try decUnary(ac, ps, CX_MV_U0, 3);
    if (mag > 2) mag = 3 + try decUBits(ac, ps, CX_MV_B0, 4);
    return if (s == 1) -@as(i32, @intCast(mag)) else @as(i32, @intCast(mag));
}

fn acEncLevel(ac: *ACEnc, ps: *Probs, l: i32) void {
    ac.encodeBit(ps, CX_LV_SIGN, if (l < 0) 1 else 0);
    const v: u32 = @as(u32, @intCast(@abs(l))) - 1;
    encUnary(ac, ps, CX_LV_U0, v, 3);
    if (v > 2) {
        const w: u32 = v - 3;
        if (w >= 4095) {
            ac.encodeBit(ps, CX_LV_ESC, 1);
            encUBits(ac, ps, CX_LV_B0, 12, 4095);
            encUBits(ac, ps, CX_LV_B0, 16, w - 4095);
        } else {
            ac.encodeBit(ps, CX_LV_ESC, 0);
            encUBits(ac, ps, CX_LV_B0, 12, w);
        }
    }
}
fn acDecLevel(ac: *ACDec, ps: *Probs) !i32 {
    const s = try ac.decodeBit(ps, CX_LV_SIGN);
    var v = try decUnary(ac, ps, CX_LV_U0, 3);
    if (v > 2) {
        const esc = try ac.decodeBit(ps, CX_LV_ESC);
        var w = try decUBits(ac, ps, CX_LV_B0, 12);
        if (esc == 1) w = 4095 + try decUBits(ac, ps, CX_LV_B0, 16);
        v = 3 + w;
    }
    const m: i32 = @intCast(v + 1);
    return if (s == 1) -m else m;
}

/// AC-coded (run, level) payload — the adaptive twin of packPairs.
fn acEncLevels(ac: *ACEnc, ps: *Probs, lv: []const i32, last: usize) void {
    var npairs: u32 = 0;
    for (lv[0 .. last + 1]) |l| {
        if (l != 0) npairs += 1;
    }
    encUnary(ac, ps, CX_NP_U0, npairs, 4);
    if (npairs > 3) encUBits(ac, ps, CX_NP_B0, 6, npairs - 4);
    var run: u32 = 0;
    for (0..last + 1) |k| {
        if (lv[k] == 0) {
            run += 1;
        } else {
            encUnary(ac, ps, CX_RN_U0, run, 4);
            if (run > 3) encUBits(ac, ps, CX_RN_B0, 6, run - 4);
            acEncLevel(ac, ps, lv[k]);
            run = 0;
        }
    }
}
fn acDecLevels(ac: *ACDec, ps: *Probs, g: *const gen.Genome, qp: f32, scale: f32, rc: gen.RegCtx, coef: *[64]f32) !void {
    for (coef) |*c| c.* = 0;
    var npairs = try decUnary(ac, ps, CX_NP_U0, 4);
    if (npairs > 3) npairs = 4 + try decUBits(ac, ps, CX_NP_B0, 6);
    var k: u32 = 0;
    var i: u32 = 0;
    while (i < npairs) : (i += 1) {
        var run = try decUnary(ac, ps, CX_RN_U0, 4);
        if (run > 3) run = 4 + try decUBits(ac, ps, CX_RN_B0, 6);
        k += run;
        if (k >= 64) return error.Corrupt;
        const lvl = try acDecLevel(ac, ps);
        coef[ZZ[@intCast(k)]] = @as(f32, @floatFromInt(lvl)) * levelQ(g, qp, scale, @intCast(k), rc);
        k += 1;
    }
}

/// v0.8: big-TX twin of acDecLevels (256 coefs, ZZ16 scan, levelQ16 dequant).
fn acDecLevels16(ac: *ACDec, ps: *Probs, g: *const gen.Genome, qp: f32, scale: f32, rc: gen.RegCtx, coef: *[256]f32) !void {
    for (coef) |*c| c.* = 0;
    var npairs = try decUnary(ac, ps, CX_NP_U0, 4);
    if (npairs > 3) npairs = 4 + try decUBits(ac, ps, CX_NP_B0, 6);
    var k: u32 = 0;
    var i: u32 = 0;
    while (i < npairs) : (i += 1) {
        var run = try decUnary(ac, ps, CX_RN_U0, 4);
        if (run > 3) run = 4 + try decUBits(ac, ps, CX_RN_B0, 6);
        k += run;
        if (k >= 256) return error.Corrupt;
        const lvl = try acDecLevel(ac, ps);
        coef[ZZ16[@intCast(k)]] = @as(f32, @floatFromInt(lvl)) * levelQ16(g, qp, scale, @intCast(k), rc);
        k += 1;
    }
}

/// Comptime-specialized block-stream writer: one source, two bitstreams.
/// Legacy=false is the byte-varint path (byte-exact v0.4); Legacy=true is
/// the adaptive arithmetic coder (v0.5 entropy gene).
fn BlockW(comptime ac_on: bool) type {
    return struct {
        bw: BW = undefined,
        ac: ACEnc = undefined,
        ps: Probs = undefined,

        fn init(buf: []u8) @This() {
            if (ac_on) return .{ .ac = .{ .buf = buf }, .ps = @splat(PROB_INIT) };
            return .{ .bw = .{ .buf = buf } };
        }
        fn marker(self: *@This(), m: u8) void {
            if (ac_on) encMarker(&self.ac, &self.ps, m) else self.bw.putU8(m);
        }
        fn mv(self: *@This(), dx: i32, dy: i32) void {
            if (ac_on) {
                encMV(&self.ac, &self.ps, dx);
                encMV(&self.ac, &self.ps, dy);
            } else {
                self.bw.putSvarint(dx);
                self.bw.putSvarint(dy);
            }
        }
        fn subpel(self: *@This(), code: u8, bits: u4) void {
            // v0.5b: 4 bits legacy (half-pel 3x3) | 5 bits qpel (5x5 lattice)
            if (ac_on) encUBits(&self.ac, &self.ps, CX_SP_B0, bits, code) else self.bw.putU8(code);
        }
        fn levels(self: *@This(), lv: []const i32, last: usize) void {
            if (ac_on) acEncLevels(&self.ac, &self.ps, lv, last) else packPairs(&self.bw, lv, last);
        }
        /// v0.8 sb16 wide marker (values 0..3; third bit only when wide).
        fn markerSB(self: *@This(), m: u8, wide: bool) void {
            if (ac_on) {
                if (wide) encMarkerWide(&self.ac, &self.ps, m) else encMarker(&self.ac, &self.ps, m);
            } else {
                self.bw.putU8(m);
            }
        }
        /// v0.8: big-TX levels — same pair coding, 256 zigzag slots.
        fn levels16(self: *@This(), lv: []const i32, last: usize) void {
            if (ac_on) acEncLevels(&self.ac, &self.ps, lv, last) else packPairs(&self.bw, lv, last);
        }
        fn written(self: *@This()) usize {
            return if (ac_on) self.ac.n else self.bw.n;
        }
        fn finish(self: *@This()) void {
            if (ac_on) self.ac.flush();
        }
    };
}
fn BlockR(comptime ac_on: bool) type {
    return struct {
        br: *BR,
        ac: ACDec = undefined,
        ps: Probs = undefined,

        fn init(br: *BR) !@This() {
            if (ac_on) {
                var r = @This(){ .br = br, .ac = .{ .br = br } };
                try r.ac.init();
                r.ps = @splat(PROB_INIT);
                return r;
            }
            return .{ .br = br };
        }
        fn marker(self: *@This()) !u8 {
            if (ac_on) return decMarker(&self.ac, &self.ps);
            return try self.br.getU8();
        }
        /// v0.8 sb16 wide marker read (third bit only when wide).
        fn markerSB(self: *@This(), wide: bool) !u8 {
            if (ac_on) {
                if (wide) return decMarkerWide(&self.ac, &self.ps);
                return decMarker(&self.ac, &self.ps);
            }
            return try self.br.getU8();
        }
        fn mvPair(self: *@This()) ![2]i32 {
            if (ac_on) return .{ try decMV(&self.ac, &self.ps), try decMV(&self.ac, &self.ps) };
            const dx = try self.br.getSvarint();
            const dy = try self.br.getSvarint();
            const cdx = std.math.cast(i32, dx) orelse return error.Corrupt;
            const cdy = std.math.cast(i32, dy) orelse return error.Corrupt;
            return .{ cdx, cdy };
        }
        fn subpel(self: *@This(), bits: u4) !u8 {
            if (ac_on) return @intCast(try decUBits(&self.ac, &self.ps, CX_SP_B0, bits));
            return try self.br.getU8();
        }
        /// Legacy twin: read (npairs, pairs) and fill the dequantized coef array.
        fn levels(self: *@This(), g: *const gen.Genome, qp: f32, scale: f32, rc: gen.RegCtx, coef: *[64]f32) !void {
            if (ac_on) {
                try acDecLevels(&self.ac, &self.ps, g, qp, scale, rc, coef);
                return;
            }
            for (coef) |*c| c.* = 0;
            const npairs = try self.br.getUvarint();
            var k: u64 = 0;
            var i: u64 = 0;
            while (i < npairs) : (i += 1) {
                const run = try self.br.getUvarint();
                const lvl = try self.br.getSvarint();
                k += run;
                if (k >= 64) return error.Corrupt;
                const lf: f32 = @floatFromInt(lvl);
                coef[ZZ[@intCast(k)]] = lf * levelQ(g, qp, scale, @intCast(k), rc);
                k += 1;
            }
        }
        /// v0.8: big-TX levels read (256 zigzag slots, ZZ16 + levelQ16).
        fn levels16(self: *@This(), g: *const gen.Genome, qp: f32, scale: f32, rc: gen.RegCtx, coef: *[256]f32) !void {
            if (ac_on) {
                try acDecLevels16(&self.ac, &self.ps, g, qp, scale, rc, coef);
                return;
            }
            for (coef) |*c| c.* = 0;
            const npairs = try self.br.getUvarint();
            var k: u64 = 0;
            var i: u64 = 0;
            while (i < npairs) : (i += 1) {
                const run = try self.br.getUvarint();
                const lvl = try self.br.getSvarint();
                k += run;
                if (k >= 256) return error.Corrupt;
                const lf: f32 = @floatFromInt(lvl);
                coef[ZZ16[@intCast(k)]] = lf * levelQ16(g, qp, scale, @intCast(k), rc);
                k += 1;
            }
        }
    };
}

// ------------------------------------------------------------ block coding

fn dct8(src: []const u8, out: *[64]f32) void {
    var tmp: [64]f32 = undefined;
    for (0..8) |r| {
        for (0..8) |u| {
            var s: f32 = 0;
            for (0..8) |x| {
                const px: f32 = @as(f32, @floatFromInt(src[r * 8 + x])) - 128.0;
                s += px * dct_tab[u * 8 + x];
            }
            tmp[r * 8 + u] = s;
        }
    }
    for (0..8) |u| {
        for (0..8) |v| {
            var s: f32 = 0;
            for (0..8) |r| s += tmp[r * 8 + u] * dct_tab[v * 8 + r];
            out[v * 8 + u] = s;
        }
    }
}

fn idct8(coef: *const [64]f32, dst: []u8, stride: usize, idct_calls: *u64) void {
    var tmp: [64]f32 = undefined;
    for (0..8) |v| {
        for (0..8) |x| {
            var s: f32 = 0;
            for (0..8) |u| s += coef[v * 8 + u] * dct_tab[u * 8 + x];
            tmp[x * 8 + v] = s;
        }
    }
    for (0..8) |r| {
        for (0..8) |c| {
            var s: f32 = 0;
            for (0..8) |v| s += tmp[r * 8 + v] * dct_tab[v * 8 + c];
            const px: i32 = @intFromFloat(@round(s + 128.0));
            dst[r * stride + c] = @intCast(std.math.clamp(px, 0, 255));
        }
    }
    idct_calls.* += 1;
}

// ---- v0.8: 16x16 transform (the superblock's big TX; direct separable
// matrix product, same orthonormal DCT-II convention as dct8) ----
fn dct16(src: []const u8, out: *[256]f32) void {
    var tmp: [256]f32 = undefined;
    for (0..16) |r| {
        for (0..16) |u| {
            var s: f32 = 0;
            for (0..16) |x| {
                const px: f32 = @as(f32, @floatFromInt(src[r * 16 + x])) - 128.0;
                s += px * dct16_tab[u * 16 + x];
            }
            tmp[r * 16 + u] = s;
        }
    }
    for (0..16) |u| {
        for (0..16) |v| {
            var s: f32 = 0;
            for (0..16) |r| s += tmp[r * 16 + u] * dct16_tab[v * 16 + r];
            out[v * 16 + u] = s;
        }
    }
}
fn idct16(coef: *const [256]f32, dst: []u8, stride: usize, idct_calls: *u64) void {
    var tmp: [256]f32 = undefined;
    for (0..16) |v| {
        for (0..16) |x| {
            var s: f32 = 0;
            for (0..16) |u| s += coef[v * 16 + u] * dct16_tab[u * 16 + x];
            tmp[x * 16 + v] = s;
        }
    }
    for (0..16) |r| {
        for (0..16) |c| {
            var s: f32 = 0;
            for (0..16) |v| s += tmp[r * 16 + v] * dct16_tab[v * 16 + c];
            const px: i32 = @intFromFloat(@round(s + 128.0));
            dst[r * stride + c] = @intCast(std.math.clamp(px, 0, 255));
        }
    }
    idct_calls.* += 1;
}

// v0.6a: uniform quantizer override for RD probing (--qscale). Applied in
// bandQ — THE single funnel every quant step passes through on BOTH encoder
// and decoder — so the two sides can never disagree by construction. 1.0 =
// off, bit-identical behavior. This is the honest operating-point knob the
// RD sweep should use: sweeping a single co-adapted gene (baseq) desyncs the
// quantizer stack and produces non-monotonic junk curves (seen on champion
// 170007151: 27.7 dB @ 0.225 bpp vs 31.7 dB @ 0.181 bpp).
pub var qscale_override: f32 = 1.0;

fn bandQ(qp: f32, scale: f32) f32 {
    return @max(1.0, qp * scale * qscale_override);
}

fn quantLevel(c: f32, q: f32, dz: f32, dith: f32) i32 {
    const a = @abs(c) + dith;
    const lvl = @round(@max(0.0, (a - dz * 0.5) / q));
    const li: i32 = @intFromFloat(lvl);
    return if (c < 0) -li else li;
}

/// Shared per-level quantization step. THE single source of truth for how
/// band scales, regulatory modulation, and intra low-frequency shaping
/// combine. Used by the encoder quantizer, the encoder reconstructor, and
/// both decoder paths — regulation can never desynchronize (canalization
/// by code structure).
fn levelQ(g: *const gen.Genome, qp: f32, base_scale: f32, k: usize, rc: gen.RegCtx) f32 {
    const bs = gen.bandScale(g, zzBand(k));
    var s = base_scale * gen.regQMod(g, rc) * bs;
    if (rc.intra and zzBand(k) == 0) s *= gen.intraB0Mul(g);
    return bandQ(qp, s);
}

/// v0.8: levelQ twin for the 16x16 transform — same gene funnel, band map
/// from zzBand16. Both sides call this, so big-TX dequant never desyncs.
fn levelQ16(g: *const gen.Genome, qp: f32, base_scale: f32, k: usize, rc: gen.RegCtx) f32 {
    const bs = gen.bandScale(g, zzBand16(k));
    var s = base_scale * gen.regQMod(g, rc) * bs;
    if (rc.intra and zzBand16(k) == 0) s *= gen.intraB0Mul(g);
    return bandQ(qp, s);
}

/// Bilinear half-pel prediction block, shared by encoder search/recon and
/// decoder reconstruction. Samples the reference at half-pel position
/// (ox + hx/2, oy + hy/2), hx/hy in {-1,0,1}. Edge-clamped; identical on
/// both sides by construction.
fn interpBlock(prev: []const u8, pw: usize, ph: usize, ox: i32, oy: i32, hx: i32, hy: i32, out: *[64]u8) void {
    const w: i32 = @intCast(pw);
    const h: i32 = @intCast(ph);
    for (0..8) |r| {
        for (0..8) |c| {
            const xn = 2 * (ox + @as(i32, @intCast(c))) + hx;
            const yn = 2 * (oy + @as(i32, @intCast(r))) + hy;
            const xi = @divFloor(xn, 2);
            const xf = xn - 2 * xi; // 0 or 1
            const yi = @divFloor(yn, 2);
            const yf = yn - 2 * yi; // 0 or 1
            const x0 = @max(0, @min(w - 1, xi));
            const x1 = @max(0, @min(w - 1, xi + xf));
            const y0 = @max(0, @min(h - 1, yi));
            const y1 = @max(0, @min(h - 1, yi + yf));
            const a: i32 = prev[@as(usize, @intCast(y0)) * pw + @as(usize, @intCast(x0))];
            const b: i32 = prev[@as(usize, @intCast(y0)) * pw + @as(usize, @intCast(x1))];
            const c2: i32 = prev[@as(usize, @intCast(y1)) * pw + @as(usize, @intCast(x0))];
            const d: i32 = prev[@as(usize, @intCast(y1)) * pw + @as(usize, @intCast(x1))];
            const v = @divTrunc(a * (2 - xf) * (2 - yf) + b * xf * (2 - yf) +
                c2 * (2 - xf) * yf + d * xf * yf + 2, 4);
            out[r * 8 + c] = @intCast(v);
        }
    }
}

// --------------------------------------------------- quarter-pel MC (v0.5b)
// Learned from the AV1 lineup (switchable interpolation filters; the 4-tap
// Wiener regular filter) structured like H.264's MC: Wiener-filtered halves,
// bilinear quarters. The 5x5 quarter lattice around an integer MV:
//   half positions  (qx,qy in {-2,0,2}): 4-tap Wiener (-1,9,9,-1)>>4,
//     diagonal halves = vertical 4-tap of the horizontal half plane
//     (canonical order, like H.264's j from b).
//   quarter positions (any |qx| or |qy| == 1): rounded bilinear average of
//     the bracketing integer/half samples on the finer grid:
//     1D quarters = avg(int, half); diagonal quarters =
//     avg(int, halfH, halfV, halfD) (2D bilinear of the four corners).
// Edge-clamped throughout; shared by encoder search/recon and decoder
// reconstruction — identical on both sides by construction.
// Gene-gated (g[21]): off = byte-exact v0.5 (bilinear half-pel only).

/// 4-tap Wiener half sample between pos and pos+1 along one axis.
/// taps (-1, 9, 9, -1), rounded >>4, CLAMPED to [0,255] (x264-style: the
/// clamp is part of the one canonical definition shared by the direct path
/// and the cached half-planes, so both are bit-identical).
inline fn halfT4(p0: i32, p1: i32, p2: i32, p3: i32) i32 {
    return @max(0, @min(255, @divTrunc(-p0 + 9 * p1 + 9 * p2 - p3 + 8, 16)));
}

fn atClamp(prev: []const u8, pw: usize, ph: usize, x: i32, y: i32) i32 {
    const xi = @max(0, @min(@as(i32, @intCast(pw)) - 1, x));
    const yi = @max(0, @min(@as(i32, @intCast(ph)) - 1, y));
    return @as(i32, prev[@as(usize, @intCast(yi)) * pw + @as(usize, @intCast(xi))]);
}

fn clamp255(v: i32) u8 {
    return @intCast(@max(0, @min(255, v)));
}

/// Horizontal half sample at (x + 1/2, y).
inline fn halfH(prev: []const u8, pw: usize, ph: usize, x: i32, y: i32) i32 {
    return halfT4(atClamp(prev, pw, ph, x - 1, y), atClamp(prev, pw, ph, x, y), atClamp(prev, pw, ph, x + 1, y), atClamp(prev, pw, ph, x + 2, y));
}
/// Vertical half sample at (x, y + 1/2).
inline fn halfV(prev: []const u8, pw: usize, ph: usize, x: i32, y: i32) i32 {
    return halfT4(atClamp(prev, pw, ph, x, y - 1), atClamp(prev, pw, ph, x, y), atClamp(prev, pw, ph, x, y + 1), atClamp(prev, pw, ph, x, y + 2));
}
/// Diagonal half sample at (x + 1/2, y + 1/2): vertical 4-tap of the
/// horizontal half plane (canonical order, identical enc/dec).
inline fn halfD(prev: []const u8, pw: usize, ph: usize, x: i32, y: i32) i32 {
    return halfT4(halfH(prev, pw, ph, x, y - 1), halfH(prev, pw, ph, x, y), halfH(prev, pw, ph, x, y + 1), halfH(prev, pw, ph, x, y + 2));
}

/// Quarter-pel prediction block: samples the reference at
/// (ox + qx/4, oy + qy/4), qx/qy in {-2,-1,0,1,2}. DIRECT path — recomputes
/// the 4-tap filters per pixel. Used as the reference definition; the
/// production path is mcBlockQ on prebuilt half-planes (same values by
/// construction, and the cross-check test asserts that).
fn interpBlockQ(prev: []const u8, pw: usize, ph: usize, ox: i32, oy: i32, qx: i32, qy: i32, out: *[64]u8) void {
    for (0..8) |r| {
        for (0..8) |c| {
            const x: i32 = ox + @as(i32, @intCast(c));
            const y: i32 = oy + @as(i32, @intCast(r));
            // absolute quarter offsets from the integer grid point (x,y)
            const ax = qx; // in {-2..2}
            const ay = qy;
            var v: i32 = undefined;
            if (ax == 0 and ay == 0) {
                v = atClamp(prev, pw, ph, x, y);
            } else if (ay == 0 and @abs(ax) == 2) {
                // horizontal half: sample at x + ax/4 (divFloor: -2 -> -1)
                v = halfH(prev, pw, ph, x + @divFloor(ax, 4), y);
            } else if (ax == 0 and @abs(ay) == 2) {
                v = halfV(prev, pw, ph, x, y + @divFloor(ay, 4));
            } else if (@abs(ax) == 2 and @abs(ay) == 2) {
                v = halfD(prev, pw, ph, x + @divFloor(ax, 4), y + @divFloor(ay, 4));
            } else if (ay == 0) {
                // 1D horizontal quarter: avg(int, neighboring half)
                if (ax == -1) {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + halfH(prev, pw, ph, x - 1, y) + 1, 2);
                } else {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + halfH(prev, pw, ph, x, y) + 1, 2);
                }
            } else if (ax == 0) {
                if (ay == -1) {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + halfV(prev, pw, ph, x, y - 1) + 1, 2);
                } else {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + halfV(prev, pw, ph, x, y) + 1, 2);
                }
            } else {
                // diagonal quarter: 2D bilinear of the four grid corners
                // (int, halfH, halfV, halfD) around the quarter point.
                const sx = if (ax < 0) @as(i32, -1) else @as(i32, 0);
                const sy = if (ay < 0) @as(i32, -1) else @as(i32, 0);
                const ic = atClamp(prev, pw, ph, x, y);
                const hh = halfH(prev, pw, ph, x + sx, y);
                const vv = halfV(prev, pw, ph, x, y + sy);
                const dd = halfD(prev, pw, ph, x + sx, y + sy);
                v = @divTrunc(ic + hh + vv + dd + 2, 4);
            }
            out[r * 8 + c] = clamp255(v);
        }
    }
}

// --- v0.5b production path: prebuilt half-planes (the libaom/SVT-AV1
// "interpolated reference buffer" pattern). Building the three half planes
// once per reference plane turns per-block sub-pel refinement into plain
// reads — the difference between +267% and a few dozen percent encode cost.

/// Build the three half-pel planes for one reference plane. hH/hV/hD are
/// pw*ph u8 buffers. halfD is the vertical 4-tap of the hH plane (canonical
/// order, H.264's j-from-b structure). Edge-clamped at build time; all
/// production reads go through these planes (encoder AND decoder), so the
/// closed loop cannot desync.
fn buildHalfPlanes(prev: []const u8, pw: usize, ph: usize, hH: []u8, hV: []u8, hD: []u8) void {
    for (0..ph) |y| {
        for (0..pw) |x| {
            hH[y * pw + x] = @intCast(halfH(prev, pw, ph, @intCast(x), @intCast(y)));
        }
    }
    for (0..ph) |y| {
        for (0..pw) |x| {
            hV[y * pw + x] = @intCast(halfV(prev, pw, ph, @intCast(x), @intCast(y)));
        }
    }
    for (0..ph) |y| {
        for (0..pw) |x| {
            const ym: usize = if (y == 0) 0 else y - 1;
            const yp: usize = @min(ph - 1, y + 1);
            const y2: usize = @min(ph - 1, y + 2);
            hD[y * pw + x] = @intCast(halfT4(
                @as(i32, hH[ym * pw + x]),
                @as(i32, hH[y * pw + x]),
                @as(i32, hH[yp * pw + x]),
                @as(i32, hH[y2 * pw + x]),
            ));
        }
    }
}

/// Clamp helper for plane reads (plane boundaries already clamp at build
/// time; reads only clamp index range).
inline fn atPlane(p: []const u8, pw: usize, ph: usize, x: i32, y: i32) i32 {
    const xi = @max(0, @min(@as(i32, @intCast(pw)) - 1, x));
    const yi = @max(0, @min(@as(i32, @intCast(ph)) - 1, y));
    return @as(i32, p[@as(usize, @intCast(yi)) * pw + @as(usize, @intCast(xi))]);
}

/// Quarter-pel prediction from prebuilt half-planes. Same semantics as
/// interpBlockQ, byte-identical values (both clamp halves identically).
fn mcBlockQ(prev: []const u8, hH: []const u8, hV: []const u8, hD: []const u8, pw: usize, ph: usize, ox: i32, oy: i32, qx: i32, qy: i32, out: *[64]u8) void {
    for (0..8) |r| {
        for (0..8) |c| {
            const x: i32 = ox + @as(i32, @intCast(c));
            const y: i32 = oy + @as(i32, @intCast(r));
            const ax = qx;
            const ay = qy;
            var v: i32 = undefined;
            if (ax == 0 and ay == 0) {
                v = atClamp(prev, pw, ph, x, y);
            } else if (ay == 0 and @abs(ax) == 2) {
                v = atPlane(hH, pw, ph, x + @divFloor(ax, 4), y);
            } else if (ax == 0 and @abs(ay) == 2) {
                v = atPlane(hV, pw, ph, x, y + @divFloor(ay, 4));
            } else if (@abs(ax) == 2 and @abs(ay) == 2) {
                v = atPlane(hD, pw, ph, x + @divFloor(ax, 4), y + @divFloor(ay, 4));
            } else if (ay == 0) {
                if (ax == -1) {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + atPlane(hH, pw, ph, x - 1, y) + 1, 2);
                } else {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + atPlane(hH, pw, ph, x, y) + 1, 2);
                }
            } else if (ax == 0) {
                if (ay == -1) {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + atPlane(hV, pw, ph, x, y - 1) + 1, 2);
                } else {
                    v = @divTrunc(atClamp(prev, pw, ph, x, y) + atPlane(hV, pw, ph, x, y) + 1, 2);
                }
            } else {
                const sx = if (ax < 0) @as(i32, -1) else @as(i32, 0);
                const sy = if (ay < 0) @as(i32, -1) else @as(i32, 0);
                const ic = atClamp(prev, pw, ph, x, y);
                const hh = atPlane(hH, pw, ph, x + sx, y);
                const vv = atPlane(hV, pw, ph, x, y + sy);
                const dd = atPlane(hD, pw, ph, x + sx, y + sy);
                v = @divTrunc(ic + hh + vv + dd + 2, 4);
            }
            out[r * 8 + c] = clamp255(v);
        }
    }
}

// ----------------------------------------------------- intra prediction (v0.4)
// Learned from the best of the best: H.264/x264 spatial intra prediction.
// Every mode derives ONLY from already-reconstructed neighbor pixels in the
// raster-ordered recon plane — identical on encoder and decoder by
// construction (canalization by code structure). Gene-gated: g[16] < 0.25 is
// byte-exact legacy (no prediction, no mode byte), so pre-v0.4 genomes keep
// their oracle metrics and the Hall of Fame floor stays comparable.

pub const INTRA_NONE: u8 = 0; // legacy raw-DCT intra
pub const INTRA_DC: u8 = 1;
pub const INTRA_PLANAR: u8 = 2;
pub const INTRA_VERTICAL: u8 = 3;
pub const INTRA_HORIZONTAL: u8 = 4;
pub const INTRA_DIAG_DR: u8 = 5; // diagonal down-right from the top-left corner
pub const INTRA_DIAG_DL: u8 = 6; // diagonal down-left from the top row
pub const INTRA_HOR_DOWN: u8 = 7; // from the left column, shifted by column
// v0.5 — learned from the AV1 lineup: smooth-family prediction, PAETH's
// nearest-edge pick, and chroma-from-luma with four signed alphas.
pub const INTRA_SMOOTH: u8 = 8; // H/V planar-blend average (AV1 SMOOTH)
pub const INTRA_PAETH: u8 = 9; // nearest of left/top/topleft (PNG/AV1)
pub const INTRA_CFL_N2: u8 = 10; // chroma-from-luma, alpha = -2/2
pub const INTRA_CFL_N1: u8 = 11; // chroma-from-luma, alpha = -1/2
pub const INTRA_CFL_P1: u8 = 12; // chroma-from-luma, alpha = +1/2
pub const INTRA_CFL_P2: u8 = 13; // chroma-from-luma, alpha = +2/2

const SET_NONE: []const u8 = &.{INTRA_NONE};
const SET_ND: []const u8 = &.{ INTRA_NONE, INTRA_DC };
const SET_5: []const u8 = &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL };
const SET_8: []const u8 = &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL, INTRA_DIAG_DR, INTRA_DIAG_DL, INTRA_HOR_DOWN };
const SET_10: []const u8 = &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL, INTRA_DIAG_DR, INTRA_DIAG_DL, INTRA_HOR_DOWN, INTRA_SMOOTH, INTRA_PAETH };
const SET_NONE_CFL: []const u8 = &.{ INTRA_NONE, INTRA_CFL_N2, INTRA_CFL_N1, INTRA_CFL_P1, INTRA_CFL_P2 };
const SET_ND_CFL: []const u8 = &.{ INTRA_NONE, INTRA_DC, INTRA_CFL_N2, INTRA_CFL_N1, INTRA_CFL_P1, INTRA_CFL_P2 };
const SET_5_CFL: []const u8 = &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL, INTRA_CFL_N2, INTRA_CFL_N1, INTRA_CFL_P1, INTRA_CFL_P2 };
const SET_8_CFL: []const u8 = &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL, INTRA_DIAG_DR, INTRA_DIAG_DL, INTRA_HOR_DOWN, INTRA_CFL_N2, INTRA_CFL_N1, INTRA_CFL_P1, INTRA_CFL_P2 };
const SET_10_CFL: []const u8 = &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL, INTRA_DIAG_DR, INTRA_DIAG_DL, INTRA_HOR_DOWN, INTRA_SMOOTH, INTRA_PAETH, INTRA_CFL_N2, INTRA_CFL_N1, INTRA_CFL_P1, INTRA_CFL_P2 };

/// Enabled intra modes for this genome and plane kind. NONE is ALWAYS
/// present as mode 0 in every non-legacy set: the clamp-aware mode decision
/// then guarantees the chosen predictor is never worse than the legacy
/// raw-DCT path per block — richer sets can only help, never crater. A
/// single {NONE} set means legacy raw-DCT intra: no prediction, no mode
/// map, byte-exact v0.1-v0.3 bitstream. Tier >=0.925 adds SMOOTH/PAETH
/// (v0.5); chroma planes with the cfl gene on append the four CFL variants
/// (AV1 chroma-from-luma) — the map width is per-plane and both sides
/// derive it from the genome, so CFL costs zero extra signaling.
pub fn intraModes(g: *const gen.Genome, chroma: bool) []const u8 {
    const v = gen.intraPredGene(g);
    const cfl = chroma and gen.cflGene(g) > 0.5;
    if (v < 0.25) return if (cfl) SET_NONE_CFL else SET_NONE;
    if (v < 0.55) return if (cfl) SET_ND_CFL else SET_ND;
    if (v < 0.85) return if (cfl) SET_5_CFL else SET_5;
    if (v < 0.925) return if (cfl) SET_8_CFL else SET_8;
    return if (cfl) SET_10_CFL else SET_10;
}

/// Bits needed to index a mode within a set of n (ceil(log2(n))). Both sides
/// derive it from the genome, so the mode map costs 1 bit/block for
/// {NONE,DC} and 3-4 bits/block for the richer sets — x264-style narrow
/// signaling in a per-plane map instead of a byte per block.
pub fn intraModeBits(n: usize) u5 {
    if (n <= 1) return 0;
    return @intCast(32 - @clz(@as(u32, @intCast(n - 1))));
}

/// DC prediction of an 8x8 block from its recon neighbors (shared by the
/// DC mode and the CFL base term).
fn dcPred8(recon: []const u8, pw: usize, sx: usize, sy: usize) u8 {
    const have_top = sy > 0;
    const have_left = sx > 0;
    var dc: i32 = 128 * 16;
    if (have_top and have_left) {
        var s: i32 = 0;
        for (0..8) |i| s += recon[(sy - 1) * pw + sx + i];
        for (0..8) |i| s += recon[(sy + i) * pw + sx - 1];
        dc = @divTrunc(s + 8, 16);
    } else if (have_top) {
        var s: i32 = 0;
        for (0..8) |i| s += recon[(sy - 1) * pw + sx + i];
        dc = @divTrunc(s + 4, 8);
    } else if (have_left) {
        var s: i32 = 0;
        for (0..8) |i| s += recon[(sy + i) * pw + sx - 1];
        dc = @divTrunc(s + 4, 8);
    }
    return @intCast(std.math.clamp(dc, 0, 255));
}

/// v0.8: DC prediction of a 16x16 superblock from its recon neighbors — the
/// big-TX twin of dcPred8, shared by encoder trial and decoder recon.
fn dcPred16(recon: []const u8, pw: usize, sx: usize, sy: usize) u8 {
    const have_top = sy > 0;
    const have_left = sx > 0;
    var dc: i32 = 128 * 32;
    if (have_top and have_left) {
        var s: i32 = 0;
        for (0..16) |i| s += recon[(sy - 1) * pw + sx + i];
        for (0..16) |i| s += recon[(sy + i) * pw + sx - 1];
        dc = @divTrunc(s + 16, 32);
    } else if (have_top) {
        var s: i32 = 0;
        for (0..16) |i| s += recon[(sy - 1) * pw + sx + i];
        dc = @divTrunc(s + 8, 16);
    } else if (have_left) {
        var s: i32 = 0;
        for (0..16) |i| s += recon[(sy + i) * pw + sx - 1];
        dc = @divTrunc(s + 8, 16);
    }
    return @intCast(std.math.clamp(dc, 0, 255));
}

/// Build the 8x8 prediction block for `mode` from the recon plane at block
/// (sx, sy). Unavailable neighbors (frame edges) are filled with 128.
/// Deterministic in (mode, plane contents, sx, sy, pw, ph, luma, lpw) only —
/// the same function runs on both sides, so predictions can never
/// desynchronize. `luma` is the co-located reconstructed luma plane (chroma
/// CFL modes only); at the point chroma is coded, both sides hold the SAME
/// pre-deblocking luma recon, so CFL needs zero side information.
fn intraPredict(mode: u8, recon: []const u8, pw: usize, ph: usize, sx: usize, sy: usize, out: *[64]u8, luma: ?[]const u8, lpw: usize) void {
    var top: [8]u8 = @splat(128);
    var left: [8]u8 = @splat(128);
    var tl: u8 = 128;
    var tr: u8 = 128; // one past the top row's right edge (planar)
    var bl: u8 = 128; // one past the left column's bottom edge (planar)
    const have_top = sy > 0;
    const have_left = sx > 0;
    if (have_top) {
        for (0..8) |c| top[c] = recon[(sy - 1) * pw + sx + c];
        tl = if (have_left) recon[(sy - 1) * pw + sx - 1] else 128;
        tr = if (sx + 8 < pw) recon[(sy - 1) * pw + sx + 8] else top[7];
    }
    if (have_left) {
        for (0..8) |r| left[r] = recon[(sy + r) * pw + sx - 1];
        bl = if (sy + 8 < ph) recon[(sy + 8) * pw + sx - 1] else left[7];
    }
    switch (mode) {
        INTRA_NONE => {
            // legacy raw-DCT intra expressed as prediction: pred = mid-gray,
            // so recon = pred + rec - 128 == rec, byte-identical to v0.1-v0.3.
            @memset(out, 128);
        },
        INTRA_VERTICAL => {
            for (0..8) |r| for (0..8) |c| {
                out[r * 8 + c] = top[c];
            };
        },
        INTRA_HORIZONTAL => {
            for (0..8) |r| for (0..8) |c| {
                out[r * 8 + c] = left[r];
            };
        },
        INTRA_DC => {
            const px = dcPred8(recon, pw, sx, sy);
            @memset(out, px);
        },
        INTRA_PLANAR => {
            for (0..8) |r| for (0..8) |c| {
                const v: i32 = ((7 - @as(i32, @intCast(c))) * @as(i32, left[r]) +
                    (@as(i32, @intCast(c)) + 1) * @as(i32, tr) +
                    (7 - @as(i32, @intCast(r))) * @as(i32, top[c]) +
                    (@as(i32, @intCast(r)) + 1) * @as(i32, bl) + 8) >> 4;
                out[r * 8 + c] = @intCast(std.math.clamp(v, 0, 255));
            };
        },
        INTRA_DIAG_DR => {
            // ref[0]=TL, ref[1..8]=top, ref[9..15]=left[0..6]
            var ref: [16]u8 = @splat(128);
            ref[0] = tl;
            for (0..8) |c| ref[1 + c] = top[c];
            for (0..7) |r| ref[9 + r] = left[r];
            for (0..8) |r| for (0..8) |c| {
                const idx = @min(@as(usize, 15), r + c + 1);
                out[r * 8 + c] = ref[idx];
            };
        },
        INTRA_DIAG_DL => {
            for (0..8) |r| for (0..8) |c| {
                const idx = @min(@as(usize, 7), c + (r + 1) / 2);
                out[r * 8 + c] = top[idx];
            };
        },
        INTRA_HOR_DOWN => {
            for (0..8) |r| for (0..8) |c| {
                const idx = @min(@as(usize, 7), r + (c + 1) / 2);
                out[r * 8 + c] = left[idx];
            };
        },
        INTRA_SMOOTH => {
            // AV1 SMOOTH: bilinear blends of the top/left edges, averaged.
            for (0..8) |r| for (0..8) |c| {
                const h: i32 = @divTrunc((7 - @as(i32, @intCast(c))) * @as(i32, left[r]) +
                    (@as(i32, @intCast(c)) + 1) * @as(i32, tr) + 4, 8);
                const vv: i32 = @divTrunc((7 - @as(i32, @intCast(r))) * @as(i32, top[c]) +
                    (@as(i32, @intCast(r)) + 1) * @as(i32, bl) + 4, 8);
                out[r * 8 + c] = @intCast(std.math.clamp((h + vv + 1) >> 1, 0, 255));
            };
        },
        INTRA_PAETH => {
            // PNG/AV1 PAETH: the neighbor closest to the plane predictor.
            for (0..8) |r| for (0..8) |c| {
                const pl: i32 = @as(i32, left[r]) + @as(i32, top[c]) - @as(i32, tl);
                const dl = @abs(pl - @as(i32, left[r]));
                const dt = @abs(pl - @as(i32, top[c]));
                const dtl = @abs(pl - @as(i32, tl));
                const v: u8 = if (dl <= dt and dl <= dtl) left[r] else if (dt <= dtl) top[c] else tl;
                out[r * 8 + c] = v;
            };
        },
        INTRA_CFL_N2, INTRA_CFL_N1, INTRA_CFL_P1, INTRA_CFL_P2 => {
            // AV1 chroma-from-luma: decimate the co-located 16x16 luma block
            // to 8x8 (2x2 mean), remove its mean, scale by the signed alpha
            // (a2 = 2*alpha), and add the chroma DC base. All inputs are the
            // recon planes both sides already share — zero side information.
            const lum = luma.?;
            var ld: [64]i32 = undefined;
            var mean: i64 = 0;
            for (0..8) |r| {
                const ly0 = 2 * sy + 2 * r;
                const ly1 = ly0 + 1;
                for (0..8) |c| {
                    const lx0 = 2 * sx + 2 * c;
                    const s: i32 = @as(i32, lum[ly0 * lpw + lx0]) +
                        @as(i32, lum[ly0 * lpw + lx0 + 1]) +
                        @as(i32, lum[ly1 * lpw + lx0]) +
                        @as(i32, lum[ly1 * lpw + lx0 + 1]);
                    const d = s >> 2;
                    ld[r * 8 + c] = d;
                    mean += d;
                }
            }
            const lm: i32 = @intCast(@divTrunc(mean + 32, 64));
            const dc: i32 = @as(i32, dcPred8(recon, pw, sx, sy));
            const a2: i32 = switch (mode) {
                INTRA_CFL_N2 => -2,
                INTRA_CFL_N1 => -1,
                INTRA_CFL_P1 => 1,
                else => 2,
            };
            for (0..8) |r| for (0..8) |c| {
                const lp = ld[r * 8 + c] - lm;
                const v = dc + @divTrunc(a2 * lp, 2);
                out[r * 8 + c] = @intCast(std.math.clamp(v, 0, 255));
            };
        },
        else => unreachable, // encoder only writes modes from intraModes()
    }
}

// ------------------------------------------------------- in-loop deblocking
// Learned from x264/H.264: smooth 8x8 block edges on the reconstructed frame
// before it becomes the next reference and the measured output. H.264-lite:
// an edge pair (p1,p0|q0,q1) is filtered only when the step across the edge
// and both neighboring steps are small (alpha/beta activity tests); the
// correction moves p0/q0 toward their local mean without overshooting the
// midpoint. Frame-atomic: applied to the finished recon frame identically on
// both sides, so predictions inside a frame never see a half-filtered plane.
// Gene-gated: strength 0 = off = byte-exact legacy.

fn deblockPair(p0: *u8, q0: *u8, p1: u8, q1: u8, alpha: f32, beta: f32) void {
    const fp0: f32 = @floatFromInt(p0.*);
    const fq0: f32 = @floatFromInt(q0.*);
    const d = fq0 - fp0;
    if (@abs(d) >= alpha) return;
    const dp = @abs(@as(f32, @floatFromInt(p1)) - fp0);
    if (dp >= beta) return;
    const dq = @abs(@as(f32, @floatFromInt(q1)) - fq0);
    if (dq >= beta) return;
    const filt = (3.0 * d + (@as(f32, @floatFromInt(p1)) - @as(f32, @floatFromInt(q1)))) / 8.0;
    const maxd = @max(1.0, @abs(d) * 0.5);
    const delta = std.math.clamp(filt, -maxd, maxd);
    p0.* = @intFromFloat(std.math.clamp(@round(fp0 + delta), 0.0, 255.0));
    q0.* = @intFromFloat(std.math.clamp(@round(fq0 - delta), 0.0, 255.0));
}

fn deblockPlane(plane: []u8, pw: usize, ph: usize, strength: f32, qp: f32) void {
    const alpha = strength * (6.0 + qp * 0.8);
    const beta = strength * (3.0 + qp * 0.4);
    var c: usize = 8;
    while (c < pw) : (c += 8) { // vertical block edges
        for (0..ph) |r| {
            const row = plane[r * pw ..];
            deblockPair(&row[c - 1], &row[c], row[c - 2], row[c + 1], alpha, beta);
        }
    }
    var rr: usize = 8;
    while (rr < ph) : (rr += 8) { // horizontal block edges
        for (0..pw) |cc| {
            deblockPair(
                &plane[(rr - 1) * pw + cc],
                &plane[rr * pw + cc],
                plane[(rr - 2) * pw + cc],
                plane[(rr + 1) * pw + cc],
                alpha,
                beta,
            );
        }
    }
}

/// In-loop deblock of a finished frame (all three planes). Shared by encoder
/// and decoder — one code path, one qp, zero side info.
fn deblockFrame(g: *const gen.Genome, y: []u8, u: []u8, v: []u8, w: usize, h: usize, qp: f32) void {
    const s = gen.deblockGene(g);
    if (s <= 0) return;
    deblockPlane(y, w, h, s, qp);
    deblockPlane(u, w / 2, h / 2, s, qp);
    deblockPlane(v, w / 2, h / 2, s, qp);
}

// ---------------------------------------------------- CDEF-lite deringing
// v0.5 — learned from the AV1 lineup (CDEF, the constrained directional
// enhancement filter): after deblocking, a short directional smoothing pass
// removes residual ringing along each block's dominant edge direction.
// Simplified from AV1: 4 line orientations (0/45/90/135 degrees) chosen by
// constrained-gradient argmin on the RECONSTRUCTED block (decoder-derivable,
// zero side info), 5-tap constrained averaging along the line with qp-scaled
// damping, skip on isotropic blocks (no dominant edge to enhance).
// Frame-atomic like deblock: reads a snapshot, writes the plane in place,
// runs identically on both sides. Gene-gated: <=0.5 = off = legacy recon.

fn cdefConstrain(v: i32, center: i32, th: i32) i32 {
    return center + std.math.clamp(v - center, -th, th);
}

fn cdefPlane(p: []u8, pw: usize, ph: usize, qp: f32, snap: []u8) void {
    @memcpy(snap[0 .. pw * ph], p[0 .. pw * ph]);
    const qp_i: i32 = @intFromFloat(qp);
    const damp: usize = @intCast(2 + @divTrunc(qp_i, 24)); // tap displacement cap
    const nbx = pw / 8;
    const nby = ph / 8;
    // 4 line orientations: (dx,dy) positive-step along the line
    const dirs = [4][2]i32{ .{ 1, 0 }, .{ 1, 1 }, .{ 0, 1 }, .{ -1, 1 } };
    var by: usize = 0;
    while (by < nby) : (by += 1) {
        var bx: usize = 0;
        while (bx < nbx) : (bx += 1) {
            const sx = bx * 8;
            const sy = by * 8;
            // dominant direction: min constrained-gradient cost over 4 lines
            var best_dir: usize = 0;
            var best_cost: i64 = std.math.maxInt(i64);
            for (dirs, 0..) |d, di| {
                var cost: i64 = 0;
                var r: usize = 2;
                while (r < 6) : (r += 1) {
                    var c: usize = 2;
                    while (c < 6) : (c += 1) {
                        const x: i32 = @as(i32, @intCast(sx + c));
                        const y: i32 = @as(i32, @intCast(sy + r));
                        const ctr: i32 = snap[@as(usize, @intCast(y)) * pw + @as(usize, @intCast(x))];
                        for (1..3) |k| {
                            const kk: i32 = @intCast(k);
                            const xx = std.math.clamp(x + d[0] * kk, 0, @as(i32, @intCast(pw - 1)));
                            const yy = std.math.clamp(y + d[1] * kk, 0, @as(i32, @intCast(ph - 1)));
                            const smp: i32 = snap[@as(usize, @intCast(yy)) * pw + @as(usize, @intCast(xx))];
                            cost += @divTrunc(@as(i64, @intCast(@abs(smp - ctr))), 4);
                        }
                    }
                }
                if (cost < best_cost) {
                    best_cost = cost;
                    best_dir = di;
                }
            }
            // isotropic block: no dominant edge -> skip (AV1's skip condition,
            // simplified). Threshold scales with block area (64 px, inner 16
            // sampled twice => 128 pairs max at avg grad 2).
            if (best_cost > 512) continue;
            const d = dirs[best_dir];
            for (0..8) |r| {
                for (0..8) |c| {
                    const x: i32 = @as(i32, @intCast(sx + c));
                    const y: i32 = @as(i32, @intCast(sy + r));
                    const ci: usize = @as(usize, @intCast(y)) * pw + @as(usize, @intCast(x));
                    const ctr: i32 = snap[ci];
                    var sum: i64 = ctr;
                    for (1..3) |k| {
                        const kk: i32 = @intCast(@min(k, damp));
                        for (0..2) |sg| {
                            const sgn: i32 = if (sg == 0) 1 else -1;
                            const xx = std.math.clamp(x + d[0] * kk * sgn, 0, @as(i32, @intCast(pw - 1)));
                            const yy = std.math.clamp(y + d[1] * kk * sgn, 0, @as(i32, @intCast(ph - 1)));
                            const smp: i32 = snap[@as(usize, @intCast(yy)) * pw + @as(usize, @intCast(xx))];
                            sum += cdefConstrain(smp, ctr, 6);
                        }
                    }
                    p[ci] = @intCast(std.math.clamp(@divTrunc(sum + 2, 5), 0, 255));
                }
            }
        }
    }
}

fn cdefFrame(g: *const gen.Genome, y: []u8, u: []u8, v: []u8, w: usize, h: usize, qp: f32, snap: []u8) void {
    const gene = gen.cdefGene(g);
    if (gene <= 0.5) return;
    cdefPlane(y, w, h, qp, snap);
    cdefPlane(u, w / 2, h / 2, qp, snap);
    cdefPlane(v, w / 2, h / 2, qp, snap);
}

// ------------------------------------------------------------- context

const Ctx = struct {
    clip: *const yuv.Clip,
    g: *const gen.Genome,
    opts: EvalOpts,

    encY: []u8,
    encU: []u8,
    encV: []u8,
    prevY: []u8,
    prevU: []u8,
    prevV: []u8,
    decY: []u8,
    decU: []u8,
    decV: []u8,

    bw: BW,
    br: BR,
    // per-plane scratch: block data is assembled here, then framed as
    // [mode map][block data] into the main bitstream (v0.4 syntax; the
    // v0.5 entropy gene packs it through the arithmetic coder instead)
    scratch: []u8,
    // CDEF snapshot buffer (max plane size; frame-atomic filtering)
    cdef_buf: []u8,
    // v0.5b half-pel MC planes (max plane size; rebuilt per reference plane
    // when the qpel gene is on — the interpolated reference buffer)
    mcH: []u8,
    mcV: []u8,
    mcD: []u8,

    block_src: [64]u8 = @splat(0),
    dct_calls: u64 = 0,
    idct_calls: u64 = 0,
    qp_adj: f32 = 0,
    prev_frame_bytes: usize = 0,
    last_frame_bytes: usize = 0,
    dec_fi: u32 = 0,
    cur_gop: f32 = 0,
    // decoder-side handle on the current frame's luma recon (CFL source for
    // chroma planes); set by decodeFrame
    dec_cur_y: []const u8 = &.{},
    debug_px: bool = false,
};

fn packPairs(bw: *BW, lv: []const i32, last: usize) void {
    var npairs: u64 = 0;
    for (lv[0 .. last + 1]) |l| {
        if (l != 0) npairs += 1;
    }
    bw.putUvarint(npairs);
    var run: u64 = 0;
    for (0..last + 1) |k| {
        if (lv[k] == 0) {
            run += 1;
        } else {
            bw.putUvarint(run);
            bw.putSvarint(lv[k]);
            run = 0;
        }
    }
}

fn quantizeBlock(ctx: *Ctx, src: []const u8, qp: f32, scale: f32, rc: gen.RegCtx, lv: *[64]i32) void {
    var coef: [64]f32 = undefined;
    dct8(src, &coef);
    ctx.dct_calls += 1;
    // base deadzone, motion-regulated; DC gets its own multiplier (dz_dc gene)
    const dz0 = gen.regDeadzone(ctx.g, rc, gen.deadzone(ctx.g));
    const dith = gen.dither(ctx.g);
    for (0..64) |k| {
        const dz = if (k == 0) dz0 * gen.dzDcMul(ctx.g) else dz0;
        lv[k] = quantLevel(coef[ZZ[k]], levelQ(ctx.g, qp, scale, k, rc), dz, dith);
    }
}

fn dequantLevels(ctx: *Ctx, lv: *const [64]i32, qp: f32, scale: f32, rc: gen.RegCtx, out: *[64]f32) void {
    for (0..64) |k| {
        const lf: f32 = @floatFromInt(lv[k]);
        out[ZZ[k]] = lf * levelQ(ctx.g, qp, scale, k, rc);
    }
}

/// v0.8: big-TX quantize — dct16 + deadzone over the 256-coef zigzag.
fn quantizeBlock16(ctx: *Ctx, src: []const u8, qp: f32, scale: f32, rc: gen.RegCtx, lv: *[256]i32) void {
    var coef: [256]f32 = undefined;
    dct16(src, &coef);
    ctx.dct_calls += 1;
    const dz0 = gen.regDeadzone(ctx.g, rc, gen.deadzone(ctx.g));
    const dith = gen.dither(ctx.g);
    for (0..256) |k| {
        const dz = if (k == 0) dz0 * gen.dzDcMul(ctx.g) else dz0;
        lv[k] = quantLevel(coef[ZZ16[k]], levelQ16(ctx.g, qp, scale, k, rc), dz, dith);
    }
}
fn dequantLevels16(ctx: *Ctx, lv: *const [256]i32, qp: f32, scale: f32, rc: gen.RegCtx, out: *[256]f32) void {
    for (0..256) |k| {
        const lf: f32 = @floatFromInt(lv[k]);
        out[ZZ16[k]] = lf * levelQ16(ctx.g, qp, scale, k, rc);
    }
}

// --------------------------------------------------------------- encode frame

fn encodeFrame(ctx: *Ctx, fi: u32) !void {
    const g = ctx.g;
    const clip = ctx.clip;
    const key_int = gen.keyInt(g);
    const is_i = (fi % key_int) == 0;
    // GOP position in [0,1) — regulator context (decoder derives the same
    // value from dec_fi, so frame-level regulation needs no side info)
    const gop: f32 = @as(f32, @floatFromInt(fi % key_int)) / @as(f32, @floatFromInt(key_int));
    // R2 (gop_q): frame-level quality ramp across the GOP. The modulated qp
    // is transmitted in the frame header — decoder reads it, zero extra bits.
    const qp_f0: f32 = std.math.clamp(gen.baseQ(g) + ctx.qp_adj, 1.0, 120.0);
    const qp_f: f32 = std.math.clamp(qp_f0 * (1.0 + gen.regGain(g, 2) * (2.0 * gop - 1.0)), 1.0, 120.0);
    const qp: f32 = @round(qp_f);
    ctx.cur_gop = gop;

    ctx.bw.putU8(if (is_i) 1 else 0);
    ctx.bw.putU8(@intFromFloat(qp));

    // working planes start as copy of previous recon
    @memcpy(ctx.encY, ctx.prevY);
    @memcpy(ctx.encU, ctx.prevU);
    @memcpy(ctx.encV, ctx.prevV);

    const refresh = gen.refreshEvery(g);

    // ---- Y plane ----
    try encodePlane(ctx, fi, is_i, qp, clip.y, ctx.encY, ctx.prevY, clip.w, clip.h, false, refresh, @as(usize, fi) * clip.ysz);
    // ---- chroma ----
    try encodePlane(ctx, fi, is_i, qp, clip.u, ctx.encU, ctx.prevU, clip.w / 2, clip.h / 2, true, refresh, @as(usize, fi) * clip.csz);
    try encodePlane(ctx, fi, is_i, qp, clip.v, ctx.encV, ctx.prevV, clip.w / 2, clip.h / 2, true, refresh, @as(usize, fi) * clip.csz);

    // v0.4 in-loop deblocking + v0.5 CDEF-lite deringing: the finished recon
    // frame is filtered BEFORE it becomes the next reference and the stored
    // decoder output. Same qp, same code path on the decoder — can never
    // desynchronize.
    deblockFrame(g, ctx.encY, ctx.encU, ctx.encV, clip.w, clip.h, qp);
    cdefFrame(g, ctx.encY, ctx.encU, ctx.encV, clip.w, clip.h, qp, ctx.cdef_buf);

    // swap: enc becomes prev
    const ty = ctx.prevY;
    const tu = ctx.prevU;
    const tv = ctx.prevV;
    ctx.prevY = ctx.encY;
    ctx.prevU = ctx.encU;
    ctx.prevV = ctx.encV;
    ctx.encY = ty;
    ctx.encU = tu;
    ctx.encV = tv;

    // store decoded frame (closed loop: decoder output == encoder recon)
    const fidx: usize = @as(usize, fi);
    @memcpy(ctx.decY[fidx * clip.ysz ..][0..clip.ysz], ctx.prevY);
    @memcpy(ctx.decU[fidx * clip.csz ..][0..clip.csz], ctx.prevU);
    @memcpy(ctx.decV[fidx * clip.csz ..][0..clip.csz], ctx.prevV);

    // adaptive Q (open loop): fat frame -> squeeze next
    const fb = ctx.last_frame_bytes;
    if (ctx.prev_frame_bytes > 0 and gen.adaptQ(g) > 0.01) {
        if (fb > ctx.prev_frame_bytes) {
            ctx.qp_adj += 0.05 * gen.adaptQ(g);
        } else {
            ctx.qp_adj -= 0.025 * gen.adaptQ(g);
        }
        ctx.qp_adj = std.math.clamp(ctx.qp_adj, -2.0, gen.adaptQ(g));
    }
    ctx.prev_frame_bytes = fb;
}

fn encodePlane(
    ctx: *Ctx,
    fi: u32,
    is_i: bool,
    qp: f32,
    src: []const u8,
    enc: []u8,
    prev: []const u8,
    pw: u32,
    ph: u32,
    chroma: bool,
    refresh: u32,
    src_base: usize,
) !void {
    // v0.5 entropy gene: comptime-specialized plane body — legacy byte
    // varints or the adaptive arithmetic coder, one shared source.
    if (gen.entropyGene(ctx.g) > 0.5) {
        return encodePlaneT(ctx, fi, is_i, qp, src, enc, prev, pw, ph, chroma, refresh, src_base, true);
    }
    return encodePlaneT(ctx, fi, is_i, qp, src, enc, prev, pw, ph, chroma, refresh, src_base, false);
}

fn encodePlaneT(
    ctx: *Ctx,
    fi: u32,
    is_i: bool,
    qp: f32,
    src: []const u8,
    enc: []u8,
    prev: []const u8,
    pw: u32,
    ph: u32,
    chroma: bool,
    refresh: u32,
    src_base: usize,
    comptime ac_on: bool,
) !void {
    const g = ctx.g;
    const cqp_scale = gen.chromaScale(g);
    const iq_scale: f32 = if (chroma) cqp_scale else 1.0;
    const pq_scale: f32 = if (chroma) gen.pQmul(g) * cqp_scale else gen.pQmul(g);
    const nbx: usize = pw / 8;
    const nby: usize = ph / 8;
    const rrow: usize = @intCast((fi / refresh) % @max(1, nby));
    const do_refresh = !is_i and !chroma and (fi / refresh) > 0;
    const halfpel = gen.halfPel(g);
    // v0.5b: build the half-pel planes ONCE per reference plane when the qpel
    // gene is on and this plane can contain inter blocks. Production MC reads
    // the planes (mcBlockQ); the direct interpBlockQ is test-reference only.
    const qpel = gen.qpelOn(g);
    if (qpel and !is_i) {
        buildHalfPlanes(prev, pw, ph, ctx.mcH, ctx.mcV, ctx.mcD);
    }
    // CFL reads the co-located luma recon — pre-deblock on BOTH sides.
    const cfl_luma: ?[]const u8 = if (chroma) ctx.encY else null;
    const cfl_lpw: usize = ctx.clip.w;

    // v0.4 per-plane framing: block data goes to scratch, intra mode codes go
    // to a bit-packed map; the plane lands as [mode map][block data].
    const modes = intraModes(g, chroma);
    const mwidth: u5 = intraModeBits(modes.len);
    var mmap: [1024]u8 = @splat(0);
    var mbacc: u32 = 0;
    var mbn: u5 = 0;
    var mmap_n: usize = 0; // completed bytes in the mode map
    var w = BlockW(ac_on).init(ctx.scratch);
    if (modes.len > 1 and (nbx * nby * @as(usize, mwidth) + 7) / 8 > mmap.len) return error.BitstreamOverflow;

    // ---- v0.8: the 16x16 superblock layer ------------------------------
    // Full 16x16 superblocks (aligned, non-mixed) can code as ONE unit:
    //   flag 3 + subtype 0 = unified intra (DC pred + 16x16 TX, no mode bits)
    //   flag 3 + subtype 1 = skip16 (one MV, 4 blocks copied)
    //   flag 3 + subtype 2 = inter16 (one MV + 16x16 TX residual)
    // The encoder trials the unified mode against the legacy 4x8x8 path with
    // full stream/mode-map/recon rollback, and keeps whichever wins on
    // SSE + lambda*bits. Gene-gated: sb16 <= 0.5 never writes flag 3 and the
    // marker tree stays bit-exact legacy.
    const sb16_on = gen.sb16On(g);
    const SbSnap = struct {
        const State = struct {
            ac_n: usize = 0,
            ac_low: u64 = 0,
            ac_range: u32 = 0,
            ac_cache: u8 = 0,
            ac_cs: u32 = 0,
            ps: Probs = undefined,
            bw_n: usize = 0,
            bw_bacc: u32 = 0,
            bw_bn: u5 = 0,
            mbacc: u32 = 0,
            mbn: u5 = 0,
            mmap_n: usize = 0,
        };
        fn snap(wv: *BlockW(ac_on), macc: u32, mb: u5, mn: usize) State {
            var s = State{ .mbacc = macc, .mbn = mb, .mmap_n = mn };
            if (ac_on) {
                s.ac_n = wv.ac.n;
                s.ac_low = wv.ac.low;
                s.ac_range = wv.ac.range;
                s.ac_cache = wv.ac.cache;
                s.ac_cs = wv.ac.cache_size;
                s.ps = wv.ps;
            } else {
                s.bw_n = wv.bw.n;
                s.bw_bacc = wv.bw.bacc;
                s.bw_bn = wv.bw.bn;
            }
            return s;
        }
        fn restore(wv: *BlockW(ac_on), s: State, macc: *u32, mb: *u5, mn: *usize) void {
            if (ac_on) {
                wv.ac.n = s.ac_n;
                wv.ac.low = s.ac_low;
                wv.ac.range = s.ac_range;
                wv.ac.cache = s.ac_cache;
                wv.ac.cache_size = s.ac_cs;
                wv.ps = s.ps;
            } else {
                wv.bw.n = s.bw_n;
                wv.bw.bacc = s.bw_bacc;
                wv.bw.bn = s.bw_bn;
            }
            macc.* = s.mbacc;
            mb.* = s.mbn;
            mn.* = s.mmap_n;
        }
    };
    const SbU = struct {
        /// Encode one full superblock in unified mode (flag 3 + subtype +
        /// payload) and write the recon into `encp`. Deterministic — the
        /// caller runs it once as a trial, then again to commit.
        fn encode(
            cctx: *Ctx,
            wv: *BlockW(ac_on),
            srcp: []const u8,
            sbase: usize,
            encp: []u8,
            prevp: []const u8,
            pwv: usize,
            phv: usize,
            is_i_v: bool,
            chroma_v: bool,
            qp_v: f32,
            iq_v: f32,
            pq_v: f32,
            gop_v: f32,
            sxv: usize,
            syv: usize,
            fast: bool,
        ) void {
            const gg = cctx.g;
            wv.markerSB(3, true);
            var sb_src: [256]u8 = undefined;
            var sr0: usize = 0;
            while (sr0 < 16) : (sr0 += 1) {
                @memcpy(sb_src[sr0 * 16 ..][0..16], srcp[sbase + (syv + sr0) * pwv + sxv ..][0..16]);
            }
            const by_v = syv / 8;
            const by_n_v: f32 = (@as(f32, @floatFromInt(by_v)) + 0.5) / @as(f32, @floatFromInt(phv / 8));
            if (is_i_v) {
                // unified intra: DC prediction from recon neighbors + big TX
                wv.markerSB(0, false);
                const dc = dcPred16(encp, pwv, sxv, syv);
                const pred: [256]u8 = @splat(dc);
                var res: [256]u8 = undefined;
                for (0..256) |k| {
                    const d: i32 = @as(i32, sb_src[k]) - @as(i32, pred[k]);
                    res[k] = @intCast(std.math.clamp(d + 128, 0, 255));
                }
                const rc = gen.RegCtx{ .mv_n = 0, .by_n = by_n_v, .gop = gop_v, .intra = true };
                var lv: [256]i32 = undefined;
                quantizeBlock16(cctx, res[0..], qp_v, iq_v, rc, &lv);
                var last: usize = 0;
                for (0..256) |k| {
                    if (lv[k] != 0) last = k;
                }
                wv.levels16(lv[0..], last);
                var deq: [256]f32 = undefined;
                dequantLevels16(cctx, &lv, qp_v, iq_v, rc, &deq);
                var rec: [256]u8 = undefined;
                idct16(&deq, rec[0..], 16, &cctx.idct_calls);
                const dst = encp[syv * pwv + sxv ..];
                for (0..16) |r2| {
                    for (0..16) |c2| {
                        const v: i32 = @as(i32, pred[r2 * 16 + c2]) + @as(i32, rec[r2 * 16 + c2]) - 128;
                        dst[r2 * pwv + c2] = @intCast(std.math.clamp(v, 0, 255));
                    }
                }
            } else {
                // unified inter: integer-MV SAD16 search, skip16 or big-TX
                const rmax: i32 = if (chroma_v)
                    @intCast(@max(1, gen.searchR(gg) / 2))
                else
                    @as(i32, @intCast(gen.searchR(gg)));
                const ymin: i32 = -@as(i32, @intCast(@min(gen.searchR(gg), syv)));
                const ymax: i32 = @intCast(@min(gen.searchR(gg), phv - 16 - syv));
                const xmin: i32 = -@as(i32, @intCast(@min(gen.searchR(gg), sxv)));
                const xmax: i32 = @intCast(@min(gen.searchR(gg), pwv - 16 - sxv));
                var best: u64 = std.math.maxInt(u64);
                var bdx: i32 = 0;
                var bdy: i32 = 0;
                var dy: i32 = ymin;
                while (dy <= ymax) : (dy += 1) {
                    if (dy < -rmax or dy > rmax) continue;
                    var dx: i32 = xmin;
                    while (dx <= xmax) : (dx += 1) {
                        if (dx < -rmax or dx > rmax) continue;
                        const ox: usize = @intCast(@as(i32, @intCast(sxv)) + dx);
                        const oy: usize = @intCast(@as(i32, @intCast(syv)) + dy);
                        var acc: u64 = 0;
                        if (fast) {
                            var fr: usize = 0;
                            while (fr < 16) : (fr += 2) {
                                var fc: usize = 0;
                                while (fc < 16) : (fc += 2) {
                                    acc += @abs(@as(i32, sb_src[fr * 16 + fc]) - @as(i32, prevp[oy * pwv + ox + fc]));
                                }
                            }
                            acc *= 4;
                        } else {
                            for (0..16) |fr| {
                                for (0..16) |fc| {
                                    acc += @abs(@as(i32, sb_src[fr * 16 + fc]) - @as(i32, prevp[oy * pwv + ox + fc]));
                                }
                            }
                        }
                        if (acc < best) {
                            best = acc;
                            bdx = dx;
                            bdy = dy;
                        }
                    }
                }
                const rc = gen.RegCtx{
                    .mv_n = @min(1.0, (@as(f32, @floatFromInt(@abs(bdx))) + @as(f32, @floatFromInt(@abs(bdy)))) / 8.0),
                    .by_n = by_n_v,
                    .gop = gop_v,
                    .intra = false,
                };
                const perpx: f32 = @as(f32, @floatFromInt(best)) / 256.0;
                const skip_th = gen.regSkipTh(gg, rc, gen.skipTh(gg));
                const ox_i: i32 = @as(i32, @intCast(sxv)) + bdx;
                const oy_i: i32 = @as(i32, @intCast(syv)) + bdy;
                if (perpx < skip_th) {
                    wv.markerSB(1, false); // skip16: one MV, whole sb copied
                    wv.mv(bdx, bdy);
                    const dst = encp[syv * pwv + sxv ..];
                    var r2: usize = 0;
                    while (r2 < 16) : (r2 += 1) {
                        @memcpy(dst[r2 * pwv ..][0..16], prevp[@as(usize, @intCast(oy_i + @as(i32, @intCast(r2)))) * pwv + @as(usize, @intCast(ox_i)) ..][0..16]);
                    }
                } else {
                    wv.markerSB(2, false); // inter16: one MV + 16x16 TX residual
                    wv.mv(bdx, bdy);
                    var pred: [256]u8 = undefined;
                    var r2: usize = 0;
                    while (r2 < 16) : (r2 += 1) {
                        @memcpy(pred[r2 * 16 ..][0..16], prevp[@as(usize, @intCast(oy_i + @as(i32, @intCast(r2)))) * pwv + @as(usize, @intCast(ox_i)) ..][0..16]);
                    }
                    var res: [256]u8 = undefined;
                    for (0..256) |k| {
                        const d: i32 = @as(i32, sb_src[k]) - @as(i32, pred[k]);
                        res[k] = @intCast(std.math.clamp(d + 128, 0, 255));
                    }
                    var lv: [256]i32 = undefined;
                    quantizeBlock16(cctx, res[0..], qp_v, pq_v, rc, &lv);
                    var last: usize = 0;
                    for (0..256) |k| {
                        if (lv[k] != 0) last = k;
                    }
                    wv.levels16(lv[0..], last);
                    var deq: [256]f32 = undefined;
                    dequantLevels16(cctx, &lv, qp_v, pq_v, rc, &deq);
                    var rec: [256]u8 = undefined;
                    idct16(&deq, rec[0..], 16, &cctx.idct_calls);
                    const dst = encp[syv * pwv + sxv ..];
                    for (0..16) |r3| {
                        for (0..16) |c3| {
                            const v: i32 = @as(i32, pred[r3 * 16 + c3]) + @as(i32, rec[r3 * 16 + c3]) - 128;
                            dst[r3 * pwv + c3] = @intCast(std.math.clamp(v, 0, 255));
                        }
                    }
                }
            }
        }
    }.encode;
    const SbPend = struct {
        s0: SbSnap.State,
        recon0: [256]u8,
        rate0: usize,
        rate_b: usize,
        err_b: u64,
        sx0: usize,
        sy0: usize,
    };
    var sb_pend: ?SbPend = null;

    var by: usize = 0;
    while (by < nby) : (by += 1) {
        const by_n: f32 = (@as(f32, @floatFromInt(by)) + 0.5) / @as(f32, @floatFromInt(nby));
        var bx: usize = 0;
        while (bx < nbx) : (bx += 1) {
            const sx = bx * 8;
            const sy = by * 8;
            // ---- v0.8 sb-start: trial the unified superblock mode ----------
            const sb_full = (by % 2 == 0) and (bx % 2 == 0) and (by + 2 <= nby) and (bx + 2 <= nbx);
            const sb_mixed = !is_i and do_refresh and (by == rrow or by + 1 == rrow);
            if (sb16_on and sb_full and !sb_mixed) {
                const s0 = SbSnap.snap(&w, mbacc, mbn, mmap_n);
                const rate0: usize = if (ac_on) s0.ac_n else s0.bw_n;
                var recon0: [256]u8 = undefined;
                var sr1: usize = 0;
                while (sr1 < 16) : (sr1 += 1) {
                    @memcpy(recon0[sr1 * 16 ..][0..16], enc[(sy + sr1) * pw + sx ..][0..16]);
                }
                SbU(ctx, &w, src, src_base, enc, prev, pw, ph, is_i, chroma, qp, iq_scale, pq_scale, ctx.cur_gop, sx, sy, ctx.opts.fast_sad);
                const rate_b = w.written() - rate0;
                var err_b: u64 = 0;
                var sr2: usize = 0;
                while (sr2 < 16) : (sr2 += 1) {
                    const srow = src[src_base + (sy + sr2) * pw + sx ..][0..16];
                    const erow = enc[(sy + sr2) * pw + sx ..][0..16];
                    for (0..16) |sc| {
                        const dv: i32 = @as(i32, srow[sc]) - @as(i32, erow[sc]);
                        err_b += @as(u64, @intCast(dv * dv));
                    }
                }
                // roll back to S0: stream, mode map, recon region
                SbSnap.restore(&w, s0, &mbacc, &mbn, &mmap_n);
                var sr3: usize = 0;
                while (sr3 < 16) : (sr3 += 1) {
                    @memcpy(enc[(sy + sr3) * pw + sx ..][0..16], recon0[sr3 * 16 ..][0..16]);
                }
                // optimistic legacy: the sb flag precedes the four blocks
                w.markerSB(0, true);
                sb_pend = .{
                    .s0 = s0,
                    .recon0 = recon0,
                    .rate0 = rate0,
                    .rate_b = rate_b,
                    .err_b = err_b,
                    .sx0 = bx,
                    .sy0 = by,
                };
            }
            // stage source block
            var r: usize = 0;
            while (r < 8) : (r += 1) {
                const srow = src[src_base + (sy + r) * pw + sx ..][0..8];
                @memcpy(ctx.block_src[r * 8 ..][0..8], srow);
            }

            const force_intra = is_i or (do_refresh and by == rrow);
            var rc = gen.RegCtx{
                .mv_n = 0,
                .by_n = by_n,
                .gop = ctx.cur_gop,
                .intra = force_intra,
            };

            if (force_intra) {
                if (!is_i) w.marker(2); // intra-in-P marker
                var lv: [64]i32 = undefined;
                if (modes.len == 1) {
                    // legacy: raw block into DCT — no prediction, no mode code
                    quantizeBlock(ctx, ctx.block_src[0..64], qp, iq_scale, rc, &lv);
                    var last: usize = 0;
                    for (0..64) |k| {
                        if (lv[k] != 0) last = k;
                    }
                    w.levels(lv[0..], last);
                    var deq: [64]f32 = undefined;
                    dequantLevels(ctx, &lv, qp, iq_scale, rc, &deq);
                    idct8(&deq, enc[sy * pw + sx ..], pw, &ctx.idct_calls);
                } else {
                    // v0.4: spatial prediction from reconstructed neighbors,
                    // mode decided by residual SAD, signaled with one byte.
                    // The prediction reads the encoder's OWN recon plane
                    // (raster-ordered) — byte-identical to the decoder's.
                    // Mode metric is CLAMP-AWARE: the residual travels in a
                    // u8 (+128 offset), so a predictor that leaves |src-pred|
                    // > 127 loses pixels to saturation. The metric below is
                    // the true pre-quant error of each candidate, so a bad
                    // predictor can never beat the legacy path — the mode
                    // decision degrades gracefully to legacy behavior.
                    var mode_i: usize = 0;
                    var pred: [64]u8 = undefined;
                    var best_err: u64 = std.math.maxInt(u64);
                    var trial: [64]u8 = undefined;
                    for (modes, 0..) |m, mi| {
                        intraPredict(m, enc, pw, ph, sx, sy, &trial, cfl_luma, cfl_lpw);
                        var err: u64 = 0;
                        for (0..64) |k| {
                            const s: i32 = @as(i32, ctx.block_src[k]);
                            const p: i32 = @as(i32, trial[k]);
                            const dcl: i32 = std.math.clamp(s - p, -128, 127);
                            err += @abs(p + dcl - s);
                        }
                        if (err < best_err) {
                            best_err = err;
                            mode_i = mi;
                            pred = trial;
                        }
                    }
                    mbacc = (mbacc << mwidth) | @as(u32, @intCast(mode_i));
                    mbn += mwidth;
                    while (mbn >= 8) {
                        mbn -= 8;
                        mmap[mmap_n] = @intCast((mbacc >> mbn) & 0xFF);
                        mmap_n += 1;
                    }
                    // residual = src - pred, offset by 128 for DCT
                    var res: [64]u8 = undefined;
                    for (0..64) |k| {
                        const d: i32 = @as(i32, ctx.block_src[k]) - @as(i32, pred[k]);
                        res[k] = @intCast(std.math.clamp(d + 128, 0, 255));
                    }
                    quantizeBlock(ctx, res[0..64], qp, iq_scale, rc, &lv);
                    var last: usize = 0;
                    for (0..64) |k| {
                        if (lv[k] != 0) last = k;
                    }
                    w.levels(lv[0..], last);
                    var deq: [64]f32 = undefined;
                    dequantLevels(ctx, &lv, qp, iq_scale, rc, &deq);
                    var rec: [64]u8 = undefined;
                    idct8(&deq, rec[0..64], 8, &ctx.idct_calls);
                    const dst = enc[sy * pw + sx ..];
                    for (0..8) |rr2| {
                        for (0..8) |cc2| {
                            const v: i32 = @as(i32, pred[rr2 * 8 + cc2]) + @as(i32, rec[rr2 * 8 + cc2]) - 128;
                            dst[rr2 * pw + cc2] = @intCast(std.math.clamp(v, 0, 255));
                        }
                    }
                }
            } else {
                // motion search against prev recon
                var best: u64 = std.math.maxInt(u64);
                var bdx: i32 = 0;
                var bdy: i32 = 0;
                const rmax: i32 = if (chroma)
                    @intCast(@max(1, gen.searchR(g) / 2))
                else
                    @as(i32, @intCast(gen.searchR(g)));
                const ymin: i32 = -@as(i32, @intCast(@min(gen.searchR(g), sy)));
                const ymax: i32 = @intCast(@min(gen.searchR(g), ph - 8 - sy));
                const xmin: i32 = -@as(i32, @intCast(@min(gen.searchR(g), sx)));
                const xmax: i32 = @intCast(@min(gen.searchR(g), pw - 8 - sx));
                var dy: i32 = ymin;
                while (dy <= ymax) : (dy += 1) {
                    if (dy < -rmax or dy > rmax) continue;
                    var dx: i32 = xmin;
                    while (dx <= xmax) : (dx += 1) {
                        if (dx < -rmax or dx > rmax) continue;
                        const ox: usize = @intCast(@as(i32, @intCast(sx)) + dx);
                        const oy: usize = @intCast(@as(i32, @intCast(sy)) + dy);
                        const s = sadBlock(ctx.block_src[0..64], prev[oy * pw + ox ..], pw, ctx.opts.fast_sad);
                        if (s < best) {
                            best = s;
                            bdx = dx;
                            bdy = dy;
                        }
                    }
                }
                const perpx: f32 = @as(f32, @floatFromInt(best)) / 64.0;
                rc.mv_n = @min(1.0, (@as(f32, @floatFromInt(@abs(bdx))) + @as(f32, @floatFromInt(@abs(bdy)))) / 8.0);
                // R4 (skip_mv): skip threshold scales with motion (encoder-side)
                const skip_th = gen.regSkipTh(g, rc, gen.skipTh(g));
                // v0.5b: qpel rides beside halfpel. When on, it SUPERSEDES the
                // bilinear half path: 4-tap Wiener halves + bilinear quarters,
                // code (qx+2)*5+(qy+2) in 5 bits (12 = integer center).
                const qpel_on = qpel;
                const sp_center: u8 = if (qpel_on) 12 else 4;
                const sp_bits: u4 = if (qpel_on) 5 else 4;
                var subpel: u8 = sp_center;
                var pred: [64]u8 = undefined;
                const ox_i: i32 = @intCast(@as(i32, @intCast(sx)) + bdx);
                const oy_i: i32 = @intCast(@as(i32, @intCast(sy)) + bdy);
                if (qpel_on) {
                    // two-stage refinement: 8 half positions (4-tap), then the
                    // 8 quarter neighbors of the winner (half re-tests excluded)
                    var hb: u64 = best;
                    var bqx: i32 = 0;
                    var bqy: i32 = 0;
                    var hp: [64]u8 = undefined;
                    var qy2: i32 = -2;
                    while (qy2 <= 2) : (qy2 += 2) {
                        var qx2: i32 = -2;
                        while (qx2 <= 2) : (qx2 += 2) {
                            if (qx2 == 0 and qy2 == 0) continue;
                            mcBlockQ(prev, ctx.mcH, ctx.mcV, ctx.mcD, pw, ph, ox_i, oy_i, qx2, qy2, &hp);
                            const s2 = sadBlock(ctx.block_src[0..64], &hp, 8, ctx.opts.fast_sad);
                            if (s2 < hb) {
                                hb = s2;
                                bqx = qx2;
                                bqy = qy2;
                            }
                        }
                    }
                    var qy3: i32 = -1;
                    while (qy3 <= 1) : (qy3 += 1) {
                        var qx3: i32 = -1;
                        while (qx3 <= 1) : (qx3 += 1) {
                            if (qx3 == 0 and qy3 == 0) continue;
                            // cost gate: if no half-pel beat the integer MV,
                            // skip the pure-quarter ring around center (the
                            // block gains little from sub-pel; saves 8 evals
                            // on exactly the blocks where it never pays).
                            if (bqx == 0 and bqy == 0) break;
                            const cx = bqx + qx3;
                            const cy = bqy + qy3;
                            if (@abs(cx) > 2 or @abs(cy) > 2) continue;
                            if (@abs(cx) != 1 and @abs(cy) != 1) continue; // halves already tested
                            mcBlockQ(prev, ctx.mcH, ctx.mcV, ctx.mcD, pw, ph, ox_i, oy_i, cx, cy, &hp);
                            const s2 = sadBlock(ctx.block_src[0..64], &hp, 8, ctx.opts.fast_sad);
                            if (s2 < hb) {
                                hb = s2;
                                bqx = cx;
                                bqy = cy;
                            }
                        }
                    }
                    if (bqx != 0 or bqy != 0) {
                        subpel = @intCast((bqx + 2) * 5 + (bqy + 2));
                        best = hb;
                        mcBlockQ(prev, ctx.mcH, ctx.mcV, ctx.mcD, pw, ph, ox_i, oy_i, bqx, bqy, &pred);
                    }
                } else if (halfpel) {
                    // half-pel refinement around the integer MV (v0.5 legacy:
                    // bilinear; byte-exact when the qpel gene is off)
                    var hb: u64 = best;
                    var bhx: i32 = 0;
                    var bhy: i32 = 0;
                    var hp: [64]u8 = undefined;
                    var hy2: i32 = -1;
                    while (hy2 <= 1) : (hy2 += 1) {
                        var hx2: i32 = -1;
                        while (hx2 <= 1) : (hx2 += 1) {
                            if (hx2 == 0 and hy2 == 0) continue;
                            interpBlock(prev, pw, ph, ox_i, oy_i, hx2, hy2, &hp);
                            const s2 = sadBlock(ctx.block_src[0..64], &hp, 8, ctx.opts.fast_sad);
                            if (s2 < hb) {
                                hb = s2;
                                bhx = hx2;
                                bhy = hy2;
                            }
                        }
                    }
                    if (bhx != 0 or bhy != 0) {
                        subpel = @intCast((bhx + 1) * 3 + (bhy + 1));
                        best = hb;
                        interpBlock(prev, pw, ph, ox_i, oy_i, bhx, bhy, &pred);
                    }
                }
                if (perpx < skip_th) {
                    w.marker(1); // skip: cur already == prev copy
                } else {
                    if (subpel != sp_center) {
                        w.marker(2); // inter with sub-pel refinement
                    } else {
                        w.marker(0);
                    }
                    w.mv(bdx, bdy);
                    if (subpel != sp_center) w.subpel(subpel, sp_bits);
                    if (subpel == sp_center) {
                        var r3: usize = 0;
                        while (r3 < 8) : (r3 += 1) {
                            const prow = prev[@as(usize, @intCast(oy_i + @as(i32, @intCast(r3)))) * pw + @as(usize, @intCast(ox_i)) ..][0..8];
                            @memcpy(pred[r3 * 8 ..][0..8], prow);
                        }
                    }
                    // residual = src - pred, offset by 128 for DCT
                    var res: [64]u8 = undefined;
                    for (0..64) |k| {
                        const d: i32 = @as(i32, ctx.block_src[k]) - @as(i32, pred[k]);
                        res[k] = @intCast(std.math.clamp(d + 128, 0, 255));
                    }
                    var lv: [64]i32 = undefined;
                    quantizeBlock(ctx, res[0..64], qp, pq_scale, rc, &lv);
                    var last: usize = 0;
                    for (0..64) |k| {
                        if (lv[k] != 0) last = k;
                    }
                    w.levels(lv[0..], last);
                    // reconstruct: pred + idct(dequant(residual))
                    var deq: [64]f32 = undefined;
                    dequantLevels(ctx, &lv, qp, pq_scale, rc, &deq);
                    var rec: [64]u8 = undefined;
                    idct8(&deq, rec[0..64], 8, &ctx.idct_calls);
                    const dst = enc[sy * pw + sx ..];
                    for (0..8) |rr| {
                        for (0..8) |cc| {
                            const v: i32 = @as(i32, pred[rr * 8 + cc]) + @as(i32, rec[rr * 8 + cc]) - 128;
                            dst[rr * pw + cc] = @intCast(std.math.clamp(v, 0, 255));
                        }
                    }
                    if (ctx.debug_px and fi == 2 and !chroma) {
                        var worst: i32 = 0;
                        for (0..8) |rr| {
                            for (0..8) |cc| {
                                const dv: i32 = @as(i32, dst[rr * pw + cc]) - @as(i32, ctx.block_src[rr * 8 + cc]);
                                if (@abs(dv) > @abs(worst)) worst = dv;
                            }
                        }
                        if (@abs(worst) > 2) {
                            std.debug.print("P2 blk({d},{d}) mv=({d},{d}) worst_delta={d} skip_sad_pp={d:.2}\n", .{ bx, by, bdx, bdy, worst, perpx });
                        }
                    }
                    if (ctx.debug_px and fi == 1 and sx == 0 and sy == 0 and !chroma) {
                        std.debug.print("INTER blk(0,0) mv=({d},{d})\n src: {any}\n pred: {any}\n res:  {any}\n rec:  {any}\n recon:{any}\n", .{
                            bdx,                 bdy,
                            ctx.block_src[0..8], pred[0..8],
                            res[0..8],           rec[0..8],
                            dst[0..8],
                        });
                    }
                }
            }

            // ---- v0.8 sb-end: keep unified only if it wins RD --------------
            if (sb_pend) |pd| {
                if (by == pd.sy0 + 1 and bx == pd.sx0 + 1) {
                    var err_a: u64 = 0;
                    var sr4: usize = 0;
                    while (sr4 < 16) : (sr4 += 1) {
                        const srow = src[src_base + (pd.sy0 * 8 + sr4) * pw + pd.sx0 * 8 ..][0..16];
                        const erow = enc[(pd.sy0 * 8 + sr4) * pw + pd.sx0 * 8 ..][0..16];
                        for (0..16) |sc| {
                            const dv: i32 = @as(i32, srow[sc]) - @as(i32, erow[sc]);
                            err_a += @as(u64, @intCast(dv * dv));
                        }
                    }
                    const rate_a = w.written() - pd.rate0;
                    const lam: f32 = 0.85 * qp * qp * (0.5 + (gen.sb16Gene(g) - 0.5) * 2.0);
                    const cost_a = @as(f64, @floatFromInt(err_a)) + @as(f64, lam) * 8.0 * @as(f64, @floatFromInt(rate_a));
                    const cost_b = @as(f64, @floatFromInt(pd.err_b)) + @as(f64, lam) * 8.0 * @as(f64, @floatFromInt(pd.rate_b));
                    if (cost_b < cost_a) {
                        // roll back the legacy sb and commit the unified one
                        SbSnap.restore(&w, pd.s0, &mbacc, &mbn, &mmap_n);
                        var sr5: usize = 0;
                        while (sr5 < 16) : (sr5 += 1) {
                            @memcpy(enc[(pd.sy0 * 8 + sr5) * pw + pd.sx0 * 8 ..][0..16], pd.recon0[sr5 * 16 ..][0..16]);
                        }
                        SbU(ctx, &w, src, src_base, enc, prev, pw, ph, is_i, chroma, qp, iq_scale, pq_scale, ctx.cur_gop, pd.sx0 * 8, pd.sy0 * 8, ctx.opts.fast_sad);
                        bx += 1; // skip the sb's 2nd column (loop ++ lands on the next sb)
                        sb_pend = null;
                        continue;
                    }
                    sb_pend = null;
                }
            }
        }
    }

    // ---- plane framing: [mode map (deterministic length)][block data] ----
    if (mwidth > 0) {
        const map_len = (nbx * nby * @as(usize, mwidth) + 7) / 8;
        for (mmap[0..map_len]) |b| ctx.bw.put(b); // zero-padded tail included
    }
    w.finish();
    for (ctx.scratch[0..w.written()]) |b| ctx.bw.put(b);
}

fn sadBlock(a: *const [64]u8, b: []const u8, stride: usize, fast: bool) u64 {
    var acc: u64 = 0;
    if (fast) {
        var r: usize = 0;
        while (r < 8) : (r += 2) {
            var c: usize = 0;
            while (c < 8) : (c += 2) {
                const d: i32 = @as(i32, a[r * 8 + c]) - @as(i32, b[r * stride + c]);
                acc += @abs(d);
            }
        }
        return acc * 2; // compensate 4x sampling
    }
    for (0..8) |r| {
        for (0..8) |c| {
            const d: i32 = @as(i32, a[r * 8 + c]) - @as(i32, b[r * stride + c]);
            acc += @abs(d);
        }
    }
    return acc;
}

// --------------------------------------------------------------- decode frame

fn decodeFrame(ctx: *Ctx, curY: []u8, curU: []u8, curV: []u8, prevY: []const u8, prevU: []const u8, prevV: []const u8) !void {
    const g = ctx.g;
    const clip = ctx.clip;
    ctx.dec_cur_y = curY;
    const ftype = try ctx.br.getU8();
    const qp: f32 = @floatFromInt(try ctx.br.getU8());
    const is_i = ftype == 1;
    const refresh = gen.refreshEvery(g);
    const key_int = gen.keyInt(g);
    // identical GOP-position derivation as the encoder — regulation contexts
    // are decoder-derivable, so mirrored regulation costs zero side info
    ctx.cur_gop = @as(f32, @floatFromInt(ctx.dec_fi % key_int)) / @as(f32, @floatFromInt(key_int));

    try decodePlane(ctx, is_i, qp, curY, prevY, clip.w, clip.h, false, refresh);
    try decodePlane(ctx, is_i, qp, curU, prevU, clip.w / 2, clip.h / 2, true, refresh);
    try decodePlane(ctx, is_i, qp, curV, prevV, clip.w / 2, clip.h / 2, true, refresh);

    // v0.4 in-loop deblocking + v0.5 CDEF-lite — mirrors encodeFrame exactly:
    // same planes, same frame qp, same filters. The filtered frame is the
    // stored output AND the next frame's reference on both sides.
    deblockFrame(g, curY, curU, curV, clip.w, clip.h, qp);
    cdefFrame(g, curY, curU, curV, clip.w, clip.h, qp, ctx.cdef_buf);
}

fn decodePlane(
    ctx: *Ctx,
    is_i: bool,
    qp: f32,
    cur: []u8,
    prev: []const u8,
    pw: u32,
    ph: u32,
    chroma: bool,
    refresh: u32,
) !void {
    // v0.5 entropy gene: comptime-specialized mirror of encodePlane's choice.
    if (gen.entropyGene(ctx.g) > 0.5) {
        return decodePlaneT(ctx, is_i, qp, cur, prev, pw, ph, chroma, refresh, true);
    }
    return decodePlaneT(ctx, is_i, qp, cur, prev, pw, ph, chroma, refresh, false);
}

fn decodePlaneT(
    ctx: *Ctx,
    is_i: bool,
    qp: f32,
    cur: []u8,
    prev: []const u8,
    pw: u32,
    ph: u32,
    chroma: bool,
    refresh: u32,
    comptime ac_on: bool,
) !void {
    const g = ctx.g;
    const cqp_scale = gen.chromaScale(g);
    const iq_scale: f32 = if (chroma) cqp_scale else 1.0;
    const pq_scale: f32 = if (chroma) gen.pQmul(g) * cqp_scale else gen.pQmul(g);
    const nbx: usize = pw / 8;
    const nby: usize = ph / 8;
    const rrow: usize = @intCast((ctx.dec_fi / refresh) % @max(1, nby));
    const do_refresh = !is_i and !chroma and (ctx.dec_fi / refresh) > 0;
    // v0.5b: decoder mirrors the encoder's half-plane build (same reference
    // plane, same deterministic filter — cannot desync).
    const qpel = gen.qpelOn(g);
    if (qpel and !is_i) {
        buildHalfPlanes(prev, pw, ph, ctx.mcH, ctx.mcV, ctx.mcD);
    }
    // CFL reads the co-located luma recon — pre-deblock on BOTH sides.
    const cfl_luma: ?[]const u8 = if (chroma) ctx.dec_cur_y else null;
    const cfl_lpw: usize = ctx.clip.w;

    // v0.4: the plane's intra mode map precedes the block data — read it once
    // (deterministic length), then decode blocks against it.
    const modes = intraModes(g, chroma);
    const mwidth: u5 = intraModeBits(modes.len);
    var mmap: [1024]u8 = undefined;
    var map_br = BR{ .buf = mmap[0..0] };
    if (mwidth > 0) {
        const map_len = (nbx * nby * @as(usize, mwidth) + 7) / 8;
        for (0..map_len) |mi| mmap[mi] = try ctx.br.getU8();
        map_br = .{ .buf = mmap[0..map_len] };
    }
    // v0.5: the block stream is either byte varints (legacy) or the adaptive
    // arithmetic coder; both start right after the mode map, byte-aligned.
    var r = try BlockR(ac_on).init(&ctx.br);

    // v0.8: columns of an odd block row already covered by a unified 16x16
    // superblock decoded in the even row above (skipped, no syntax there).
    const sb16_on = gen.sb16On(g);
    if (sb16_on and nbx > 256) return error.PlaneTooWide;
    var skipmap: [256]bool = @splat(false);

    var by: usize = 0;
    while (by < nby) : (by += 1) {
        const by_n: f32 = (@as(f32, @floatFromInt(by)) + 0.5) / @as(f32, @floatFromInt(nby));
        // v0.8: fresh even row — stale coverage from the previous odd row is gone
        if (sb16_on and (by % 2) == 0) {
            for (0..nbx) |ci| skipmap[ci] = false;
        }
        var bx: usize = 0;
        while (bx < nbx) : (bx += 1) {
            const sx = bx * 8;
            const sy = by * 8;
            // v0.8: this block belongs to a unified superblock from the row
            // above — its pixels are already decoded, no syntax to consume.
            if (sb16_on and (by % 2) == 1 and skipmap[bx]) {
                continue;
            }
            // v0.8 sb-start: full aligned non-mixed superblocks carry one
            // wide marker — 3 = unified (subtype 0 intra16 / 1 skip16 /
            // 2 inter16), 0 = legacy 4-block path follows.
            const sb_full = (by % 2 == 0) and (bx % 2 == 0) and (by + 2 <= nby) and (bx + 2 <= nbx);
            const sb_mixed = !is_i and do_refresh and (by == rrow or by + 1 == rrow);
            if (sb16_on and sb_full and !sb_mixed) {
                const flag = try r.markerSB(true);
                if (flag == 3) {
                    const sub = try r.markerSB(false);
                    const by_n_v: f32 = by_n; // top row of the sb == current row
                    if (sub == 0) {
                        // unified intra16: DC pred + big TX, no mode-map bits
                        const dc = dcPred16(cur, pw, sx, sy);
                        const pred: [256]u8 = @splat(dc);
                        const rc = gen.RegCtx{ .mv_n = 0, .by_n = by_n_v, .gop = ctx.cur_gop, .intra = true };
                        var coef: [256]f32 = @splat(0);
                        try r.levels16(g, qp, iq_scale, rc, &coef);
                        var rec: [256]u8 = undefined;
                        idct16(&coef, rec[0..], 16, &ctx.idct_calls);
                        const dst = cur[sy * pw + sx ..];
                        for (0..16) |rr| {
                            for (0..16) |cc| {
                                const v: i32 = @as(i32, pred[rr * 16 + cc]) + @as(i32, rec[rr * 16 + cc]) - 128;
                                dst[rr * pw + cc] = @intCast(std.math.clamp(v, 0, 255));
                            }
                        }
                    } else {
                        if (sub > 2) return error.Corrupt;
                        const mv2 = try r.mvPair();
                        const dx = mv2[0];
                        const dy = mv2[1];
                        const rc = gen.RegCtx{
                            .mv_n = @min(1.0, (@as(f32, @floatFromInt(@abs(dx))) + @as(f32, @floatFromInt(@abs(dy)))) / 8.0),
                            .by_n = by_n_v,
                            .gop = ctx.cur_gop,
                            .intra = false,
                        };
                        const ox_i: i32 = @as(i32, @intCast(sx)) + dx;
                        const oy_i: i32 = @as(i32, @intCast(sy)) + dy;
                        if (sub == 1) {
                            // skip16: whole sb copied from the reference
                            const dst = cur[sy * pw + sx ..];
                            for (0..16) |rr| {
                                @memcpy(dst[rr * pw ..][0..16], prev[@as(usize, @intCast(oy_i + @as(i32, @intCast(rr)))) * pw + @as(usize, @intCast(ox_i)) ..][0..16]);
                            }
                        } else {
                            // inter16: one MV + 16x16 TX residual
                            var pred: [256]u8 = undefined;
                            for (0..16) |rr| {
                                @memcpy(pred[rr * 16 ..][0..16], prev[@as(usize, @intCast(oy_i + @as(i32, @intCast(rr)))) * pw + @as(usize, @intCast(ox_i)) ..][0..16]);
                            }
                            var coef: [256]f32 = @splat(0);
                            try r.levels16(g, qp, pq_scale, rc, &coef);
                            var rec: [256]u8 = undefined;
                            idct16(&coef, rec[0..], 16, &ctx.idct_calls);
                            const dst = cur[sy * pw + sx ..];
                            for (0..16) |rr| {
                                for (0..16) |cc| {
                                    const v: i32 = @as(i32, pred[rr * 16 + cc]) + @as(i32, rec[rr * 16 + cc]) - 128;
                                    dst[rr * pw + cc] = @intCast(std.math.clamp(v, 0, 255));
                                }
                            }
                        }
                    }
                    // mark the odd-row columns as covered, skip the 2nd column
                    skipmap[bx] = true;
                    skipmap[bx + 1] = true;
                    bx += 1;
                    continue;
                } else if (flag != 0) {
                    return error.Corrupt;
                }
                // flag == 0: legacy superblock — fall through to per-block
            }
            const force_intra = is_i or (do_refresh and by == rrow);
            var rc = gen.RegCtx{
                .mv_n = 0,
                .by_n = by_n,
                .gop = ctx.cur_gop,
                .intra = force_intra,
            };

            if (force_intra) {
                if (!is_i) _ = try r.marker(); // intra-in-P marker
                if (modes.len == 1) {
                    // legacy: no mode byte, raw-DCT recon
                    var coef: [64]f32 = @splat(0);
                    try r.levels(g, qp, iq_scale, rc, &coef);
                    idct8(&coef, cur[sy * pw + sx ..], pw, &ctx.idct_calls);
                } else {
                    // v0.4: mode index from the plane's bit-packed map (1-4
                    // bits), prediction from the decoder's own recon plane
                    // (identical availability, identical pixels).
                    const midx = try map_br.getBits(mwidth);
                    if (midx >= modes.len) return error.Corrupt;
                    const mode = modes[midx];
                    var pred: [64]u8 = undefined;
                    intraPredict(mode, cur, pw, ph, sx, sy, &pred, cfl_luma, cfl_lpw);
                    var coef: [64]f32 = @splat(0);
                    try r.levels(g, qp, iq_scale, rc, &coef);
                    var rec: [64]u8 = undefined;
                    idct8(&coef, rec[0..64], 8, &ctx.idct_calls);
                    const dst = cur[sy * pw + sx ..];
                    for (0..8) |rr| {
                        for (0..8) |cc| {
                            const v: i32 = @as(i32, pred[rr * 8 + cc]) + @as(i32, rec[rr * 8 + cc]) - 128;
                            dst[rr * pw + cc] = @intCast(std.math.clamp(v, 0, 255));
                        }
                    }
                }
            } else {
                const flags = try r.marker();
                if (flags == 1) {
                    // skip: cur already copied from prev
                } else {
                    const mv2 = try r.mvPair();
                    const dx = mv2[0];
                    const dy = mv2[1];
                    rc.mv_n = @min(1.0, (@as(f32, @floatFromInt(@abs(dx))) + @as(f32, @floatFromInt(@abs(dy)))) / 8.0);
                    const ox_i: i32 = @as(i32, @intCast(sx)) + @as(i32, @intCast(dx));
                    const oy_i: i32 = @as(i32, @intCast(sy)) + @as(i32, @intCast(dy));
                    var pred: [64]u8 = undefined;
                    if (flags == 2) {
                        if (gen.qpelOn(g)) {
                            // v0.5b: 5-bit quarter lattice code (qx+2)*5+(qy+2)
                            const code = try r.subpel(5);
                            if (code >= 25) return error.Corrupt;
                            const qx = @as(i32, code / 5) - 2;
                            const qy = @as(i32, code % 5) - 2;
                            mcBlockQ(prev, ctx.mcH, ctx.mcV, ctx.mcD, pw, ph, ox_i, oy_i, qx, qy, &pred);
                        } else {
                            const code = try r.subpel(4);
                            if (code >= 9) return error.Corrupt;
                            const hx = @as(i32, code / 3) - 1;
                            const hy = @as(i32, code % 3) - 1;
                            interpBlock(prev, pw, ph, ox_i, oy_i, hx, hy, &pred);
                        }
                    } else {
                        var r2: usize = 0;
                        while (r2 < 8) : (r2 += 1) {
                            @memcpy(pred[r2 * 8 ..][0..8], prev[@as(usize, @intCast(oy_i + @as(i32, @intCast(r2)))) * pw + @as(usize, @intCast(ox_i)) ..][0..8]);
                        }
                    }
                    var coef: [64]f32 = @splat(0);
                    try r.levels(g, qp, pq_scale, rc, &coef);
                    var rec: [64]u8 = undefined;
                    idct8(&coef, rec[0..64], 8, &ctx.idct_calls);
                    const dst = cur[sy * pw + sx ..];
                    for (0..8) |rr| {
                        for (0..8) |cc| {
                            const v: i32 = @as(i32, pred[rr * 8 + cc]) + @as(i32, rec[rr * 8 + cc]) - 128;
                            dst[rr * pw + cc] = @intCast(std.math.clamp(v, 0, 255));
                        }
                    }
                }
            }
        }
    }
}

// --------------------------------------------------------------- public API

pub fn evalClip(
    alloc: std.mem.Allocator,
    io: std.Io,
    clip: *const yuv.Clip,
    g: *const gen.Genome,
    opts: EvalOpts,
) !ClipStats {
    initDct();
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const p1Y = try a.alloc(u8, clip.ysz);
    const p1U = try a.alloc(u8, clip.csz);
    const p1V = try a.alloc(u8, clip.csz);
    const p2Y = try a.alloc(u8, clip.ysz);
    const p2U = try a.alloc(u8, clip.csz);
    const p2V = try a.alloc(u8, clip.csz);
    @memset(p1Y, 128);
    @memset(p1U, 128);
    @memset(p1V, 128);
    @memset(p2Y, 128);
    @memset(p2U, 128);
    @memset(p2V, 128);

    const decY = try a.alloc(u8, @as(usize, clip.frames) * clip.ysz);
    const decU = try a.alloc(u8, @as(usize, clip.frames) * clip.csz);
    const decV = try a.alloc(u8, @as(usize, clip.frames) * clip.csz);
    const bitbuf = try a.alloc(u8, 8 * 1024 * 1024);

    var ctx = Ctx{
        .clip = clip,
        .g = g,
        .opts = opts,
        .debug_px = g.id >= 900000,
        .encY = p1Y,
        .encU = p1U,
        .encV = p1V,
        .prevY = p2Y,
        .prevU = p2U,
        .prevV = p2V,
        .decY = decY,
        .decU = decU,
        .decV = decV,
        .bw = .{ .buf = bitbuf },
        .br = .{ .buf = "" },
        .scratch = try a.alloc(u8, 1 << 20),
        .cdef_buf = try a.alloc(u8, clip.ysz),
        .mcH = try a.alloc(u8, clip.ysz),
        .mcV = try a.alloc(u8, clip.ysz),
        .mcD = try a.alloc(u8, clip.ysz),
    };

    const t0 = std.Io.Clock.now(.awake, io);
    for (0..clip.frames) |fi| {
        const fb_start = ctx.bw.n;
        try encodeFrame(&ctx, @intCast(fi));
        ctx.last_frame_bytes = ctx.bw.n - fb_start;
    }
    const t1 = std.Io.Clock.now(.awake, io);
    const enc_ns: i96 = t1.nanoseconds - t0.nanoseconds;
    const bitstream = bitbuf[0..ctx.bw.n];

    // ---------------- decode (independent path; PSNR measured here) --------
    ctx.br = .{ .buf = bitstream };
    ctx.dec_fi = 0;

    var cy = p1Y;
    var cu = p1U;
    var cv = p1V;
    var py = p2Y;
    var pu = p2U;
    var pv = p2V;
    for (0..clip.frames) |fi| {
        @memset(cy, 128);
        @memset(cu, 128);
        @memset(cv, 128);
        // start from previous decoded frame (skip blocks copy)
        @memcpy(cy, py);
        @memcpy(cu, pu);
        @memcpy(cv, pv);
        ctx.dec_fi = @intCast(fi);
        try decodeFrame(&ctx, cy, cu, cv, py, pu, pv);
        @memcpy(decY[@as(usize, fi) * clip.ysz ..][0..clip.ysz], cy);
        @memcpy(decU[@as(usize, fi) * clip.csz ..][0..clip.csz], cu);
        @memcpy(decV[@as(usize, fi) * clip.csz ..][0..clip.csz], cv);
        const ty = py;
        const tu = pu;
        const tv = pv;
        py = cy;
        pu = cu;
        pv = cv;
        cy = ty;
        cu = tu;
        cv = tv;
    }

    var acc: f32 = 0;
    var acc_u: f32 = 0;
    var acc_v: f32 = 0;
    var acc_ms: f32 = 0;
    for (0..clip.frames) |fi| {
        const s = clip.frameY(@intCast(fi));
        const d = decY[@as(usize, fi) * clip.ysz ..][0..clip.ysz];
        acc += yuv.psnrPlane(s, d);
        acc_u += yuv.psnrPlane(clip.frameU(@intCast(fi)), decU[@as(usize, fi) * clip.csz ..][0..clip.csz]);
        acc_v += yuv.psnrPlane(clip.frameV(@intCast(fi)), decV[@as(usize, fi) * clip.csz ..][0..clip.csz]);
        acc_ms += try msssim.planeMsssim(alloc, s, d, clip.w, clip.h);
    }
    const nframes = @as(f32, @floatFromInt(clip.frames));
    const mean_psnr = acc / nframes;

    if (opts.dump_recon) |rd_dir| {
        std.Io.Dir.cwd().createDirPath(io, rd_dir) catch {};
        const rp = try std.fmt.allocPrint(alloc, "{s}/{s}.recon.yuv", .{ rd_dir, clip.name });
        const rf = try std.Io.Dir.cwd().createFile(io, rp, .{});
        defer rf.close(io);
        try rf.writeStreamingAll(io, decY);
        try rf.writeStreamingAll(io, decU);
        try rf.writeStreamingAll(io, decV);
    }

    return .{
        .bytes = bitstream.len,
        .psnr_y = mean_psnr,
        .psnr_u = acc_u / nframes,
        .psnr_v = acc_v / nframes,
        .msssim_y = acc_ms / nframes,
        .enc_ms = @as(f32, @floatFromInt(enc_ns)) / 1e6,
        .enc_mops = @as(f32, @floatFromInt(ctx.dct_calls + ctx.idct_calls)) * 64.0 / 1e6,
        .dec_mops = @as(f32, @floatFromInt(ctx.idct_calls)) * 64.0 / 1e6,
    };
}

// --------------------------------------------------------------- debug: interleave encode/decode per frame and diff
pub const DebugReport = struct {
    frame: u32,
    enc_y_psnr: f32,
    dec_y_psnr: f32,
    first_bad_block: i32, // -1 = none
    max_delta: u32,
};

pub fn debugRoundtrip(alloc: std.mem.Allocator, clip: *const yuv.Clip, g: *const gen.Genome, opts: EvalOpts, out: *std.ArrayList(DebugReport), alloc2: std.mem.Allocator) !void {
    initDct();
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const p1Y = try a.alloc(u8, clip.ysz);
    const p2Y = try a.alloc(u8, clip.ysz);
    const p1U = try a.alloc(u8, clip.csz);
    const p2U = try a.alloc(u8, clip.csz);
    const p1V = try a.alloc(u8, clip.csz);
    const p2V = try a.alloc(u8, clip.csz);
    @memset(p1Y, 128);
    @memset(p2Y, 128);
    @memset(p1U, 128);
    @memset(p2U, 128);
    @memset(p1V, 128);
    @memset(p2V, 128);

    const decY = try a.alloc(u8, @as(usize, clip.frames) * clip.ysz);
    const bitbuf = try a.alloc(u8, 8 * 1024 * 1024);

    var ctx = Ctx{
        .clip = clip,
        .g = g,
        .opts = opts,
        .debug_px = g.id >= 900000,
        .encY = p1Y,
        .encU = p1U,
        .encV = p1V,
        .prevY = p2Y,
        .prevU = p2U,
        .prevV = p2V,
        .decY = decY,
        .decU = decY,
        .decV = decY,
        .bw = .{ .buf = bitbuf },
        .br = .{ .buf = "" },
        .scratch = try a.alloc(u8, 1 << 20),
        .cdef_buf = try a.alloc(u8, clip.ysz),
        .mcH = try a.alloc(u8, clip.ysz),
        .mcV = try a.alloc(u8, clip.ysz),
        .mcD = try a.alloc(u8, clip.ysz),
    };

    var cy = p1Y;
    var cu = p1U;
    var cv = p1V;
    var py = p2Y;
    var pu = p2U;
    var pv = p2V;

    for (0..clip.frames) |fi| {
        const fb_start = ctx.bw.n;
        try encodeFrame(&ctx, @intCast(fi));
        // encoder recon for frame fi is now in ctx.prevY
        // decode this frame from its slice
        const frame_bits = bitbuf[fb_start..ctx.bw.n];
        var dctx = ctx; // copy counters
        dctx.br = .{ .buf = frame_bits };
        dctx.dec_fi = @intCast(fi);
        @memcpy(cy, py);
        @memcpy(cu, pu);
        @memcpy(cv, pv);
        try decodeFrame(&dctx, cy, cu, cv, py, pu, pv);
        ctx.idct_calls = dctx.idct_calls;
        // compare cy (decoder) vs ctx.prevY (encoder recon)
        var bad: i32 = -1;
        var maxd: u32 = 0;
        for (0..clip.ysz) |i| {
            const d: u32 = @abs(@as(i32, cy[i]) - @as(i32, ctx.prevY[i]));
            if (d > maxd) maxd = d;
            if (d > 0 and bad < 0) bad = @intCast(i);
        }
        const src = clip.frameY(@intCast(fi));
        const enc_p = yuv.psnrPlane(src, ctx.prevY);
        const dec_p = yuv.psnrPlane(src, cy);
        try out.append(alloc2, .{ .frame = @intCast(fi), .enc_y_psnr = enc_p, .dec_y_psnr = dec_p, .first_bad_block = bad, .max_delta = maxd });
        // advance decoder-side pointers to mirror evalClip
        const t = py;
        py = cy;
        cy = t;
        const tu = pu;
        pu = cu;
        cu = tu;
        const tv = pv;
        pv = cv;
        cv = tv;
    }
}

// ---------------------------------------------------------------- v0.4 tests

// Deterministic synthetic clip: smooth gradient + a moving block (motion) +
// hard rectangles (block edges for the deblocker to chew on).
fn synthClip(alloc: std.mem.Allocator, w: u32, h: u32, frames: u32) !yuv.Clip {
    const ysz: usize = @as(usize, w) * h;
    const csz: usize = ysz / 4;
    const y = try alloc.alloc(u8, @as(usize, frames) * ysz);
    const u = try alloc.alloc(u8, @as(usize, frames) * csz);
    const v = try alloc.alloc(u8, @as(usize, frames) * csz);
    for (0..frames) |fi| {
        const fy = y[@as(usize, fi) * ysz ..][0..ysz];
        for (0..h) |r| {
            for (0..w) |c| {
                // slow diagonal drift each frame + gradient + box
                const dx: i32 = @intCast((c + fi * 2) % w);
                const dy: i32 = @intCast((r + fi) % h);
                var px: i32 = @divTrunc(@divTrunc(dx * 255, @as(i32, @intCast(w))) + @divTrunc(dy * 255, @as(i32, @intCast(h))), 2);
                if (dx >= 6 and dx < 22 and dy >= 6 and dy < 22) px = 220; // hard box
                if (dx >= 24 and dx < 30 and dy >= 4 and dy < 10) px = 30; // second box
                fy[r * w + c] = @intCast(std.math.clamp(px, 0, 255));
            }
        }
        @memset(u[@as(usize, fi) * csz ..][0..csz], 100);
        @memset(v[@as(usize, fi) * csz ..][0..csz], 150);
    }
    return .{
        .name = "synth",
        .w = w,
        .h = h,
        .frames = frames,
        .fps = 24,
        .ysz = ysz,
        .csz = csz,
        .y = y,
        .u = u,
        .v = v,
    };
}

fn genomeWith(id: u64, intra: f32, deb: f32) gen.Genome {
    var g = gen.Genome{ .id = id, .gen = 0, .pa = 0, .pb = 0, .tribe = 0, .g = @splat(0.5) };
    g.g[3] = 0.18; // fine baseq: sharp recon for the roundtrip floor
    g.g[16] = intra;
    g.g[17] = deb;
    return g;
}

fn genomeWithV5(id: u64, intra: f32, deb: f32, entropy: f32, cfl: f32, cdef: f32) gen.Genome {
    var g = genomeWith(id, intra, deb);
    g.g[18] = entropy;
    g.g[19] = cfl;
    g.g[20] = cdef;
    return g;
}

fn genomeWithV5b(id: u64, intra: f32, deb: f32, entropy: f32, cfl: f32, cdef: f32, qpel: f32) gen.Genome {
    var g = genomeWithV5(id, intra, deb, entropy, cfl, cdef);
    g.g[21] = qpel;
    return g;
}

// THE v0.4 invariant: with prediction and/or deblocking enabled, the decoder
// output must remain byte-exact equal to the encoder recon (closed loop),
// frame by frame, on every plane. Any drift here is a desync bug.
test "v0.4 closed loop holds with intra prediction and deblocking on" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 32, 32, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    const variants = [_]gen.Genome{
        genomeWith(1, 0.0, 0.0), // legacy exact
        genomeWith(2, 0.9, 0.0), // full intra prediction
        genomeWith(3, 0.0, 0.6), // deblocking only
        genomeWith(4, 0.9, 0.6), // both
        genomeWith(5, 0.4, 0.3), // DC-only set + mild deblock
    };
    for (&variants) |*g| {
        var reports = std.ArrayList(DebugReport).empty;
        defer reports.deinit(alloc);
        try debugRoundtrip(alloc, &clip, g, .{}, &reports, alloc);
        try std.testing.expectEqual(@as(usize, 4), reports.items.len);
        for (reports.items) |r| {
            try std.testing.expectEqual(@as(i32, -1), r.first_bad_block);
            try std.testing.expectEqual(@as(u32, 0), r.max_delta);
            try std.testing.expect(r.enc_y_psnr > 9.0); // crude default genes; floor sanity only
        }
    }
}

// THE v0.5 invariant: entropy coder, CFL, CDEF, and the smooth/PAETH modes
// must all hold the closed loop (enc recon == dec output, byte-exact) with
// every combination of the new features — including all-on.
test "v0.5 closed loop holds with entropy, CFL, CDEF, smooth/PAETH on" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 64, 64, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    const variants = [_]gen.Genome{
        genomeWithV5(21, 0.95, 0.6, 1.0, 0.0, 0.0), // AC stream only
        genomeWithV5(22, 0.95, 0.6, 0.0, 1.0, 0.0), // CFL only
        genomeWithV5(23, 0.95, 0.6, 0.0, 0.0, 1.0), // CDEF only
        genomeWithV5(24, 0.30, 0.0, 1.0, 1.0, 0.0), // legacy intra + AC + CFL
        genomeWithV5(25, 0.95, 0.6, 1.0, 1.0, 1.0), // everything on
    };
    for (&variants) |*g| {
        var reports = std.ArrayList(DebugReport).empty;
        defer reports.deinit(alloc);
        try debugRoundtrip(alloc, &clip, g, .{}, &reports, alloc);
        try std.testing.expectEqual(@as(usize, 4), reports.items.len);
        for (reports.items) |r| {
            try std.testing.expectEqual(@as(i32, -1), r.first_bad_block);
            try std.testing.expectEqual(@as(u32, 0), r.max_delta);
            try std.testing.expect(r.enc_y_psnr > 9.0);
        }
    }
}

// The v0.5 migration invariant: v0.4 genomes (new genes at 0) measure
// byte-exactly the same with the v0.5 binary present — the arena's fitness
// floor stays comparable across the upgrade.
test "v0.5 genes at 0 reproduce v0.4 metrics exactly" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 32, 32, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    var a = genomeWith(10, 0.9, 0.6);
    var b = genomeWithV5(10, 0.9, 0.6, 0.0, 0.0, 0.0);
    var ra = std.ArrayList(DebugReport).empty;
    defer ra.deinit(alloc);
    var rb = std.ArrayList(DebugReport).empty;
    defer rb.deinit(alloc);
    try debugRoundtrip(alloc, &clip, &a, .{}, &ra, alloc);
    try debugRoundtrip(alloc, &clip, &b, .{}, &rb, alloc);
    for (ra.items, rb.items) |x, yv| {
        try std.testing.expectEqual(x.enc_y_psnr, yv.enc_y_psnr);
        try std.testing.expectEqual(x.max_delta, yv.max_delta);
    }
}

// THE v0.5b invariant: quarter-pel MC must hold the closed loop
// (enc recon == dec output, byte-exact) across its operating envelope —
// qpel-only, qpel+AC, qpel+halfpel gene (qpel supersedes), and all-on.
test "v0.5b closed loop holds with quarter-pel MC on" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 64, 64, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    const variants = [_]gen.Genome{
        genomeWithV5b(31, 0.95, 0.6, 0.0, 0.0, 0.0, 1.0), // qpel only
        genomeWithV5b(32, 0.95, 0.6, 1.0, 0.0, 0.0, 1.0), // qpel + AC stream
        genomeWithV5b(33, 0.95, 0.6, 1.0, 1.0, 1.0, 1.0), // everything on
        genomeWithV5b(34, 0.95, 0.0, 1.0, 1.0, 1.0, 1.0), // qpel + AC, deblock off
        genomeWithV5b(35, 0.30, 0.6, 1.0, 1.0, 0.0, 0.8), // legacy intra + qpel
    };
    for (&variants) |*g| {
        var reports = std.ArrayList(DebugReport).empty;
        defer reports.deinit(alloc);
        try debugRoundtrip(alloc, &clip, g, .{}, &reports, alloc);
        try std.testing.expectEqual(@as(usize, 4), reports.items.len);
        for (reports.items) |r| {
            try std.testing.expectEqual(@as(i32, -1), r.first_bad_block);
            try std.testing.expectEqual(@as(u32, 0), r.max_delta);
            try std.testing.expect(r.enc_y_psnr > 9.0);
        }
    }
}

// The v0.5b migration invariant: v0.5 genomes (qpel at 0) measure byte-exactly
// the same with the v0.5b binary — the fitness floor stays comparable.
test "v0.5b qpel gene at 0 reproduces v0.5 metrics exactly" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 32, 32, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    var a = genomeWithV5(11, 0.9, 0.6, 1.0, 1.0, 1.0);
    var b = genomeWithV5b(11, 0.9, 0.6, 1.0, 1.0, 1.0, 0.0);
    var ra = std.ArrayList(DebugReport).empty;
    defer ra.deinit(alloc);
    var rb = std.ArrayList(DebugReport).empty;
    defer rb.deinit(alloc);
    try debugRoundtrip(alloc, &clip, &a, .{}, &ra, alloc);
    try debugRoundtrip(alloc, &clip, &b, .{}, &rb, alloc);
    for (ra.items, rb.items) |x, yv| {
        try std.testing.expectEqual(x.enc_y_psnr, yv.enc_y_psnr);
        try std.testing.expectEqual(x.max_delta, yv.max_delta);
    }
}

// interpBlockQ geometry: integer position = integer copy; a half position
// on a flat plane is the flat value; quarter positions stay in [0,255] and
// bracket the integer sample on a ramp (monotone, no overshoot).
test "interpBlockQ geometry: flat, ramp, bounds" {
    var plane: [40 * 40]u8 = @splat(100);
    var out: [64]u8 = undefined;
    // integer == copy
    interpBlockQ(&plane, 40, 40, 8, 8, 0, 0, &out);
    for (out) |px| try std.testing.expectEqual(@as(u8, 100), px);
    // every half/quarter position on a flat plane is the flat value
    const offs = [_][2]i32{ .{ -2, -2 }, .{ -2, 0 }, .{ -2, 2 }, .{ 0, -2 }, .{ 0, 2 }, .{ 2, -2 }, .{ 2, 0 }, .{ 2, 2 }, .{ -1, -1 }, .{ -1, 0 }, .{ -1, 1 }, .{ 0, -1 }, .{ 0, 1 }, .{ 1, -1 }, .{ 1, 0 }, .{ 1, 1 } };
    for (offs) |o| {
        interpBlockQ(&plane, 40, 40, 8, 8, o[0], o[1], &out);
        for (out) |px| try std.testing.expectEqual(@as(u8, 100), px);
    }
    // horizontal ramp: half sample at +2 must sit strictly between the two
    // integer samples (4-tap Wiener on a linear ramp is the ramp value)
    var ramp: [40 * 40]u8 = undefined;
    for (0..40) |r| for (0..40) |c| {
        ramp[r * 40 + c] = @intCast(50 + c * 2);
    };
    interpBlockQ(&ramp, 40, 40, 8, 8, 2, 0, &out);
    for (0..8) |r| for (0..8) |c| {
        const want: u8 = @intCast(50 + (8 + c) * 2 + 1); // midpoint of the ramp step
        try std.testing.expectEqual(want, out[r * 8 + c]);
    };
}

// The AC engine: byte-exact roundtrip of the full symbol alphabet under
// adversarial probability drift — markers, MVs, subpel codes, (run,level)
// pairs, escapes. Any asymmetry between ACEnc and ACDec shows here.
test "adaptive entropy coder roundtrips symbol streams byte-exactly" {
    const alloc = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xC0DEC);
    const rnd = prng.random();
    var ps: Probs = @splat(PROB_INIT);
    var ps2: Probs = @splat(PROB_INIT);

    const buf = try alloc.alloc(u8, 1 << 16);
    defer alloc.free(buf);
    var ac = ACEnc{ .buf = buf };

    // encode a long randomized symbol sequence
    var ref_dx: [256]i32 = undefined;
    var ref_dy: [256]i32 = undefined;
    var ref_sub: [256]u8 = undefined;
    var ref_mark: [256]u8 = undefined;
    var ref_lv: [512]i32 = undefined;
    var n_lv: usize = 0;
    for (0..256) |i| {
        const m: u8 = @intCast(rnd.uintLessThan(u2, 3));
        ref_mark[i] = m;
        encMarker(&ac, &ps, m);
        if (m != 1) {
            const dx: i32 = @as(i32, rnd.intRangeAtMost(i8, -12, 12));
            const dy: i32 = @as(i32, rnd.intRangeAtMost(i8, -12, 12));
            ref_dx[i] = dx;
            ref_dy[i] = dy;
            encMV(&ac, &ps, dx);
            encMV(&ac, &ps, dy);
            if (m == 2 and i % 3 == 0) {
                // v0.5b: exercise both subpel widths — 4-bit legacy half codes
                // and 5-bit quarter codes, index-drifted identically both sides
                if (i % 6 == 0) {
                    const code: u8 = @intCast(rnd.uintLessThan(u4, 9));
                    ref_sub[i] = code;
                    encUBits(&ac, &ps, CX_SP_B0, 4, code);
                } else {
                    const code: u8 = @intCast(rnd.uintLessThan(u8, 25));
                    ref_sub[i] = code;
                    encUBits(&ac, &ps, CX_SP_B0, 5, code);
                }
            }
        }
        // a level every other iteration (levels 1..8, plus one big escape)
        if (i % 2 == 0 and n_lv < 510) {
            var l: i32 = @as(i32, rnd.intRangeAtMost(i8, -8, 8)) + (if (i % 4 == 0) @as(i32, 1) else 0);
            if (l == 0) l = 1; // levels are nonzero by construction
            if (i == 100) l = 5000; // exercise the big-escape tier
            ref_lv[n_lv] = l;
            acEncLevel(&ac, &ps, l);
            n_lv += 1;
        }
        // drift the probabilities adversarially between symbols — INDEX-based
        // so the decoder side can reproduce the exact same drift
        for (0..8) |ci| {
            pUpdate(&ps[ci], @truncate((i * 7 + ci * 13) & 1));
        }
    }
    ac.flush();
    try std.testing.expect(ac.n < buf.len);

    // decode and compare
    const stream: []const u8 = buf[0..ac.n];
    var br = BR{ .buf = stream };
    var dec = ACDec{ .br = &br };
    try dec.init();
    var out_lv: usize = 0;
    for (0..256) |i| {
        const m = try decMarker(&dec, &ps2);
        try std.testing.expectEqual(ref_mark[i], m);
        if (m != 1) {
            const dx = try decMV(&dec, &ps2);
            const dy = try decMV(&dec, &ps2);
            try std.testing.expectEqual(ref_dx[i], dx);
            try std.testing.expectEqual(ref_dy[i], dy);
            if (m == 2 and i % 3 == 0) {
                const bits: u5 = if (i % 6 == 0) 4 else 5;
                const code = try decUBits(&dec, &ps2, CX_SP_B0, bits);
                try std.testing.expectEqual(ref_sub[i], @as(u8, @intCast(code)));
            }
        }
        if (i % 2 == 0 and out_lv < n_lv) {
            const l = try acDecLevel(&dec, &ps2);
            try std.testing.expectEqual(ref_lv[out_lv], l);
            out_lv += 1;
        }
        for (0..8) |ci| {
            pUpdate(&ps2[ci], @truncate((i * 7 + ci * 13) & 1));
        }
    }
}

// intraPredict sanity: vertical mode copies the top row; DC of a flat
// neighborhood is the flat value.
test "intraPredict vertical copies top row, DC fills flat value" {
    var recon: [32 * 32]u8 = undefined;
    for (0..32) |r| for (0..32) |c| {
        recon[r * 32 + c] = @intCast((r * 7 + c * 3) % 256);
    };
    var out: [64]u8 = undefined;
    intraPredict(INTRA_VERTICAL, &recon, 32, 32, 8, 8, &out, null, 0); // top = row 7
    for (0..8) |r| for (0..8) |c| {
        try std.testing.expectEqual(recon[7 * 32 + 8 + c], out[r * 8 + c]);
    };
    var flat: [32 * 32]u8 = @splat(90);
    intraPredict(INTRA_DC, &flat, 32, 32, 8, 8, &out, null, 0);
    for (out) |px| try std.testing.expectEqual(@as(u8, 90), px);
}

// deblockPair never overshoots the midpoint and leaves a flat plane flat.
test "deblock pair clamps and preserves flat regions" {
    var p0: u8 = 100;
    var q0: u8 = 110;
    deblockPair(&p0, &q0, 100, 110, 50.0, 25.0);
    try std.testing.expect(p0 > 100 and q0 < 110);
    try std.testing.expect(p0 <= 105 and q0 >= 105); // midpoint never crossed
    var a: u8 = 77;
    var b: u8 = 77;
    deblockPair(&a, &b, 77, 77, 50.0, 25.0);
    try std.testing.expectEqual(@as(u8, 77), a);
    try std.testing.expectEqual(@as(u8, 77), b);
}

// ============================================================ v0.8: 16x16 superblock layer

fn genomeWithV8(id: u64, intra: f32, deb: f32, entropy: f32, cfl: f32, cdef: f32, qpel: f32, sb16: f32) gen.Genome {
    var g = genomeWithV5b(id, intra, deb, entropy, cfl, cdef, qpel);
    g.g[22] = sb16;
    return g;
}

/// Encode a whole clip and return the total bitstream byte count (no decode).
fn encodeAllBytes(alloc: std.mem.Allocator, clip: *const yuv.Clip, g: *const gen.Genome) !usize {
    initDct();
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    const p1Y = try a.alloc(u8, clip.ysz);
    const p2Y = try a.alloc(u8, clip.ysz);
    const p1U = try a.alloc(u8, clip.csz);
    const p2U = try a.alloc(u8, clip.csz);
    const p1V = try a.alloc(u8, clip.csz);
    const p2V = try a.alloc(u8, clip.csz);
    @memset(p1Y, 128);
    @memset(p2Y, 128);
    @memset(p1U, 128);
    @memset(p2U, 128);
    @memset(p1V, 128);
    @memset(p2V, 128);
    const bitbuf = try a.alloc(u8, 8 * 1024 * 1024);
    var ctx = Ctx{
        .clip = clip,
        .g = g,
        .opts = .{},
        .encY = p1Y,
        .encU = p1U,
        .encV = p1V,
        .prevY = p2Y,
        .prevU = p2U,
        .prevV = p2V,
        .decY = p1Y,
        .decU = p1U,
        .decV = p1V,
        .bw = .{ .buf = bitbuf },
        .br = .{ .buf = "" },
        .scratch = try a.alloc(u8, 1 << 20),
        .cdef_buf = try a.alloc(u8, clip.ysz),
        .mcH = try a.alloc(u8, clip.ysz),
        .mcV = try a.alloc(u8, clip.ysz),
        .mcD = try a.alloc(u8, clip.ysz),
    };
    for (0..clip.frames) |fi| {
        try encodeFrame(&ctx, @intCast(fi));
    }
    return ctx.bw.n;
}

// THE v0.8 invariant: with the 16x16 superblock layer enabled the decoder
// output must stay byte-exact equal to the encoder recon, across feature
// combinations (entropy coder vs byte path, qpel, CFL, deblocking).
test "v0.8 closed loop holds with the superblock layer on" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 64, 64, 6);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    const variants = [_]gen.Genome{
        genomeWithV8(1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9), // sb16 alone (byte path)
        genomeWithV8(2, 0.9, 0.6, 0.9, 0.9, 0.9, 0.9, 0.6), // everything on (AC path)
        genomeWithV8(3, 0.9, 0.0, 0.0, 0.9, 0.0, 0.0, 1.0), // intra modes + CFL + sb16 max
        genomeWithV8(4, 0.0, 0.6, 0.9, 0.0, 0.9, 0.9, 0.75), // entropy + cdef + qpel + sb16
    };
    for (&variants) |*g| {
        var reports = std.ArrayList(DebugReport).empty;
        defer reports.deinit(alloc);
        try debugRoundtrip(alloc, &clip, g, .{}, &reports, alloc);
        try std.testing.expectEqual(@as(usize, 6), reports.items.len);
        for (reports.items) |r| {
            try std.testing.expectEqual(@as(i32, -1), r.first_bad_block);
            try std.testing.expectEqual(@as(u32, 0), r.max_delta);
            try std.testing.expect(r.enc_y_psnr > 9.0);
        }
    }
}

// Migration invariant: anything <= 0.5 on the v0.8 gene must reproduce the
// v0.5b bitstream byte-for-byte.
test "v0.8 sb16 gene at 0 reproduces v0.5b bytes exactly" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 64, 64, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    var g0 = genomeWithV5b(11, 0.9, 0.6, 0.9, 0.9, 0.9, 0.9);
    g0.g[22] = 0.0;
    var g4 = g0;
    g4.id = 12;
    g4.g[22] = 0.4; // still off
    const b0 = try encodeAllBytes(alloc, &clip, &g0);
    const b4 = try encodeAllBytes(alloc, &clip, &g4);
    try std.testing.expectEqual(b0, b4);
}

// Engagement: on the synthetic corpus (smooth drift + boxes + flat chroma)
// the RD decision must actually pick unified superblocks somewhere, and the
// closed loop must survive it (covered above). Bytes change is the proof the
// layer is live, not dead code.
test "v0.8 superblock layer engages on smooth content" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 64, 64, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    var g_off = genomeWithV8(21, 0.9, 0.6, 0.9, 0.9, 0.9, 0.9, 0.0);
    var g_on = genomeWithV8(22, 0.9, 0.6, 0.9, 0.9, 0.9, 0.9, 1.0);
    const b_off = try encodeAllBytes(alloc, &clip, &g_off);
    const b_on = try encodeAllBytes(alloc, &clip, &g_on);
    try std.testing.expect(b_on != b_off);
    // rate sanity: the layer must never explode the stream
    try std.testing.expect(b_on < b_off * 2);
}

// Migration at the pop-file level: a legacy 33-token v5 line and the same
// line with the v0.8 gene inserted at 0.0 decode to identical genomes.
test "v0.8 pop-line migration: v5 33-token line == v6 34-token line" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const wr = fbs.writer();
    try wr.print("170007151 28 170006756 170006902 12", .{});
    for (0..22) |i| try wr.print(" {d:.4}", .{@as(f32, @floatFromInt(i % 7)) / 8.0});
    for (0..6) |i| try wr.print(" {d:.4}", .{@as(f32, @floatFromInt(i % 5)) / 4.0});
    const v5 = fbs.getWritten();
    const g5 = (try gen.parseLine(v5)).?;
    try std.testing.expectEqual(@as(f32, 0.0), g5.g[22]); // migrated to legacy

    // v6: header + 22 genes + sb16 + 6 regs
    var buf2: [4096]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);
    const wr2 = fbs2.writer();
    try wr2.print("170007151 28 170006756 170006902 12", .{});
    for (0..22) |i| try wr2.print(" {d:.4}", .{@as(f32, @floatFromInt(i % 7)) / 8.0});
    try wr2.print(" 0.0000", .{});
    for (0..6) |i| try wr2.print(" {d:.4}", .{@as(f32, @floatFromInt(i % 5)) / 4.0});
    const v6 = fbs2.getWritten();
    const g6 = (try gen.parseLine(v6)).?;
    try std.testing.expectEqual(g5.id, g6.id);
    try std.testing.expectEqualSlices(f32, &g5.g, &g6.g);
    try std.testing.expectEqualSlices(f32, &g5.reg, &g6.reg);
    try std.testing.expect(!gen.sb16On(&g6));
}
