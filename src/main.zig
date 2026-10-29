// main.zig — arena CLI.
//   arena eval --corpus DIR --pop FILE --out FILE [--slow]
//     Loads clips from DIR/corpus.txt (name w h frames fps), evaluates every
//     genome in POP, writes CSV: id,psnr,bpp,enc_ms_x10,dec_mops
//   arena psnr A.yuv B.yuv W H FRAMES   — mean Y-PSNR between two raw files

const std = @import("std");
const yuv = @import("yuv.zig");
const gen = @import("genome.zig");
const codec = @import("codec.zig");
const screen = @import("screen.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();

    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer arg_it.deinit();
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(alloc);
    while (arg_it.next()) |a| {
        try args.append(alloc, try alloc.dupe(u8, a));
    }
    defer for (args.items) |a| alloc.free(a);

    if (args.items.len < 2) {
        usage();
        return error.BadArgs;
    }

    if (std.mem.eql(u8, args.items[1], "psnr")) {
        if (args.items.len < 7) return error.BadArgs;
        const w = try std.fmt.parseInt(u32, args.items[4], 10);
        const h = try std.fmt.parseInt(u32, args.items[5], 10);
        const frames = try std.fmt.parseInt(u32, args.items[6], 10);
        const a = try yuv.loadClip(alloc, io, args.items[2], "a", w, h, frames, 24);
        const b = try yuv.loadClip(alloc, io, args.items[3], "b", w, h, frames, 24);
        var acc: f32 = 0;
        var acc_u: f32 = 0;
        var acc_v: f32 = 0;
        for (0..frames) |i| {
            acc += yuv.psnrPlane(a.frameY(@intCast(i)), b.frameY(@intCast(i)));
            acc_u += yuv.psnrPlane(a.frameU(@intCast(i)), b.frameU(@intCast(i)));
            acc_v += yuv.psnrPlane(a.frameV(@intCast(i)), b.frameV(@intCast(i)));
        }
        const nframes: f32 = @floatFromInt(frames);
        const mean = acc / nframes;
        const mean_u = acc_u / nframes;
        const mean_v = acc_v / nframes;
        var buf: [96]u8 = undefined;
        // v0.5d: "Y U V" (anchor.py parses all three; first value unchanged)
        const s = try std.fmt.bufPrint(&buf, "{d:.4} {d:.4} {d:.4}\n", .{ mean, mean_u, mean_v });
        try std.Io.File.stdout().writeStreamingAll(io, s);
        return;
    }

    if (std.mem.eql(u8, args.items[1], "eval")) {
        var corpus_dir: []const u8 = "corpus/raw";
        var pop_path: []const u8 = "pop/seed.txt";
        var out_path: []const u8 = "results.csv";
        var fast = true;
        var i: usize = 2;
        while (i < args.items.len) : (i += 1) {
            if (std.mem.eql(u8, args.items[i], "--corpus") and i + 1 < args.items.len) {
                i += 1;
                corpus_dir = args.items[i];
            } else if (std.mem.eql(u8, args.items[i], "--pop") and i + 1 < args.items.len) {
                i += 1;
                pop_path = args.items[i];
            } else if (std.mem.eql(u8, args.items[i], "--out") and i + 1 < args.items.len) {
                i += 1;
                out_path = args.items[i];
            } else if (std.mem.eql(u8, args.items[i], "--slow")) {
                fast = false;
            }
        }
        try evalAll(alloc, io, corpus_dir, pop_path, out_path, fast);
        return;
    }

    if (std.mem.eql(u8, args.items[1], "screen")) {
        try screenCmd(alloc, io, args.items[2..]);
        return;
    }

    if (std.mem.eql(u8, args.items[1], "debug")) {
        // arena debug CLIP.yuv W H FRAMES POPLINE...
        const w = try std.fmt.parseInt(u32, args.items[3], 10);
        const h = try std.fmt.parseInt(u32, args.items[4], 10);
        const fr = try std.fmt.parseInt(u32, args.items[5], 10);
        const clip = try yuv.loadClip(alloc, io, args.items[2], "dbg", w, h, fr, 24);
        const gm = try gen.parseLine(args.items[6]);
        var reports = std.ArrayList(codec.DebugReport).empty;
        try codec.debugRoundtrip(alloc, &clip, &gm.?, .{}, &reports, alloc);
        for (reports.items) |r| {
            std.debug.print("frame {d:2}  enc {d:6.2}  dec {d:6.2}  first_bad {d:6}  maxd {d}\n", .{ r.frame, r.enc_y_psnr, r.dec_y_psnr, r.first_bad_block, r.max_delta });
        }
        return;
    }

    usage();
    return error.BadArgs;
}

fn usage() void {
    std.debug.print(
        \\arena — evolutionary codec arena evaluator
        \\  eval --corpus DIR --pop FILE --out FILE [--slow]
        \\  screen --model FILE --elites POPFILE --out POPFILE --count-out FILE
        \\         --lambda N --keep K --seed S [--threads T] [--sigma F] [--jump F] [--imm F]
        \\  psnr A.yuv B.yuv W H FRAMES
        \\
    , .{});
}

fn screenCmd(alloc: std.mem.Allocator, io: std.Io, a: []const []const u8) !void {
    var model_path: []const u8 = "state/surrogate.txt";
    var elites_path: []const u8 = "out/elites.txt";
    var out_path: []const u8 = "out/promoted.txt";
    var count_out: []const u8 = "out/screens.txt";
    var cfg = screen.Cfg{ .lambda = 1_000_000, .keep = 192, .seed = 42 };
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        const arg = a[i];
        if (i + 1 >= a.len and arg.len > 0 and arg[0] == '-') return error.BadArgs;
        if (std.mem.eql(u8, arg, "--model")) {
            i += 1;
            model_path = a[i];
        } else if (std.mem.eql(u8, arg, "--elites")) {
            i += 1;
            elites_path = a[i];
        } else if (std.mem.eql(u8, arg, "--out")) {
            i += 1;
            out_path = a[i];
        } else if (std.mem.eql(u8, arg, "--count-out")) {
            i += 1;
            count_out = a[i];
        } else if (std.mem.eql(u8, arg, "--lambda")) {
            i += 1;
            cfg.lambda = try std.fmt.parseInt(u64, a[i], 10);
        } else if (std.mem.eql(u8, arg, "--keep")) {
            i += 1;
            cfg.keep = try std.fmt.parseInt(usize, a[i], 10);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            i += 1;
            cfg.seed = try std.fmt.parseInt(u64, a[i], 10);
        } else if (std.mem.eql(u8, arg, "--threads")) {
            i += 1;
            cfg.threads = try std.fmt.parseInt(usize, a[i], 10);
        } else if (std.mem.eql(u8, arg, "--sigma")) {
            i += 1;
            cfg.sigma = try std.fmt.parseFloat(f32, a[i]);
        } else if (std.mem.eql(u8, arg, "--jump")) {
            i += 1;
            cfg.jump_p = try std.fmt.parseFloat(f32, a[i]);
        } else if (std.mem.eql(u8, arg, "--imm")) {
            i += 1;
            cfg.imm_p = try std.fmt.parseFloat(f32, a[i]);
        }
    }
    var model = try screen.loadModel(alloc, io, model_path);

    const dir = std.Io.Dir.cwd();
    const pop_txt = try dir.readFileAlloc(io, elites_path, alloc, .limited(1 << 22));
    var elites = std.ArrayList(gen.Genome).empty;
    defer elites.deinit(alloc);
    var it = std.mem.tokenizeAny(u8, pop_txt, "\n");
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const gm = gen.parseLine(line) catch continue;
        if (gm) |g| try elites.append(alloc, g);
    }
    if (elites.items.len < 2) return error.NeedTwoElites;

    const total = try screen.run(alloc, io, cfg, &model, elites.items, out_path, count_out);
    std.debug.print("screen: {d} candidates scored, top {d} promoted\n", .{ total, cfg.keep });
}

fn evalAll(
    alloc: std.mem.Allocator,
    io: std.Io,
    corpus_dir: []const u8,
    pop_path: []const u8,
    out_path: []const u8,
    fast: bool,
) !void {
    const dir = std.Io.Dir.cwd();

    // corpus spec: lines "name w h frames fps"
    const spec_path = try std.fmt.allocPrint(alloc, "{s}/corpus.txt", .{corpus_dir});
    defer alloc.free(spec_path);
    const spec_txt = try dir.readFileAlloc(io, spec_path, alloc, .limited(1 << 20));
    var clips = std.ArrayList(yuv.Clip).empty;
    defer clips.deinit(alloc);

    var it = std.mem.tokenizeAny(u8, spec_txt, "\n");
    while (it.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var t = std.mem.tokenizeAny(u8, line, " \t");
        const name = t.next() orelse continue;
        const w = try std.fmt.parseInt(u32, t.next() orelse return error.BadSpec, 10);
        const h = try std.fmt.parseInt(u32, t.next() orelse return error.BadSpec, 10);
        const fr = try std.fmt.parseInt(u32, t.next() orelse return error.BadSpec, 10);
        const fps = try std.fmt.parseInt(u32, t.next() orelse return error.BadSpec, 10);
        const yuv_path = try std.fmt.allocPrint(alloc, "{s}/{s}.yuv", .{ corpus_dir, name });
        const clip = try yuv.loadClip(alloc, io, yuv_path, try alloc.dupe(u8, name), w, h, fr, fps);
        try clips.append(alloc, clip);
    }
    if (clips.items.len == 0) return error.NoClips;

    const pop_txt = try dir.readFileAlloc(io, pop_path, alloc, .limited(1 << 24));
    const out_file = try dir.createFile(io, out_path, .{});
    defer out_file.close(io);

    var wbuf: [4096]u8 = undefined;
    var fit = std.mem.tokenizeAny(u8, pop_txt, "\n");
    var n_ok: u64 = 0;
    var n_bad: u64 = 0;
    while (fit.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        const gm = gen.parseLine(line) catch {
            n_bad += 1;
            continue;
        };
        if (gm == null) continue;
        var g = gm.?;

        var tot_bytes: u64 = 0;
        var tot_px: u64 = 0;
        var tot_enc_mops: f32 = 0;
        var tot_dec_mops: f32 = 0;
        var tot_enc_ms: f32 = 0;
        var acc_psnr: f32 = 0;
        var acc_psnr_u: f32 = 0;
        var acc_psnr_v: f32 = 0;
        var failed = false;

        for (clips.items) |*clip| {
            const st = codec.evalClip(alloc, io, clip, &g, .{ .fast_sad = fast }) catch |e| {
                std.debug.print("[evalClip error: {any} clip={s}]\n", .{ e, clip.name });
                failed = true;
                break;
            };
            tot_bytes += st.bytes;
            acc_psnr += st.psnr_y;
            acc_psnr_u += st.psnr_u;
            acc_psnr_v += st.psnr_v;
            tot_enc_mops += st.enc_mops;
            tot_dec_mops += st.dec_mops;
            tot_enc_ms += st.enc_ms;
            const px = @as(u64, clip.frames) * (@as(u64, clip.w) * @as(u64, clip.h)) * 3 / 2;
            tot_px += px;
        }
        if (failed or tot_px == 0) {
            n_bad += 1;
            continue;
        }
        const nclips: f32 = @floatFromInt(clips.items.len);
        const psnr = acc_psnr / nclips;
        const psnr_u = acc_psnr_u / nclips;
        const psnr_v = acc_psnr_v / nclips;
        const bpp = @as(f64, @floatFromInt(tot_bytes)) * 8.0 / @as(f64, @floatFromInt(tot_px));

        // v0.5d: two appended columns (psnr_u, psnr_v). Consumers must parse
        // with len >= 5; the first five columns are byte-identical to v0.5c.
        const line_out = try std.fmt.bufPrint(&wbuf, "{d},{d:.2},{d:.4},{d:.1},{d:.2},{d:.2},{d:.2}\n", .{
            g.id,
            psnr,
            bpp,
            tot_enc_ms * 10.0,
            tot_dec_mops,
            psnr_u,
            psnr_v,
        });
        try out_file.writeStreamingAll(io, line_out);
        n_ok += 1;
    }
    std.debug.print("eval: {d} ok, {d} bad, {d} clips\n", .{ n_ok, n_bad, clips.items.len });
}
