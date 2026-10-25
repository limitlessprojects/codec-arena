// genome.zig — a bot is 16 genes in [0,1] plus lineage. The brain breeds them;
// the codec only needs to read them.

pub const NG: usize = 16;

pub const Genome = struct {
    id: u64,
    gen: u32,
    pa: u64,
    pb: u64,
    tribe: u32,
    g: [NG]f32,
};

pub const GeneNames = [_][]const u8{
    "keyint",     "blk",      "search",   "baseq",
    "q_low",      "q_mid",    "q_high",   "deadzone",
    "skip",       "p_qmul",   "ent_mode", "dither",
    "halfpel",    "refresh",  "adaptq",   "chroma_q",
};

/// Parse one pop-file line:
///   id gen pa pb tribe g0 g1 ... g15   (19 whitespace-separated tokens)
pub fn parseLine(line: []const u8) !?Genome {
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    var tok: [21][]const u8 = undefined;
    var n: usize = 0;
    while (it.next()) |t| {
        if (n >= 21) return error.BadLine;
        tok[n] = t;
        n += 1;
    }
    if (n != 21) return null;
    if (tok[0].len > 0 and tok[0][0] == '#') return null;
    var gm = Genome{
        .id = try std.fmt.parseInt(u64, tok[0], 10),
        .gen = try std.fmt.parseInt(u32, tok[1], 10),
        .pa = try std.fmt.parseInt(u64, tok[2], 10),
        .pb = try std.fmt.parseInt(u64, tok[3], 10),
        .tribe = try std.fmt.parseInt(u32, tok[4], 10),
        .g = undefined,
    };
    for (0..NG) |i| {
        gm.g[i] = try std.fmt.parseFloat(f32, tok[5 + i]);
    }
    return gm;
}

// ---- gene mappings (the phenotype) ----

pub fn keyInt(g: *const Genome) u32 {
    return 1 + @as(u32, @intFromFloat(clamp01(g.g[0]) * 47.0));
}
pub fn blockSize(g: *const Genome) u32 {
    return if (g.g[1] < 0.5) 8 else 16;
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
pub fn entMode(g: *const Genome) u2 {
    return if (g.g[10] < 0.5) 0 else 1;
}
pub fn dither(g: *const Genome) f32 {
    return (clamp01(g.g[11]) - 0.5) * 1.0;
}
pub fn halfPel(g: *const Genome) bool {
    return g.g[12] > 0.6;
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

pub inline fn clamp01(x: f32) f32 {
    return @max(0.0, @min(1.0, x));
}

test "parse" {
    const g = try parseLine("1 0 0 0 7 0.1 0.9 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 0.05 0.5 0.5 0.5 0.11 0.22");
    try std.testing.expect(g != null);
    try std.testing.expectEqual(@as(u64, 1), g.?.id);
    try std.testing.expectEqual(@as(u32, 8), blockSize(&g.?));
}

const std = @import("std");
