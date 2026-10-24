// yuv.zig — planar YUV420p clip loading + PSNR. No dependencies beyond std.

pub const FramePlan = struct {
    y: []u8,
    u: []u8,
    v: []u8,
};

pub const Clip = struct {
    name: []const u8,
    w: u32,
    h: u32,
    frames: u32,
    fps: u32,
    // all frames stored planar-continuous: frame i Y at i*ys, etc.
    ysz: usize,
    csz: usize,
    y: []u8, // frames * ysz
    u: []u8, // frames * csz
    v: []u8,

    pub fn frameY(self: *const Clip, i: u32) []const u8 {
        return self.y[@as(usize, i) * self.ysz ..][0..self.ysz];
    }
    pub fn frameU(self: *const Clip, i: u32) []const u8 {
        return self.u[@as(usize, i) * self.csz ..][0..self.csz];
    }
    pub fn frameV(self: *const Clip, i: u32) []const u8 {
        return self.v[@as(usize, i) * self.csz ..][0..self.csz];
    }
};

/// Load raw planar YUV420p file. Expected size = frames * (w*h*3/2).
pub fn loadClip(
    alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    name: []const u8,
    w: u32,
    h: u32,
    frames: u32,
    fps: u32,
) !Clip {
    const dir = std.Io.Dir.cwd();
    const data = try dir.readFileAlloc(io, path, alloc, .limited(1 << 28));
    const ysz: usize = @as(usize, w) * @as(usize, h);
    const csz: usize = ysz / 4;
    const total: usize = @as(usize, frames) * (ysz + 2 * csz);
    if (data.len < total) return error.CorruptClip;
    const clip = Clip{
        .name = name,
        .w = w,
        .h = h,
        .frames = frames,
        .fps = fps,
        .ysz = ysz,
        .csz = csz,
        .y = data[0 .. @as(usize, frames) * ysz],
        .u = data[@as(usize, frames) * ysz ..][0 .. @as(usize, frames) * csz],
        .v = data[@as(usize, frames) * (ysz + csz) ..][0 .. @as(usize, frames) * csz],
    };
    return clip;
}

/// PSNR of one plane (dB). a = source, b = recon.
pub fn psnrPlane(a: []const u8, b: []const u8) f32 {
    var acc: f64 = 0.0;
    const n: f64 = @floatFromInt(a.len);
    for (a, b) |x, y| {
        const d: i32 = @as(i32, x) - @as(i32, y);
        const df: f64 = @floatFromInt(d * d);
        acc += df;
    }
    const mse = acc / n;
    if (mse <= 0.0000001) return 99.0;
    const val = 10.0 * @log10(255.0 * 255.0 / mse);
    return @floatCast(@min(val, 99.0));
}

test "psnr identical" {
    const a = [_]u8{ 10, 20, 30 };
    try std.testing.expect(psnrPlane(&a, &a) > 90.0);
}

const std = @import("std");
