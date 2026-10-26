#!/usr/bin/env python3
"""gen_corpus.py — deterministic synthetic corpus for Codec Arena.

Three clips, chosen to stress different parts of the search space:
  drift    — smooth moving content (low entropy; motion search heaven)
  grid     — scrolling checkerboard with pulsing contrast (mid entropy, temporal)
  storm    — drifting pseudo-noise (high entropy ceiling; punishes naive codecs)

Pure stdlib, seeded RNG => byte-identical corpus on every machine.
Writes raw planar YUV420p files + corpus.txt into --out (default corpus/raw).
"""
import argparse
import hashlib
import math
import os
import random
import struct
import sys

W, H, FRAMES, FPS = 320, 192, 24, 24


def write_frame(f, y, u, v):
    f.write(bytes(y))
    f.write(bytes(u))
    f.write(bytes(v))


def clip_drift(rng):
    """Soft ball gliding over a smooth vertical gradient."""
    frames = []
    for t in range(FRAMES):
        y = bytearray()
        bx = int(W * (0.5 + 0.35 * math.sin(2 * math.pi * t / FRAMES)))
        by = int(H * (0.5 + 0.35 * math.cos(2 * math.pi * t / FRAMES)))
        for r in range(H):
            for c in range(W):
                base = 60 + int(80 * r / H)
                d2 = (c - bx) ** 2 + (r - by) ** 2
                if d2 < 900:
                    v = base + 70 - d2 // 30
                    y.append(max(0, min(255, v)))
                else:
                    y.append(base)
        frames.append(y)
    return frames


def clip_grid(rng):
    """Scrolling checker + contrast pulse."""
    frames = []
    for t in range(FRAMES):
        y = bytearray()
        shift = (t * 4) % 32
        pulse = 90 + int(60 * math.sin(2 * math.pi * t / FRAMES))
        for r in range(H):
            for c in range(W):
                cell = ((c + shift) // 16 + r // 16) % 2
                y.append(pulse if cell == 0 else 255 - pulse)
        frames.append(y)
    return frames


def clip_storm(rng):
    """Value noise drifting through seeded octaves — near-random entropy."""
    # one noise field, resampled with a drifting offset each frame
    base = [rng.random() for _ in range(64 * 64)]
    frames = []
    for t in range(FRAMES):
        y = bytearray()
        ox = t * 0.7
        oy = t * 0.35
        for r in range(H):
            for c in range(W):
                fx = (c * 0.2 + ox) % 64
                fy = (r * 0.2 + oy) % 64
                x0, y0 = int(fx), int(fy)
                x1, y1 = (x0 + 1) % 64, (y0 + 1) % 64
                tx, ty = fx - x0, fy - y0
                a = base[y0 * 64 + x0]
                b = base[y0 * 64 + x1]
                cc = base[y1 * 64 + x0]
                d = base[y1 * 64 + x1]
                v = (a * (1 - tx) + b * tx) * (1 - ty) + (cc * (1 - tx) + d * tx) * ty
                y.append(int(v * 255))
        frames.append(y)
    return frames


def clip_quake(rng):
    """High motion: two translating blocks on a shaking gradient background.
    Stresses motion estimation hard — large vectors, fast direction flips."""
    frames = []
    ax, ay, avx, avy = 30.0, 40.0, 9.0, 6.0
    bx, by, bvx, bvy = 230.0, 100.0, -8.0, 5.0
    for t in range(FRAMES):
        y = bytearray()
        shake = ((t * 37) % 9) - 4
        for r in range(H):
            for c in range(W):
                v = 90 + int(50 * math.sin((c + shake) * 0.05)) + int(20 * math.cos((r + shake) * 0.07))
                da = (c - int(ax)) ** 2 + (r - int(ay)) ** 2
                db = (c - int(bx)) ** 2 + (r - int(by)) ** 2
                if da < 1600:
                    v = 235 - da // 40
                if db < 1200:
                    v = 20 + db // 30
                y.append(max(0, min(255, v)))
        ax += avx; ay += avy
        if ax < 20 or ax > W - 20: avx = -avx
        if ay < 20 or ay > H - 20: avy = -avy
        bx += bvx; by += bvy
        if bx < 20 or bx > W - 20: bvx = -bvx
        if by < 20 or by > H - 20: bvy = -bvy
        frames.append(y)
    return frames


def clip_grain(rng):
    """Independent spatiotemporal noise — the entropy ceiling. Motion search
    is useless here; only quantizer discipline and skip logic matter."""
    frames = []
    for t in range(FRAMES):
        y = bytearray()
        lo, hi = 110 + (t % 3) * 12, 150 + (t % 5) * 8
        for r in range(H):
            for c in range(W):
                y.append(lo + rng.randrange(hi - lo))
        frames.append(y)
    return frames


def chroma_from_luma(y_frames):
    us, vs = [], []
    for y in y_frames:
        u, v = bytearray(), bytearray()
        for r in range(H // 2):
            for c in range(W // 2):
                acc = 0
                for dr in range(2):
                    for dc in range(2):
                        acc += y[(2 * r + dr) * W + (2 * c + dc)]
                m = acc // 4
                u.append(max(0, min(255, 128 + (m - 128) // 4)))
                v.append(max(0, min(255, 128 - (m - 128) // 4)))
        us.append(u)
        vs.append(v)
    return us, vs


CLIPS = [
    ("drift", clip_drift),
    ("grid", clip_grid),
    ("storm", clip_storm),
    ("quake", clip_quake),
    ("grain", clip_grain),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="corpus/raw")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    rng = random.Random(0xC0DEC)  # arena-sealed
    lines = []
    hashes = {}
    for name, fn in CLIPS:
        yf = fn(rng)
        uf, vf = chroma_from_luma(yf)
        path = os.path.join(args.out, f"{name}.yuv")
        h = hashlib.sha256()
        with open(path, "wb") as f:
            # global-planar layout: ALL Y frames, then ALL U, then ALL V
            # (matches yuv.zig loadClip)
            for t in range(FRAMES):
                chunk = bytes(yf[t])
                h.update(chunk)
                f.write(chunk)
            for t in range(FRAMES):
                chunk = bytes(uf[t])
                h.update(chunk)
                f.write(chunk)
            for t in range(FRAMES):
                chunk = bytes(vf[t])
                h.update(chunk)
                f.write(chunk)
        hashes[name] = h.hexdigest()
        lines.append(f"{name} {W} {H} {FRAMES} {FPS}")
        print(f"{name}: {os.path.getsize(path)} bytes sha256={hashes[name][:16]}...")

    with open(os.path.join(args.out, "corpus.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(args.out, "manifest.txt"), "w") as f:
        for k, v in hashes.items():
            f.write(f"{k} {v}\n")
    print("corpus ready")


if __name__ == "__main__":
    main()
