// codec.zig — a real (if tiny) hybrid video codec whose every behavior is
// controlled by a 16-gene genome: 8x8 DCT, zigzag, deadzone quantization,
// integer motion estimation with optional half-pel-refined decisions, intra
// refresh, open-loop adaptive Q, two entropy modes. Encode -> bitstream ->
// decode as INDEPENDENT paths; PSNR is measured on decoded output.

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

    fn put(self: *BW, b: u8) void {
        self.buf[self.n] = b;
        self.n += 1;
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

    fn getUvarint(self: *BR) !u64 {
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
        const z = try self.getUvarint();
        const v: i64 = @bitCast(z >> 1);
        return if (z & 1 != 0) ~v + 1 else v;
    }
    fn getU8(self: *BR) !u8 {
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

    block_src: [64]u8 = @splat(0),
    dct_calls: u64 = 0,
    idct_calls: u64 = 0,
    qp_adj: f32 = 0,
    prev_frame_bytes: usize = 0,
    last_frame_bytes: usize = 0,
    dec_fi: u32 = 0,
    debug_px: bool = false,
};

fn packPairs(ctx: *Ctx, lv: []const i32, last: usize) void {
    var npairs: u64 = 0;
    for (lv[0 .. last + 1]) |l| {
        if (l != 0) npairs += 1;
    }
    ctx.bw.putUvarint(npairs);
    var run: u64 = 0;
    for (0..last + 1) |k| {
        if (lv[k] == 0) {
            run += 1;
        } else {
            ctx.bw.putUvarint(run);
            ctx.bw.putSvarint(lv[k]);
            run = 0;
        }
    }
}

fn quantizeBlock(ctx: *Ctx, src: []const u8, qp: f32, scale: f32, lv: *[64]i32) void {
    var coef: [64]f32 = undefined;
    dct8(src, &coef);
    ctx.dct_calls += 1;
    const dz = gen.deadzone(ctx.g);
    const dith = gen.dither(ctx.g);
    for (0..64) |k| {
        const bs = gen.bandScale(ctx.g, zzBand(k));
        lv[k] = quantLevel(coef[ZZ[k]], bandQ(qp, scale * bs), dz, dith);
    }
}

fn dequantLevels(ctx: *Ctx, lv: *const [64]i32, qp: f32, scale: f32, out: *[64]f32) void {
    for (0..64) |k| {
        const bs = gen.bandScale(ctx.g, zzBand(k));
        const q = bandQ(qp, scale * bs);
        const lf: f32 = @floatFromInt(lv[k]);
        out[ZZ[k]] = lf * q;
    }
}

// --------------------------------------------------------------- encode frame

fn encodeFrame(ctx: *Ctx, fi: u32) !void {
    const g = ctx.g;
    const clip = ctx.clip;
    const key_int = gen.keyInt(g);
    const is_i = (fi % key_int) == 0;
    const qp_f: f32 = std.math.clamp(gen.baseQ(g) + ctx.qp_adj, 1.0, 120.0);
    const qp: f32 = @round(qp_f);

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

    var by: usize = 0;
    while (by < nby) : (by += 1) {
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

            if (force_intra) {
                if (!is_i) ctx.bw.putU8(2); // intra-in-P marker
                var lv: [64]i32 = undefined;
                quantizeBlock(ctx, ctx.block_src[0..64], qp, iq_scale, &lv);
                var last: usize = 0;
                for (0..64) |k| {
                    if (lv[k] != 0) last = k;
                }
                packPairs(ctx, lv[0..], last);
                var deq: [64]f32 = undefined;
                dequantLevels(ctx, &lv, qp, iq_scale, &deq);
                idct8(&deq, enc[sy * pw + sx ..], pw, &ctx.idct_calls);
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
                if (perpx < gen.skipTh(g)) {
                    ctx.bw.putU8(1); // skip: cur already == prev copy
                } else {
                    ctx.bw.putU8(0);
                    ctx.bw.putSvarint(bdx);
                    ctx.bw.putSvarint(bdy);
                    const ox: usize = @intCast(@as(i32, @intCast(sx)) + bdx);
                    const oy: usize = @intCast(@as(i32, @intCast(sy)) + bdy);
                    var pred: [64]u8 = undefined;
                    var r2: usize = 0;
                    while (r2 < 8) : (r2 += 1) {
                        @memcpy(pred[r2 * 8 ..][0..8], prev[(oy + r2) * pw + ox ..][0..8]);
                    }
                    // residual = src - pred, offset by 128 for DCT
                    var res: [64]u8 = undefined;
                    for (0..64) |k| {
                        const d: i32 = @as(i32, ctx.block_src[k]) - @as(i32, pred[k]);
                        res[k] = @intCast(std.math.clamp(d + 128, 0, 255));
                    }
                    var lv: [64]i32 = undefined;
                    quantizeBlock(ctx, res[0..64], qp, pq_scale, &lv);
                    var last: usize = 0;
                    for (0..64) |k| {
                        if (lv[k] != 0) last = k;
                    }
                    packPairs(ctx, lv[0..], last);
                    // reconstruct: pred + idct(dequant(residual))
                    var deq: [64]f32 = undefined;
                    dequantLevels(ctx, &lv, qp, pq_scale, &deq);
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
                            bdx, bdy,
                            ctx.block_src[0..8],
                            pred[0..8],
                            res[0..8],
                            rec[0..8],
                            dst[0..8],
                        });
                    }
                }
            }
        }
    }
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

    try decodePlane(ctx, is_i, qp, curY, prevY, clip.w, clip.h, false, refresh);
    try decodePlane(ctx, is_i, qp, curU, prevU, clip.w / 2, clip.h / 2, true, refresh);
    try decodePlane(ctx, is_i, qp, curV, prevV, clip.w / 2, clip.h / 2, true, refresh);
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

    var by: usize = 0;
    while (by < nby) : (by += 1) {
        var bx: usize = 0;
        while (bx < nbx) : (bx += 1) {
            const sx = bx * 8;
            const sy = by * 8;
            const force_intra = is_i or (do_refresh and by == rrow);

            if (force_intra) {
                if (!is_i) _ = try ctx.br.getU8(); // intra-in-P marker
                // unpack pairs
                const npairs = try ctx.br.getUvarint();
                var coef: [64]f32 = @splat(0);
                var k: u64 = 0;
                var i: u64 = 0;
                while (i < npairs) : (i += 1) {
                    const run = try ctx.br.getUvarint();
                    const lvl = try ctx.br.getSvarint();
                    k += run;
                    if (k >= 64) return error.Corrupt;
                    const bs = gen.bandScale(g, zzBand(@intCast(k)));
                    const q = bandQ(qp, iq_scale * bs);
                    const lf: f32 = @floatFromInt(lvl);
                    coef[ZZ[@intCast(k)]] = lf * q;
                    k += 1;
                }
                idct8(&coef, cur[sy * pw + sx ..], pw, &ctx.idct_calls);
            } else {
                const flags = try ctx.br.getU8();
                if (flags == 1) {
                    // skip: cur already copied from prev
                } else {
                    const dx = try ctx.br.getSvarint();
                    const dy = try ctx.br.getSvarint();
                    const ox: usize = @intCast(@as(i32, @intCast(sx)) + @as(i32, @intCast(dx)));
                    const oy: usize = @intCast(@as(i32, @intCast(sy)) + @as(i32, @intCast(dy)));
                    var pred: [64]u8 = undefined;
                    var r2: usize = 0;
                    while (r2 < 8) : (r2 += 1) {
                        @memcpy(pred[r2 * 8 ..][0..8], prev[(oy + r2) * pw + ox ..][0..8]);
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
                        const bs = gen.bandScale(g, zzBand(@intCast(k)));
                        const q = bandQ(qp, pq_scale * bs);
                        const lf: f32 = @floatFromInt(lvl);
                        coef[ZZ[@intCast(k)]] = lf * q;
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
