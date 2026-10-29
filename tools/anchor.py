#!/usr/bin/env python3
"""anchor.py — benchmark the arena against REAL codecs via ffmpeg.

For every corpus clip, encode with x264 / x265 / libsvtav1 / libaom-av1 at
several rate points, decode back to raw, and measure PSNR with the SAME
instrument the arena uses (zig `arena psnr`) so numbers are comparable.

Writes benchmarks/baseline.json:
  { target_psnr: <x264 reference quality point>,
    codecs: { x264: [{qp, psnr, bpp}...], ... } }

Only codecs ffmpeg actually supports are measured; missing ones are recorded
as unavailable. Run from repo root.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

CLIP_SETTINGS = [
    # (codec label, ffmpeg -c:v, rate-control args)
    ("x264", "libx264", [["-qp", "24"], ["-qp", "32"], ["-qp", "40"]]),
    ("x265", "libx265", [["-qp", "28"], ["-qp", "35"], ["-qp", "42"]]),
    ("svtav1", "libsvtav1", [["-crf", "32"], ["-crf", "42"], ["-crf", "52"]]),
    ("libaom", "libaom-av1", [["-crf", "32"], ["-crf", "42"], ["-crf", "52"]]),
]


def read_corpus(path):
    clips = []
    with open(path) as f:
        for line in f:
            t = line.split()
            if len(t) == 5:
                clips.append((t[0], int(t[1]), int(t[2]), int(t[3]), int(t[4])))
    return clips


def ffmpeg_args(codec, rc):
    extra = []
    if codec == "libx264":
        extra = ["-preset", "medium"]
    elif codec == "libx265":
        extra = ["-preset", "medium"]
    elif codec == "libsvtav1":
        extra = ["-preset", "8"]
    elif codec == "libaom-av1":
        extra = ["-cpu-used", "6", "-row-mt", "1"]
    return ["-c:v", codec] + rc + extra


def psnr_via_arena(zig, a, b, w, h, frames):
    """v0.5d: returns (psnr_y, psnr_u, psnr_v). The arena psnr tool prints all
    three; older binaries print only Y — handled gracefully."""
    r = subprocess.run([zig, "psnr", a, b, str(w), str(h), str(frames)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr)
    toks = r.stdout.split()
    y = float(toks[0])
    u = float(toks[1]) if len(toks) > 1 else None
    v = float(toks[2]) if len(toks) > 2 else None
    return y, u, v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", default="corpus/raw")
    ap.add_argument("--out", default="benchmarks/baseline.json")
    ap.add_argument("--zig", default="zig-out/bin/arena")
    args = ap.parse_args()

    clips = read_corpus(os.path.join(args.corpus, "corpus.txt"))
    results = {"target_psnr": None, "codecs": {}}

    for label, codec, rate_points in CLIP_SETTINGS:
        if shutil.which("ffmpeg") is None:
            continue
        # availability probe
        probe = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"],
                               capture_output=True, text=True)
        if codec not in probe.stdout:
            results["codecs"][label] = "unavailable"
            continue
        points = []
        for rc in rate_points:
            tot_bits = 0
            tot_px = 0
            acc_psnr = 0.0
            acc_u = 0.0
            acc_v = 0.0
            n_planes = 0
            ok = True
            for name, w, h, frames, fps in clips:
                src = os.path.join(args.corpus, f"{name}.yuv")
                with tempfile.TemporaryDirectory() as td:
                    enc = os.path.join(td, "out.mkv")
                    dec = os.path.join(td, "dec.yuv")
                    r = subprocess.run(
                        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                         "-f", "rawvideo", "-pix_fmt", "yuv420p",
                         "-s", f"{w}x{h}", "-r", str(fps), "-i", src]
                        + ffmpeg_args(codec, rc) + [enc],
                        capture_output=True)
                    if r.returncode != 0:
                        ok = False
                        break
                    tot_bits += os.path.getsize(enc) * 8
                    r2 = subprocess.run(
                        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                         "-i", enc, "-f", "rawvideo", "-pix_fmt", "yuv420p", dec],
                        capture_output=True)
                    if r2.returncode != 0:
                        ok = False
                        break
                    y, u, v = psnr_via_arena(args.zig, src, dec, w, h, frames)
                    acc_psnr += y
                    if u is not None:
                        acc_u += u
                        acc_v += v
                        n_planes += 1
                    tot_px += frames * w * h * 3 // 2
            if ok and tot_px:
                pt = {
                    "rc": " ".join(rc),
                    "psnr": round(acc_psnr / len(clips), 2),
                    "bpp": round(tot_bits / tot_px, 4),
                }
                if n_planes:
                    pt["psnr_u"] = round(acc_u / n_planes, 2)
                    pt["psnr_v"] = round(acc_v / n_planes, 2)
                points.append(pt)
        results["codecs"][label] = points
        print(label, points)

    # target quality = the x264 point closest to 34 dB (arena's standard bar)
    x264 = [p for p in results["codecs"].get("x264", []) if isinstance(p, dict)]
    if x264:
        results["target_psnr"] = min(x264, key=lambda p: abs(p["psnr"] - 34.0))["psnr"]

    out_dir = os.path.dirname(args.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(results, f, indent=1)
    print("target_psnr:", results["target_psnr"])


if __name__ == "__main__":
    main()
