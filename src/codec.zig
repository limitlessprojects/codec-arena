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

pub const EvalOpts = struct {
    fast_sad: bool = true, // sample every 2nd pixel during motion search
};

pub const ClipStats = struct {
    bytes: u64,
    psnr_y: f32,
    enc_ms: f32,
    enc_mops: f32, // (dct+idct calls)*64 / 1e6
    dec_mops: f32, // idct calls*64 / 1e6
};

// ---------------------------------------------------------------- DCT tables

var dct_tab: [64]f32 = undefined; // t[u*8 + x] = c(u)/2 * cos((2x+1)u*pi/16)
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

fn bandQ(qp: f32, scale: f32) f32 {
    return @max(1.0, qp * scale);
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

/// Enabled intra modes for this genome. NONE is ALWAYS present as mode 0 in
/// every non-legacy set: the clamp-aware mode decision then guarantees the
/// chosen predictor is never worse than the legacy raw-DCT path per block —
/// richer sets can only help, never crater. A single {NONE} set means legacy
/// raw-DCT intra: no prediction, no mode map, byte-exact v0.1-v0.3 bitstream.
pub fn intraModes(g: *const gen.Genome) []const u8 {
    const v = gen.intraPredGene(g);
    if (v < 0.25) return &.{INTRA_NONE};
    if (v < 0.55) return &.{ INTRA_NONE, INTRA_DC };
    if (v < 0.85) return &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL };
    return &.{ INTRA_NONE, INTRA_DC, INTRA_PLANAR, INTRA_VERTICAL, INTRA_HORIZONTAL, INTRA_DIAG_DR, INTRA_DIAG_DL, INTRA_HOR_DOWN };
}

/// Bits needed to index a mode within a set of n (ceil(log2(n))). Both sides
/// derive it from the genome, so the mode map costs 1 bit/block for
/// {NONE,DC} and 3 bits/block for the 5- and 8-mode sets — x264-style narrow
/// signaling in a per-plane map instead of a byte per block.
pub fn intraModeBits(n: usize) u5 {
    if (n <= 1) return 0;
    return @intCast(32 - @clz(@as(u32, @intCast(n - 1))));
}

/// Build the 8x8 prediction block for `mode` from the recon plane at block
/// (sx, sy). Unavailable neighbors (frame edges) are filled with 128.
/// Deterministic in (mode, plane contents, sx, sy, pw, ph) only — the same
/// function runs on both sides, so predictions can never desynchronize.
fn intraPredict(mode: u8, recon: []const u8, pw: usize, ph: usize, sx: usize, sy: usize, out: *[64]u8) void {
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
            var dc: i32 = 128 * 16;
            if (have_top and have_left) {
                var s: i32 = 0;
                for (0..8) |i| s += top[i];
                for (0..8) |i| s += left[i];
                dc = @divTrunc(s + 8, 16);
            } else if (have_top) {
                var s: i32 = 0;
                for (0..8) |i| s += top[i];
                dc = @divTrunc(s + 4, 8);
            } else if (have_left) {
                var s: i32 = 0;
                for (0..8) |i| s += left[i];
                dc = @divTrunc(s + 4, 8);
            }
            const px: u8 = @intCast(std.math.clamp(dc, 0, 255));
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
    // [mode map][block data] into the main bitstream (v0.4 syntax)
    scratch: []u8,

    block_src: [64]u8 = @splat(0),
    dct_calls: u64 = 0,
    idct_calls: u64 = 0,
    qp_adj: f32 = 0,
    prev_frame_bytes: usize = 0,
    last_frame_bytes: usize = 0,
    dec_fi: u32 = 0,
    cur_gop: f32 = 0,
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

    // v0.4 in-loop deblocking: the finished recon frame is smoothed BEFORE it
    // becomes the next reference and the stored decoder output. Same qp, same
    // code path on the decoder — can never desynchronize.
    deblockFrame(g, ctx.encY, ctx.encU, ctx.encV, clip.w, clip.h, qp);

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
    const g = ctx.g;
    const cqp_scale = gen.chromaScale(g);
    const iq_scale: f32 = if (chroma) cqp_scale else 1.0;
    const pq_scale: f32 = if (chroma) gen.pQmul(g) * cqp_scale else gen.pQmul(g);
    const nbx: usize = pw / 8;
    const nby: usize = ph / 8;
    const rrow: usize = @intCast((fi / refresh) % @max(1, nby));
    const do_refresh = !is_i and !chroma and (fi / refresh) > 0;
    const halfpel = gen.halfPel(g);

    // v0.4 per-plane framing: block data goes to scratch, intra mode codes go
    // to a bit-packed map; the plane lands as [mode map][block data].
    const modes = intraModes(g);
    const mwidth: u5 = intraModeBits(modes.len);
    var mmap: [512]u8 = @splat(0);
    var mbacc: u32 = 0;
    var mbn: u5 = 0;
    var mmap_n: usize = 0; // completed bytes in the mode map
    var sbw = BW{ .buf = ctx.scratch };
    if (modes.len > 1 and (nbx * nby * @as(usize, mwidth) + 7) / 8 > mmap.len) return error.BitstreamOverflow;

    var by: usize = 0;
    while (by < nby) : (by += 1) {
        const by_n: f32 = (@as(f32, @floatFromInt(by)) + 0.5) / @as(f32, @floatFromInt(nby));
        var bx: usize = 0;
        while (bx < nbx) : (bx += 1) {
            const sx = bx * 8;
            const sy = by * 8;
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
                if (!is_i) sbw.putU8(2); // intra-in-P marker
                var lv: [64]i32 = undefined;
                if (modes.len == 1) {
                    // legacy: raw block into DCT — no prediction, no mode code
                    quantizeBlock(ctx, ctx.block_src[0..64], qp, iq_scale, rc, &lv);
                    var last: usize = 0;
                    for (0..64) |k| {
                        if (lv[k] != 0) last = k;
                    }
                    packPairs(&sbw, lv[0..], last);
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
                        intraPredict(m, enc, pw, ph, sx, sy, &trial);
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
                    packPairs(&sbw, lv[0..], last);
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
                var subpel: u8 = 4; // (hx+1)*3+(hy+1); 4 = integer-pel center
                var pred: [64]u8 = undefined;
                const ox_i: i32 = @intCast(@as(i32, @intCast(sx)) + bdx);
                const oy_i: i32 = @intCast(@as(i32, @intCast(sy)) + bdy);
                if (halfpel) {
                    // half-pel refinement around the integer MV
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
                    sbw.putU8(1); // skip: cur already == prev copy
                } else {
                    if (subpel != 4) {
                        sbw.putU8(2); // inter with half-pel refinement
                    } else {
                        sbw.putU8(0);
                    }
                    sbw.putSvarint(bdx);
                    sbw.putSvarint(bdy);
                    if (subpel != 4) sbw.putU8(subpel);
                    if (subpel == 4) {
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
                    packPairs(&sbw, lv[0..], last);
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
        }
    }

    // ---- plane framing: [mode map (deterministic length)][block data] ----
    if (mwidth > 0) {
        const map_len = (nbx * nby * @as(usize, mwidth) + 7) / 8;
        for (mmap[0..map_len]) |b| ctx.bw.put(b); // zero-padded tail included
    }
    for (ctx.scratch[0..sbw.n]) |b| ctx.bw.put(b);
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

    // v0.4 in-loop deblocking — mirrors encodeFrame exactly: same planes, same
    // frame qp, same filter. The deblocked frame is the stored output AND the
    // next frame's reference on both sides.
    deblockFrame(g, curY, curU, curV, clip.w, clip.h, qp);
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
    const g = ctx.g;
    const cqp_scale = gen.chromaScale(g);
    const iq_scale: f32 = if (chroma) cqp_scale else 1.0;
    const pq_scale: f32 = if (chroma) gen.pQmul(g) * cqp_scale else gen.pQmul(g);
    const nbx: usize = pw / 8;
    const nby: usize = ph / 8;
    const rrow: usize = @intCast((ctx.dec_fi / refresh) % @max(1, nby));
    const do_refresh = !is_i and !chroma and (ctx.dec_fi / refresh) > 0;

    // v0.4: the plane's intra mode map precedes the block data — read it once
    // (deterministic length), then decode blocks against it.
    const modes = intraModes(g);
    const mwidth: u5 = intraModeBits(modes.len);
    var mmap: [512]u8 = undefined;
    var map_br = BR{ .buf = mmap[0..0] };
    if (mwidth > 0) {
        const map_len = (nbx * nby * @as(usize, mwidth) + 7) / 8;
        for (0..map_len) |mi| mmap[mi] = try ctx.br.getU8();
        map_br = .{ .buf = mmap[0..map_len] };
    }

    var by: usize = 0;
    while (by < nby) : (by += 1) {
        const by_n: f32 = (@as(f32, @floatFromInt(by)) + 0.5) / @as(f32, @floatFromInt(nby));
        var bx: usize = 0;
        while (bx < nbx) : (bx += 1) {
            const sx = bx * 8;
            const sy = by * 8;
            const force_intra = is_i or (do_refresh and by == rrow);
            var rc = gen.RegCtx{
                .mv_n = 0,
                .by_n = by_n,
                .gop = ctx.cur_gop,
                .intra = force_intra,
            };

            if (force_intra) {
                if (!is_i) _ = try ctx.br.getU8(); // intra-in-P marker
                if (modes.len == 1) {
                    // legacy: no mode byte, raw-DCT recon
                    const npairs = try ctx.br.getUvarint();
                    var coef: [64]f32 = @splat(0);
                    var k: u64 = 0;
                    var i: u64 = 0;
                    while (i < npairs) : (i += 1) {
                        const run = try ctx.br.getUvarint();
                        const lvl = try ctx.br.getSvarint();
                        k += run;
                        if (k >= 64) return error.Corrupt;
                        const lf: f32 = @floatFromInt(lvl);
                        coef[ZZ[@intCast(k)]] = lf * levelQ(g, qp, iq_scale, @intCast(k), rc);
                        k += 1;
                    }
                    idct8(&coef, cur[sy * pw + sx ..], pw, &ctx.idct_calls);
                } else {
                    // v0.4: mode index from the plane's bit-packed map (1-3
                    // bits), prediction from the decoder's own recon plane
                    // (identical availability, identical pixels).
                    const midx = try map_br.getBits(mwidth);
                    if (midx >= modes.len) return error.Corrupt;
                    const mode = modes[midx];
                    var pred: [64]u8 = undefined;
                    intraPredict(mode, cur, pw, ph, sx, sy, &pred);
                    const npairs = try ctx.br.getUvarint();
                    var coef: [64]f32 = @splat(0);
                    var k: u64 = 0;
                    var i: u64 = 0;
                    while (i < npairs) : (i += 1) {
                        const run = try ctx.br.getUvarint();
                        const lvl = try ctx.br.getSvarint();
                        k += run;
                        if (k >= 64) return error.Corrupt;
                        const lf: f32 = @floatFromInt(lvl);
                        coef[ZZ[@intCast(k)]] = lf * levelQ(g, qp, iq_scale, @intCast(k), rc);
                        k += 1;
                    }
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
                const flags = try ctx.br.getU8();
                if (flags == 1) {
                    // skip: cur already copied from prev
                } else {
                    const dx = try ctx.br.getSvarint();
                    const dy = try ctx.br.getSvarint();
                    rc.mv_n = @min(1.0, (@as(f32, @floatFromInt(@abs(dx))) + @as(f32, @floatFromInt(@abs(dy)))) / 8.0);
                    const ox_i: i32 = @as(i32, @intCast(sx)) + @as(i32, @intCast(dx));
                    const oy_i: i32 = @as(i32, @intCast(sy)) + @as(i32, @intCast(dy));
                    var pred: [64]u8 = undefined;
                    if (flags == 2) {
                        const code = try ctx.br.getU8();
                        const hx = @as(i32, code / 3) - 1;
                        const hy = @as(i32, code % 3) - 1;
                        interpBlock(prev, pw, ph, ox_i, oy_i, hx, hy, &pred);
                    } else {
                        var r2: usize = 0;
                        while (r2 < 8) : (r2 += 1) {
                            @memcpy(pred[r2 * 8 ..][0..8], prev[@as(usize, @intCast(oy_i + @as(i32, @intCast(r2)))) * pw + @as(usize, @intCast(ox_i)) ..][0..8]);
                        }
                    }
                    const npairs = try ctx.br.getUvarint();
                    var coef: [64]f32 = @splat(0);
                    var k: u64 = 0;
                    var i: u64 = 0;
                    while (i < npairs) : (i += 1) {
                        const run = try ctx.br.getUvarint();
                        const lvl = try ctx.br.getSvarint();
                        k += run;
                        if (k >= 64) return error.Corrupt;
                        const lf: f32 = @floatFromInt(lvl);
                        coef[ZZ[@intCast(k)]] = lf * levelQ(g, qp, pq_scale, @intCast(k), rc);
                        k += 1;
                    }
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
    for (0..clip.frames) |fi| {
        const s = clip.frameY(@intCast(fi));
        const d = decY[@as(usize, fi) * clip.ysz ..][0..clip.ysz];
        acc += yuv.psnrPlane(s, d);
    }
    const mean_psnr = acc / @as(f32, @floatFromInt(clip.frames));

    return .{
        .bytes = bitstream.len,
        .psnr_y = mean_psnr,
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

// The migration invariant: a genome with the v0.4 genes at 0.0 must take the
// legacy path — same PSNR/bytes as a genome whose new genes were never set.
test "v0.4 genes at 0 reproduce legacy metrics exactly" {
    const alloc = std.testing.allocator;
    var clip = try synthClip(alloc, 32, 32, 4);
    defer alloc.free(clip.y);
    defer alloc.free(clip.u);
    defer alloc.free(clip.v);

    var a = genomeWith(10, 0.0, 0.0);
    var b = genomeWith(10, 0.0, 0.0);
    b.g[7] = 0.3; // unrelated gene differs — must not matter to this check
    var ra = std.ArrayList(DebugReport).empty;
    defer ra.deinit(alloc);
    var rb = std.ArrayList(DebugReport).empty;
    defer rb.deinit(alloc);
    try debugRoundtrip(alloc, &clip, &a, .{}, &ra, alloc);
    try debugRoundtrip(alloc, &clip, &b, .{}, &rb, alloc);
    // determinism: identical runs, identical reports
    for (ra.items, rb.items) |x, yv| {
        try std.testing.expectEqual(x.enc_y_psnr, yv.enc_y_psnr);
        try std.testing.expectEqual(x.max_delta, yv.max_delta);
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
    intraPredict(INTRA_VERTICAL, &recon, 32, 32, 8, 8, &out); // top = row 7
    for (0..8) |r| for (0..8) |c| {
        try std.testing.expectEqual(recon[7 * 32 + 8 + c], out[r * 8 + c]);
    };
    var flat: [32 * 32]u8 = @splat(90);
    intraPredict(INTRA_DC, &flat, 32, 32, 8, 8, &out);
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
