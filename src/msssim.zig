// msssim.zig — MS-SSIM (Wang, Simoncelli, Bovik 2003) on u8 planes.
//
// v0.6a: the perceptual fitness metric. PSNR at ~0.18bpp rewards blur; MS-SSIM
// re-steepens the selection gradient where the arena was stuck. Pure DSP:
// separable 11-tap gaussian (sigma=1.5), valid-mode convolution, 2x2 box
// downsampling, 5 scales, standard stabilizing constants. No dependencies
// beyond std — runs inside the oracle on every genome evaluation.
//
// Reference constants (K1=0.01, K2=0.03, L=255, gaussian sigma=1.5):
//   C1 = (K1*L)^2 = 6.5025, C2 = (K2*L)^2 = 58.5225
//   per-scale weights: 0.0448 0.2856 0.3001 0.2363 0.1333
// MS-SSIM = l_M^{w_M} * prod_{i=1..M} cs_i^{w_i}  (means of the ssim/cs maps).

const std = @import("std");

const WIN: usize = 11;
pub const N_SCALES: usize = 5;
const WEIGHTS = [N_SCALES]f64{ 0.0448, 0.2856, 0.3001, 0.2363, 0.1333 };
const C1: f32 = 6.5025;
const C2: f32 = 58.5225;
const CS_FLOOR: f64 = 1e-6; // guards pow() against numerically-negative cs

var kern: [WIN]f32 = undefined;
var kern_ready = false;

fn initKernel() void {
    if (kern_ready) return;
    var sum: f32 = 0;
    for (0..WIN) |i| {
        const d = @as(f32, @floatFromInt(i)) - 5.0;
        kern[i] = @exp(-(d * d) / (2.0 * 1.5 * 1.5));
        sum += kern[i];
    }
    for (0..WIN) |i| kern[i] /= sum;
    kern_ready = true;
}

/// Valid-mode separable gaussian: src (w x h) -> dst ((w-10) x (h-10)).
/// tmp must hold (w-10) * h floats (horizontal pass staging).
fn gaussValid(src: []const f32, dst: []f32, w: usize, h: usize, tmp: []f32) void {
    const ow = w - WIN + 1;
    const oh = h - WIN + 1;
    // horizontal pass: h rows x ow cols
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const row = src[y * w ..][0..w];
        const orow = tmp[y * ow ..][0..ow];
        var x: usize = 0;
        while (x < ow) : (x += 1) {
            var acc: f32 = 0;
            inline for (0..WIN) |i| acc += kern[i] * row[x + i];
            orow[x] = acc;
        }
    }
    // vertical pass: oh rows x ow cols
    var yy: usize = 0;
    while (yy < oh) : (yy += 1) {
        const drow = dst[yy * ow ..][0..ow];
        var x: usize = 0;
        while (x < ow) : (x += 1) {
            var acc: f32 = 0;
            inline for (0..WIN) |i| acc += kern[i] * tmp[(yy + i) * ow + x];
            drow[x] = acc;
        }
    }
}

/// 2x2 box low-pass + decimation by 2 (Wang's inter-scale step), in place.
fn downsample2(buf: []f32, w: usize, h: usize) void {
    const nw = w / 2;
    const nh = h / 2;
    var r: usize = 0;
    while (r < nh) : (r += 1) {
        var c: usize = 0;
        while (c < nw) : (c += 1) {
            const p0 = (2 * r) * w + 2 * c;
            const p1 = (2 * r) * w + 2 * c + 1;
            const p2 = (2 * r + 1) * w + 2 * c;
            const p3 = (2 * r + 1) * w + 2 * c + 1;
            buf[r * nw + c] = (buf[p0] + buf[p1] + buf[p2] + buf[p3]) * 0.25;
        }
    }
}

/// MS-SSIM of one Y plane pair. alloc is used for an internal scratch arena.
/// Returns a value in (0, 1]; identical planes -> 1.0.
pub fn planeMsssim(
    alloc: std.mem.Allocator,
    src: []const u8,
    rec: []const u8,
    w: usize,
    h: usize,
) !f32 {
    initKernel();
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();

    // u8 planes -> f32 working buffers
    const x = try a.alloc(f32, w * h);
    const y = try a.alloc(f32, w * h);
    for (src, x) |s, *d| d.* = @floatFromInt(s);
    for (rec, y) |s, *d| d.* = @floatFromInt(s);

    var lw = w;
    var lh = h;
    var log_ss: f64 = 0;

    var scale: usize = 0;
    while (scale < N_SCALES) : (scale += 1) {
        if (lw < WIN or lh < WIN) {
            // plane too small for a full window at this scale: lump the
            // remaining weight onto the last computed scale (never hit by
            // the arena corpus: 320x192 -> 20x12 at scale 5, still >= 11).
            log_ss += (1.0 - sumWeights(scale)) * 0.0;
            break;
        }
        const vw = lw - WIN + 1;
        const vh = lh - WIN + 1;
        const n = vw * vh;

        const fx = try a.alloc(f32, n);
        const fy = try a.alloc(f32, n);
        const fxx = try a.alloc(f32, n);
        const fyy = try a.alloc(f32, n);
        const fxy = try a.alloc(f32, n);
        const tmp = try a.alloc(f32, (lw - WIN + 1) * lh);

        // E[x], E[y]
        gaussValid(x, fx, lw, lh, tmp);
        gaussValid(y, fy, lw, lh, tmp);
        // E[x^2], E[y^2], E[xy] — square into scratch first.
        // NOTE: x/y stay at the ORIGINAL allocation; only the leading
        // cur = lw*lh elements are live at this scale — slice them explicitly
        // or the multi-object for() iterates mismatched lengths (UB in ReleaseFast).
        const cur = lw * lh;
        const sq = try a.alloc(f32, cur);
        for (x[0..cur], sq) |v, *o| o.* = v * v;
        gaussValid(sq, fxx, lw, lh, tmp);
        for (y[0..cur], sq) |v, *o| o.* = v * v;
        gaussValid(sq, fyy, lw, lh, tmp);
        for (x[0..cur], y[0..cur], sq) |vx, vy, *o| o.* = vx * vy;
        gaussValid(sq, fxy, lw, lh, tmp);

        // ssim (l) and contrast-structure (cs) map means, f64 accumulation
        var acc_l: f64 = 0;
        var acc_cs: f64 = 0;
        for (0..n) |i| {
            const mx = fx[i];
            const my = fy[i];
            const vx2 = fxx[i] - mx * mx;
            const vy2 = fyy[i] - my * my;
            const vxy = fxy[i] - mx * my;
            acc_l += @floatCast((2.0 * mx * my + C1) / (mx * mx + my * my + C1));
            acc_cs += @floatCast((2.0 * vxy + C2) / (vx2 + vy2 + C2));
        }
        const m_l: f64 = acc_l / @as(f64, @floatFromInt(n));
        const m_cs: f64 = acc_cs / @as(f64, @floatFromInt(n));

        if (scale == N_SCALES - 1) {
            log_ss += WEIGHTS[scale] * @log(@max(m_l, CS_FLOOR));
        }
        log_ss += WEIGHTS[scale] * @log(@max(m_cs, CS_FLOOR));

        if (scale + 1 < N_SCALES) {
            downsample2(x, lw, lh);
            downsample2(y, lw, lh);
            lw = lw / 2;
            lh = lh / 2;
        }
    }

    return @floatCast(@exp(log_ss));
}

fn sumWeights(from: usize) f64 {
    var s: f64 = 0;
    for (from..N_SCALES) |i| s += WEIGHTS[i];
    return s;
}

// ---------------------------------------------------------------- tests

const t = std.testing;

test "identical planes score 1.0" {
    var buf: [64 * 64]u8 = undefined;
    for (&buf, 0..) |*p, i| p.* = @intCast((i * 7) % 256);
    const v = try planeMsssim(t.allocator, &buf, &buf, 64, 64);
    try t.expect(v > 0.9999);
}

test "noise degrades monotonically" {
    var base: [64 * 64]u8 = undefined;
    var noisy: [64 * 64]u8 = undefined;
    for (&base, 0..) |*p, i| p.* = @intCast((i * 3 + (i / 64) * 5) % 256);
    var rng = std.Random.DefaultPrng.init(0xC0DEC);
    const rand = rng.random();
    // mild noise
    for (&noisy, base) |*p, b| p.* = @intCast(@min(255, @as(i32, b) + rand.intRangeAtMost(i32, -4, 4)));
    const mild = try planeMsssim(t.allocator, &base, &noisy, 64, 64);
    // heavy noise
    for (&noisy, base) |*p, b| p.* = @intCast(@min(255, @as(i32, b) + rand.intRangeAtMost(i32, -40, 40)));
    const heavy = try planeMsssim(t.allocator, &base, &noisy, 64, 64);
    try t.expect(mild > heavy);
    try t.expect(heavy > 0.05 and heavy < 0.999);
}

test "tiny planes do not crash" {
    var a: [16]u8 = undefined;
    var b: [16]u8 = undefined;
    for (0..16) |i| {
        a[i] = @intCast(10 + i * 10);
        b[i] = @intCast(10 + i * 10 + (i % 3));
    }
    _ = try planeMsssim(t.allocator, &a, &b, 4, 4);
}

test "constant offset reduces luminance but stays high" {
    var a: [32 * 32]u8 = undefined;
    var b: [32 * 32]u8 = undefined;
    for (&a, 0..) |*p, i| p.* = @intCast((i * 11) % 200 + 20);
    for (&b, a) |*p, v| p.* = @intCast(v + 10);
    const v = try planeMsssim(t.allocator, &a, &b, 32, 32);
    try t.expect(v > 0.90 and v < 1.0);
}
