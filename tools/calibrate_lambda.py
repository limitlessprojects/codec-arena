#!/usr/bin/env python3
"""calibrate_lambda.py — v0.6a: re-slope the fitness exchange rate for MS-SSIM.

Sweeps the uniform --qscale override (the honest operating-point knob: it
passes through bandQ on BOTH encoder and decoder sides) on the standing
champion and measures:

    slope_msssim = d(msssim_db)/dlog2(bpp)   near the operating point
    lambda_msssim = slope-implied break-even = Δq / Δbpp over one halving

The v0.6a value (3.5) was measured this way on champion 170007151:
0.315 dB given up per 0.0905 bpp saved -> 3.48 -> 3.5.
"""
import argparse
import json
import math
import os
import subprocess
import sys
import tempfile

QSCALES = [0.6, 0.8, 1.0, 1.25, 1.5, 1.8, 2.2, 2.8, 3.5]


def genome_line(c):
    return f"{c['id']} {c['gen']} {c['pa']} {c['pb']} {c['tribe']} " + " ".join(
        f"{x:.4f}" for x in c["g"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--champion", default="halloffame/champion.json")
    ap.add_argument("--corpus", default="corpus/raw")
    ap.add_argument("--zig", default="zig-out/bin/arena")
    ap.add_argument("--json", default=None)
    args = ap.parse_args()

    with open(args.champion) as f:
        c = json.load(f)

    rows = []
    with tempfile.TemporaryDirectory() as td:
        for q in QSCALES:
            pop = os.path.join(td, "p.pop")
            out = os.path.join(td, "r.csv")
            with open(pop, "w") as f:
                f.write(genome_line(c) + "\n")
            cmd = [args.zig, "eval", "--corpus", args.corpus,
                   "--pop", pop, "--out", out]
            if abs(q - 1.0) > 1e-9:
                cmd += ["--qscale", f"{q:.4f}"]
            subprocess.run(cmd, check=True, capture_output=True)
            with open(out) as f:
                t = f.read().strip().split(",")
            rows.append({"qscale": q, "psnr": float(t[1]), "bpp": float(t[2]),
                         "msssim": float(t[7]), "msssim_db": float(t[8])})

    print("RD sweep of champion (uniform qscale override):")
    for r in rows:
        print(f"  q {r['qscale']:.2f}  psnr {r['psnr']:6.2f}  bpp {r['bpp']:.4f}  "
              f"msssim {r['msssim']:.5f}  msssim_db {r['msssim_db']:7.4f}")

    # break-even lambda: quality given up vs bits saved across one halving,
    # measured between the operating point (q=1.0) and the far point with
    # roughly half the bits (nearest row to bpp/2).
    op = next(r for r in rows if r["qscale"] == 1.0)
    half = min(rows, key=lambda r: abs(r["bpp"] - op["bpp"] / 2.0))
    dq = op["msssim_db"] - half["msssim_db"]
    db = op["bpp"] - half["bpp"]
    lam = round(dq / db, 1) if db > 1e-9 else None
    print(f"\noperating point: {op['msssim_db']:.4f} dB @ {op['bpp']:.4f} bpp")
    print(f"half-rate point: {half['msssim_db']:.4f} dB @ {half['bpp']:.4f} bpp (q={half['qscale']})")
    print(f"Δq = {dq:.4f} dB over Δbpp = {db:.4f}")
    print(f"break-even msssim_lambda = {lam}")
    print("(rule: rate term must neither dominate nor vanish vs the measured")
    print(" frontier — the GA raises the frontier; lambda only prices bits.)")

    if args.json:
        with open(args.json, "w") as f:
            json.dump({"curve": rows, "break_even_lambda": lam}, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
