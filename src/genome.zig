// genome.zig — a bot is 18 effector genes + 6 regulator genes, all in [0,1],
// plus lineage. The brain breeds them; the codec only needs to read them.
//
// v0.3 — the regulatory layer (GRN v1): regulators don't set codec knobs
// directly; they modulate effector-driven knobs per block/frame as a function
// of context (motion magnitude, GOP position, block row, intra flag). Every
// context is decoder-derivable from the bitstream, so regulation costs zero
// side-info and encoder/decoder stay identical by sharing one code path.
//
// Smoothness (canalization) by construction: every regulator is an affine
// map of its gene with gain bounded to ±0.25, neutral at gene = 0.5.
// A 0.01 mutation changes output by at most ~0.5% of the modulated quantity.

pub const NG: usize = 18; // effectors (legacy 16 preserved; v0.4 adds 2)
pub const NR: usize = 6; // regulators
pub const NTOT: usize = NG + NR; // 24

// v0.4 structural genes (learned from the best of the best — x264's two
// structural pillars). Migration invariant: gene 0.0 == EXACT legacy
// behavior, so every pre-v0.4 genome keeps its oracle metrics byte-for-byte
// and the Hall of Fame floor stays comparable.
/// g[16]: intra spatial-prediction mode set (H.264/x264 intra prediction).
///   <0.25 none (legacy raw-DCT) | <0.55 {none,DC} | <0.85 {DC,planar,V,H}
///   | >=0.85 + 3 diagonal angles
pub fn intraPredGene(g: *const Genome) f32 {
    return clamp01(g.g[16]);
}
/// g[17]: in-loop deblocking filter strength (0 = off = legacy).
pub fn deblockGene(g: *const Genome) f32 {
    return clamp01(g.g[17]);
}

const std = @import("std");

pub const Genome = struct {
    id: u64,
    gen: u32,
    pa: u64,
    pb: u64,
    tribe: u32,
    g: [NG]f32,
    reg: [NR]f32 = @splat(0.5), // neutral unless the line carries v2 genes
};

pub const GeneNames = [_][]const u8{
    "keyint",     "dz_dc",   "search",   "baseq",
    "q_low",      "q_mid",   "q_high",   "deadzone",
    "skip",       "p_qmul",  "intra_b0", "dither",
    "halfpel",    "refresh", "adaptq",   "chroma_q",
    "intra_pred", "deblock",
};
pub const RegNames = [_][]const u8{
    "mv_dz", // deadzone scales with motion magnitude   (encoder-side)
    "mv_q", // inter q-scale scales with motion        (decoder-mirrored)
    "gop_q", // frame qp ramps across the GOP           (transmitted qp)
    "row_q", // q-scale gradient by block row           (decoder-mirrored)
    "skip_mv", // skip threshold scales with motion     (encoder-side)
    "intra_gop", // intra q-scale ramps across the GOP  (decoder-mirrored)
};

pub const NEW_GENE_LEGACY: f32 = 0.0; // migration default: exact legacy behavior

/// Parse one pop-file line:
///   v1: id gen pa pb tribe g0..g15                  (21 tokens; regs neutral)
///   v2: id gen pa pb tribe g0..g15 r0..r5           (27 tokens)
///   v3: id gen pa pb tribe g0..g17 r0..r5           (29 tokens)
/// v1/v2 lines migrate with the v0.4 genes at 0.0 = exact legacy behavior.
pub fn parseLine(line: []const u8) !?Genome {
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    var tok: [29][]const u8 = undefined;
    var n: usize = 0;
    while (it.next()) |t| {
        if (n >= 29) return error.BadLine;
        tok[n] = t;
        n += 1;
    }
    if (n != 21 and n != 27 and n != 29) return null;
    if (tok[0].len > 0 and tok[0][0] == '#') return null;
    var gm = Genome{
        .id = try std.fmt.parseInt(u64, tok[0], 10),
        .gen = try std.fmt.parseInt(u32, tok[1], 10),
        .pa = try std.fmt.parseInt(u64, tok[2], 10),
        .pb = try std.fmt.parseInt(u64, tok[3], 10),
        .tribe = try std.fmt.parseInt(u32, tok[4], 10),
        .g = undefined,
    };
    for (0..16) |i| {
        gm.g[i] = try std.fmt.parseFloat(f32, tok[5 + i]); // legacy effectors: fixed slots
    }
    if (n == 29) {
        gm.g[16] = try std.fmt.parseFloat(f32, tok[21]); // v0.4: intra_pred
        gm.g[17] = try std.fmt.parseFloat(f32, tok[22]); // v0.4: deblock
    } else {
        gm.g[16] = NEW_GENE_LEGACY; // migration: exact legacy behavior
        gm.g[17] = NEW_GENE_LEGACY;
    }
    if (n == 27) {
        for (0..NR) |i| {
            gm.reg[i] = try std.fmt.parseFloat(f32, tok[21 + i]);
        }
    } else if (n == 29) {
        for (0..NR) |i| {
            gm.reg[i] = try std.fmt.parseFloat(f32, tok[23 + i]);
        }
    } else {
        for (0..NR) |i| gm.reg[i] = 0.5; // v1: neutral regulators
    }
    return gm;
}

/// Emit a v3 pop-file line (29 tokens).
pub fn formatLine(g: *const Genome, buf: []u8) ![]const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const w = fbs.writer();
    try w.print("{d} {d} {d} {d} {d}", .{ g.id, g.gen, g.pa, g.pb, g.tribe });
    for (0..NG) |i| {
        try w.print(" {d:.4}", .{g.g[i]});
    }
    for (0..NR) |i| {
        try w.print(" {d:.4}", .{g.reg[i]});
    }
    return fbs.getWritten();
}

// ---- gene mappings (the phenotype) ----

pub fn keyInt(g: *const Genome) u32 {
    return 1 + @as(u32, @intFromFloat(clamp01(g.g[0]) * 47.0));
}
/// Repurposed v0.3: multiplier on the DC/deadzone level (was dead "blk" gene).
pub fn dzDcMul(g: *const Genome) f32 {
    return 0.5 + clamp01(g.g[1]) * 1.5;
}
pub fn searchR(g: *const Genome) u32 {
    return @intFromFloat(clamp01(g.g[2]) * 12.0);
}
pub fn baseQ(g: *const Genome) f32 {
    return 2.0 + clamp01(g.g[3]) * 46.0;
}
pub fn bandScale(g: *const Genome, band: usize) f32 {
    return switch (band) {
        0 => 0.5 + clamp01(g.g[4]) * 1.5,
        1 => 0.5 + clamp01(g.g[5]) * 2.5,
        else => 0.5 + clamp01(g.g[6]) * 4.0,
    };
}
pub fn deadzone(g: *const Genome) f32 {
    return clamp01(g.g[7]) * 14.0;
}
pub fn skipTh(g: *const Genome) f32 {
    return clamp01(g.g[8]) * 8.0; // per-pixel SAD threshold
}
pub fn pQmul(g: *const Genome) f32 {
    return 0.3 + clamp01(g.g[9]) * 1.7;
}
/// Repurposed v0.3: band-0 (low-frequency) scale boost for INTRA blocks.
pub fn intraB0Mul(g: *const Genome) f32 {
    return 0.5 + clamp01(g.g[10]) * 1.5;
}
pub fn dither(g: *const Genome) f32 {
    return (clamp01(g.g[11]) - 0.5) * 1.0;
}
pub fn halfPel(g: *const Genome) bool {
    return g.g[12] > 0.6; // REAL since v0.3: half-pel MV refinement
}
pub fn refreshEvery(g: *const Genome) u32 {
    return 1 + @as(u32, @intFromFloat(clamp01(g.g[13]) * 8.0));
}
pub fn adaptQ(g: *const Genome) f32 {
    return clamp01(g.g[14]) * 10.0;
}
pub fn chromaScale(g: *const Genome) f32 {
    return 0.5 + clamp01(g.g[15]) * 1.5;
}

// ---- regulatory layer ----

/// Damped regulator gain: gene [0,1] -> gain [-0.25, +0.25], neutral at 0.5.
pub inline fn regGain(g: *const Genome, i: usize) f32 {
    return (clamp01(g.reg[i]) - 0.5) * 0.5;
}

pub const RegCtx = struct {
    mv_n: f32 = 0, // motion magnitude, L1 pels / 8, clamped [0,1]
    by_n: f32 = 0, // block row center / nby, [0,1]
    gop: f32 = 0, // position within GOP, [0,1)
    intra: bool = false,
};

/// Decoder-mirrored q-scale modulation. ONE source of truth shared by the
/// encoder and the decoder — regulation can never desynchronize.
pub fn regQMod(g: *const Genome, rc: RegCtx) f32 {
    const mv_term = 1.0 + regGain(g, 1) * (2.0 * rc.mv_n - 1.0);
    const row_term = 1.0 + regGain(g, 3) * (2.0 * rc.by_n - 1.0);
    var m = mv_term * row_term;
    if (rc.intra) {
        m *= 1.0 + regGain(g, 5) * (2.0 * rc.gop - 1.0);
    }
    return @max(0.5, @min(2.0, m));
}

/// Encoder-only: motion-keyed deadzone modulation.
pub fn regDeadzone(g: *const Genome, rc: RegCtx, base_dz: f32) f32 {
    const m = 1.0 + regGain(g, 0) * (2.0 * rc.mv_n - 1.0);
    return base_dz * @max(0.5, @min(2.0, m));
}

/// Encoder-only: motion-keyed skip-threshold modulation.
pub fn regSkipTh(g: *const Genome, rc: RegCtx, base_th: f32) f32 {
    const m = 1.0 + regGain(g, 4) * (2.0 * rc.mv_n - 1.0);
    return base_th * @max(0.5, @min(2.0, m));
}

pub inline fn clamp01(x: f32) f32 {
    return @max(0.0, @min(1.0, x));
}

test "parse v1 and v2 lines" {
    const g1 = try parseLine("1 0 0 0 7 0.1 0.9 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.05 0.5 0.5 0.5 0.11 0.22");
    try std.testing.expect(g1 != null);
    try std.testing.expectEqual(@as(u64, 1), g1.?.id);
    try std.testing.expectEqual(@as(u32, 8), blockSizeLegacyForTest(&g1.?));
    // v1 line: regulators neutral, v0.4 genes at legacy 0
    try std.testing.expectEqual(@as(f32, 0.5), g1.?.reg[0]);
    try std.testing.expectEqual(@as(f32, 0.5), g1.?.reg[5]);
    try std.testing.expectEqual(@as(f32, 0.0), g1.?.g[16]);
    try std.testing.expectEqual(@as(f32, 0.0), g1.?.g[17]);
    const g2 = try parseLine("2 0 0 0 7 0.1 0.9 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.05 0.5 0.5 0.5 0.11 0.22 0.9 0.1 0.5 0.5 0.5 0.7");
    try std.testing.expect(g2 != null);
    try std.testing.expectEqual(@as(f32, 0.9), g2.?.reg[0]);
    try std.testing.expectEqual(@as(f32, 0.1), g2.?.reg[1]);
    try std.testing.expectEqual(@as(f32, 0.7), g2.?.reg[5]);
    try std.testing.expectEqual(@as(f32, 0.0), g2.?.g[16]);
}

test "parse and format v3 lines round-trip" {
    var buf: [512]u8 = undefined;
    var g = Genome{ .id = 77, .gen = 3, .pa = 9, .pb = 11, .tribe = 5, .g = @splat(0.5) };
    g.g[16] = 0.9;
    g.g[17] = 0.35;
    g.reg[2] = 0.8;
    const line = try formatLine(&g, &buf);
    const back = try parseLine(line);
    try std.testing.expect(back != null);
    try std.testing.expectEqual(@as(u64, 77), back.?.id);
    try std.testing.expectEqual(@as(f32, 0.9), back.?.g[16]);
    try std.testing.expectEqual(@as(f32, 0.35), back.?.g[17]);
    try std.testing.expectEqual(@as(f32, 0.8), back.?.reg[2]);
    var ntok: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, " ");
    while (it.next()) |_| ntok += 1;
    try std.testing.expectEqual(@as(usize, 29), ntok);
}

// The legacy test asserted an 8-or-16 block size gene that was never wired
// into the codec (placebo). The gene is repurposed as dz_dc; keep a trivial
// sanity anchor here instead.
fn blockSizeLegacyForTest(g: *const Genome) u32 {
    _ = g;
    return 8;
}

test "regulators neutral at 0.5, bounded elsewhere" {
    var g = Genome{ .id = 0, .gen = 0, .pa = 0, .pb = 0, .tribe = 0, .g = @splat(0.5) };
    const rc = RegCtx{ .mv_n = 1.0, .by_n = 1.0, .gop = 0.9, .intra = true };
    // all-neutral -> exactly 1.0
    try std.testing.expectEqual(@as(f32, 1.0), regQMod(&g, rc));
    try std.testing.expectEqual(@as(f32, 1.0), regDeadzone(&g, rc, 3.0) / 3.0);
    // extreme genes -> bounded
    for (0..NR) |i| g.reg[i] = 1.0;
    const m = regQMod(&g, rc);
    try std.testing.expect(m >= 0.5 and m <= 2.0);
    const dz = regDeadzone(&g, rc, 3.0);
    try std.testing.expect(dz >= 1.5 and dz <= 6.0);
}
