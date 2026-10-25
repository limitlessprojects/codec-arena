// screen.zig — the mass-screening instrument of Codec Arena.
//
// The oracle (arena eval) measures a bot by really encoding+decoding the
// corpus: ~0.26s per bot. That honesty is the arena's floor, and it caps
// throughput at ~10^5 evals per run. The screen is the second instrument:
// a quadratic response surface fit on every oracle evaluation so far
// (state/surrogate.txt) scores candidate genomes in ~tens of nanoseconds.
// A generation synthesizes billions of candidate bots, the surrogate ranks
// them, and only the survivors earn an oracle measurement. Two instruments,
// two counters, both honest: `lifetime_evals` (oracle) never borrows from
// `search_evals` (every genome any instrument ever scored).
//
// CLI (wired in main.zig):
//   arena screen --model FILE --elites POPFILE --out POPFILE
//                --count-out FILE --lambda N --keep K --seed S
//                [--threads T] [--sigma F] [--jump F] [--imm F]
//
// Deterministic: splitmix64 per (seed, thread). Same inputs, same survivors.

const std = @import("std");
const gen = @import("genome.zig");

pub const Model = struct {
    w0: f32,
    w_lin: [16]f32,
    w_quad: [256]f32, // flat 16x16, zeros in strict upper triangle

    /// Expand the compact 153-weight layout (1 + 16 + 136, triangular)
    /// into the flat SIMD-friendly layout. Feature idx 17+T(i)+j maps to
    /// quad[i*16+j], T(i)=i*(i+1)/2.
    pub fn fromCompact(w: *const [153]f32) Model {
        var m: Model = undefined;
        m.w0 = w[0];
        m.w_lin = undefined;
        @memset(&m.w_quad, 0);
        for (0..16) |i| m.w_lin[i] = w[1 + i];
        var idx: usize = 17;
        for (0..16) |i| {
            for (0..i + 1) |j| {
                m.w_quad[i * 16 + j] = w[idx];
                idx += 1;
            }
        }
        return m;
    }

    pub inline fn score(self: *const Model, g: *const [16]f32) f32 {
        const gv: @Vector(16, f32) = g.*;
        const lv: @Vector(16, f32) = self.w_lin;
        var acc: @Vector(16, f32) = @splat(self.w0);
        acc += lv * gv;
        var sum: @Vector(16, f32) = @splat(0.0);
        for (0..16) |i| {
            const row: @Vector(16, f32) = gv * @as(@Vector(16, f32), @splat(g[i]));
            const wv: @Vector(16, f32) = self.w_quad[i * 16 ..][0..16].*;
            sum += wv * row;
        }
        return @reduce(.Add, acc + sum);
    }
};

pub fn loadModel(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !Model {
    const dir = std.Io.Dir.cwd();
    const txt = try dir.readFileAlloc(io, path, alloc, .limited(1 << 20));
    var it = std.mem.tokenizeAny(u8, txt, " \t\r\n");
    const n = try std.fmt.parseInt(usize, it.next() orelse return error.BadModel, 10);
    if (n != 153) return error.BadModel;
    var w: [153]f32 = undefined;
    for (0..153) |i| {
        const tok = it.next() orelse return error.BadModel;
        w[i] = try std.fmt.parseFloat(f32, tok);
    }
    return Model.fromCompact(&w);
}

pub const Cfg = struct {
    lambda: u64,
    keep: usize,
    seed: u64,
    threads: usize = 4,
    sigma: f32 = 0.12,
    jump_p: f32 = 0.02,
    imm_p: f32 = 0.01,
};

const Lineage = struct {
    pa: u64,
    pb: u64,
    tribe: u32,
};

const Slot = struct {
    score: f32,
    g: [16]f32,
    lin: Lineage,
};

const Heap = struct {
    k: usize,
    n: usize = 0,
    slots: []Slot,

    fn init(alloc: std.mem.Allocator, k: usize) !Heap {
        const slots = try alloc.alloc(Slot, k);
        return .{ .k = k, .slots = slots };
    }

    inline fn worse(self: *const Heap) f32 {
        if (self.n < self.k) return -std.math.floatMax(f32);
        return self.slots[0].score;
    }

    fn offer(self: *Heap, s: Slot) void {
        if (self.n < self.k) {
            self.slots[self.n] = s;
            var i = self.n;
            self.n += 1;
            while (i > 0) {
                const parent = (i - 1) / 2;
                if (self.slots[parent].score <= self.slots[i].score) break;
                std.mem.swap(Slot, &self.slots[parent], &self.slots[i]);
                i = parent;
            }
            return;
        }
        if (s.score <= self.slots[0].score) return;
        self.slots[0] = s;
        var i: usize = 0;
        while (true) {
            const l = 2 * i + 1;
            const r = 2 * i + 2;
            var m = i;
            if (l < self.k and self.slots[l].score < self.slots[m].score) m = l;
            if (r < self.k and self.slots[r].score < self.slots[m].score) m = r;
            if (m == i) break;
            std.mem.swap(Slot, &self.slots[m], &self.slots[i]);
            i = m;
        }
    }
};

const Rng = struct {
    s: u64,

    fn init(seed: u64) Rng {
        return .{ .s = seed };
    }

    fn next(inout: *Rng) u64 {
        inout.s +%= 0x9E3779B97F4A7C15;
        var z = inout.s;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }

    inline fn unit(inout: *Rng) f32 {
        return @as(f32, @floatFromInt(inout.next() >> 40)) * (1.0 / 16777216.0);
    }
};

const WorkerCtx = struct {
    cfg: Cfg,
    model: *const Model,
    elites: []const gen.Genome,
    my_lambda: u64,
    rng_seed: u64,
    heap: Heap,
    screens: u64,
};

fn worker(ctx: *WorkerCtx) void {
    var rng = Rng.init(ctx.rng_seed);
    const ne = ctx.elites.len;
    var g: [16]f32 = undefined;
    var i: u64 = 0;
    while (i < ctx.my_lambda) : (i += 1) {
        // --- synthesize one candidate bot ---
        const ea = &ctx.elites[(rng.next() >> 32) % ne];
        const eb = &ctx.elites[(rng.next() >> 32) % ne];
        const lin = Lineage{ .pa = ea.id, .pb = eb.id, .tribe = ea.tribe };
        if (rng.unit() < ctx.cfg.imm_p) {
            // immigrant: fully random genome
            for (0..16) |k| g[k] = rng.unit();
        } else {
            for (0..16) |k| {
                var v = if (rng.next() & 1 == 0) ea.g[k] else eb.g[k];
                v += (rng.unit() - 0.5) * 2.0 * ctx.cfg.sigma;
                g[k] = gen.clamp01(v);
            }
        }
        if (rng.unit() < ctx.cfg.jump_p) {
            g[(rng.next() >> 32) % 16] = rng.unit();
        }
        // --- score by the surrogate ---
        const s = ctx.model.score(&g);
        ctx.screens += 1;
        ctx.heap.offer(.{ .score = s, .g = g, .lin = lin });
    }
}

pub fn run(
    alloc: std.mem.Allocator,
    io: std.Io,
    cfg: Cfg,
    model: *const Model,
    elites: []const gen.Genome,
    out_path: []const u8,
    count_out: []const u8,
) !u64 {
    if (elites.len < 2) return error.NeedTwoElites;
    const nthreads = @max(1, @min(cfg.threads, cfg.lambda));

    var heaps = try alloc.alloc(Heap, nthreads);
    var ctxs = try alloc.alloc(WorkerCtx, nthreads);
    var threads = try alloc.alloc(?std.Thread, nthreads);

    const per: u64 = cfg.lambda / nthreads;
    var issued: u64 = 0;
    for (0..nthreads) |t| {
        const my = if (t == nthreads - 1) cfg.lambda - issued else per;
        issued += per;
        heaps[t] = try Heap.init(alloc, cfg.keep);
        ctxs[t] = .{
            .cfg = cfg,
            .model = model,
            .elites = elites,
            .my_lambda = my,
            .rng_seed = cfg.seed ^ (0x9E3779B97F4A7C15 *% (t + 1)),
            .heap = heaps[t],
            .screens = 0,
        };
        threads[t] = std.Thread.spawn(.{}, worker, .{&ctxs[t]}) catch |e| blk: {
            if (t > 0) {
                // fall back: run this slice inline, join the rest below
                break :blk null;
            } else {
                return e;
            }
        };
        if (threads[t] == null) worker(&ctxs[t]);
    }
    var total: u64 = 0;
    for (0..nthreads) |t| {
        if (threads[t]) |*th| {
            th.join();
        }
        total += ctxs[t].screens;
    }

    // merge heaps -> global top-K (desc)
    var all = try alloc.alloc(Slot, nthreads * cfg.keep);
    var n: usize = 0;
    for (0..nthreads) |t| {
        for (heaps[t].slots[0..heaps[t].n]) |s| {
            all[n] = s;
            n += 1;
        }
    }
    std.mem.sort(Slot, all[0..n], {}, struct {
        fn lt(_: void, a: Slot, b: Slot) bool {
            return a.score > b.score;
        }
    }.lt);
    const out_n = @min(n, cfg.keep);

    const dir = std.Io.Dir.cwd();
    const out_file = try dir.createFile(io, out_path, .{});
    defer out_file.close(io);
    var buf: [512]u8 = undefined;
    for (all[0..out_n]) |s| {
        const line = try std.fmt.bufPrint(&buf, "0 0 {d} {d} {d} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4} {d:.4}\n", .{
            s.lin.pa, s.lin.pb, s.lin.tribe,
            s.g[0],   s.g[1],   s.g[2],   s.g[3],
            s.g[4],   s.g[5],   s.g[6],   s.g[7],
            s.g[8],   s.g[9],   s.g[10],  s.g[11],
            s.g[12],  s.g[13],  s.g[14],  s.g[15],
        });
        try out_file.writeStreamingAll(io, line);
    }
    const cnt = try std.fmt.bufPrint(&buf, "{d}\n", .{total});
    const cf = try dir.createFile(io, count_out, .{});
    defer cf.close(io);
    try cf.writeStreamingAll(io, cnt);
    return total;
}

test "model compact->flat layout" {
    var w: [153]f32 = @splat(0);
    for (0..153) |i| w[i] = @floatFromInt(i);
    const m = Model.fromCompact(&w);
    try std.testing.expectEqual(@as(f32, 0), m.w0);
    try std.testing.expectEqual(@as(f32, 1), m.w_lin[0]);
    // feature idx 17 -> pair (0,0) -> quad[0]
    try std.testing.expectEqual(@as(f32, 17), m.w_quad[0]);
    // feature idx 17+T(1)+0 = 18 -> pair (1,0) -> quad[16]
    try std.testing.expectEqual(@as(f32, 18), m.w_quad[16]);
    // feature idx 17+T(2)+1 = 20 -> pair (2,1) -> quad[2*16+1]
    try std.testing.expectEqual(@as(f32, 20), m.w_quad[33]);
    // strict upper triangle stays zero
    try std.testing.expectEqual(@as(f32, 0), m.w_quad[1]);
}

test "screen deterministic top-k" {
    var w: [153]f32 = @splat(0);
    w[0] = 1.0; // intercept
    w[1 + 3] = 10.0; // baseq dominates
    const m = Model.fromCompact(&w);
    const g_a: [16]f32 = @splat(0.5);
    var g_b: [16]f32 = @splat(0.5);
    g_b[3] = 0.9;
    var elites = [_]gen.Genome{
        .{ .id = 1, .gen = 0, .pa = 0, .pb = 0, .tribe = 1, .g = g_a },
        .{ .id = 2, .gen = 0, .pa = 0, .pb = 0, .tribe = 2, .g = g_b },
    };
    // pure scoring sanity: higher baseq -> higher score
    const s1 = m.score(&elites[0].g);
    const s2 = m.score(&elites[1].g);
    try std.testing.expect(s2 > s1);
}
