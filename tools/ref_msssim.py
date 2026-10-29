#!/usr/bin/env python3
"""ref_msssim.py — textbook numpy MS-SSIM reference (Wang et al. 2003).

Mirrors skimage-style semantics with EXPLICIT valid-mode filtering, gaussian
11x11 sigma=1.5, 2x2 avg-pool downsample, 5 scales — the exact protocol the
Zig oracle implements. Used to cross-validate src/msssim.zig to ~1e-3.

Also dumps two random test planes (seeded) so the Zig side can be checked on
identical inputs via tools/ref_msssim_cases.zig output convention.
"""
import json
import math
import sys
import numpy as np


def gaussian_kernel_1d(k=11, sigma=1.5):
    x = np.arange(k, dtype=np.float64) - (k - 1) / 2.0
    g = np.exp(-(x * x) / (2.0 * sigma * sigma))
    return g / g.sum()


def filt_valid(img, k1d):
    k = len(k1d)
    pad = k // 2  # NOT used: valid mode via explicit slicing
    # horizontal
    H, W = img.shape
    ow = W - k + 1
    tmp = np.zeros((H, ow))
    for i in range(k):
        tmp += k1d[i] * img[:, i:i + ow]
    oh = H - k + 1
    out = np.zeros((oh, ow))
    for i in range(k):
        out += k1d[i] * tmp[i:i + oh, :]
    return out


def downsample2(img):
    H, W = img.shape
    return (img[0:H // 2 * 2:2, 0:W // 2 * 2:2] +
            img[1:H // 2 * 2:2, 0:W // 2 * 2:2] +
            img[0:H // 2 * 2:2, 1:W // 2 * 2:2] +
            img[1:H // 2 * 2:2, 1:W // 2 * 2:2]) / 4.0


W5 = [0.0448, 0.2856, 0.3001, 0.2363, 0.1333]
C1 = (0.01 * 255) ** 2
C2 = (0.03 * 255) ** 2


def ms_ssim(a, b, levels=5):
    a = a.astype(np.float64)
    b = b.astype(np.float64)
    k = gaussian_kernel_1d()
    vals = []
    x, y = a, b
    for s in range(levels):
        if min(x.shape) < 11:
            break
        mx = filt_valid(x, k)
        my = filt_valid(y, k)
        mxx = filt_valid(x * x, k)
        myy = filt_valid(y * y, k)
        mxy = filt_valid(x * y, k)
        vx = mxx - mx * mx
        vy = myy - my * my
        vxy = mxy - mx * my
        l = (2 * mx * my + C1) / (mx * mx + my * my + C1)
        cs = (2 * vxy + C2) / (vx + vy + C2)
        vals.append((l.mean(), cs.mean()))
        x = downsample2(x)
        y = downsample2(y)
    # canonical MS-SSIM: prod cs_i^{w_i} * l_last^{w_last}
    logv = 0.0
    for i, (l, cs) in enumerate(vals):
        logv += W5[i] * math.log(max(cs, 1e-6))
    logv += W5[len(vals) - 1] * math.log(max(vals[-1][0], 1e-6))
    return math.exp(logv)


def dump_cases(path):
    """Write the exact u8 test planes so the Zig oracle can be cross-validated
    on identical inputs: records of u32 w, u32 h, w*h bytes A, w*h bytes B."""
    rng = np.random.RandomState(0xC0DEC)
    H, W = 192, 320
    base = np.tile(np.linspace(30, 220, W).astype(np.float64), (H, 1))
    base += 40 * np.sin(np.arange(H)[:, None] * 0.07)
    base = np.clip(base, 0, 255)
    recs = []
    for sigma in (2, 6, 14, 30):
        noisy = np.clip(base + rng.normal(0, sigma, base.shape), 0, 255)
        recs.append((f"noise{sigma}", base.astype(np.uint8), noisy.astype(np.uint8)))
    blur = np.copy(base)
    blur[:, 1:] = (blur[:, 1:] + blur[:, :-1]) / 2
    recs.append(("blur", base.astype(np.uint8), blur.astype(np.uint8)))
    recs.append(("identical", base.astype(np.uint8), base.astype(np.uint8)))
    r1 = rng.randint(0, 256, (96, 160)).astype(np.uint8)
    r2 = np.clip(r1.astype(int) + rng.randint(-25, 26, r1.shape), 0, 255).astype(np.uint8)
    recs.append(("rand96x160", r1, r2))
    r3 = rng.randint(0, 256, (40, 40)).astype(np.uint8)
    r4 = np.clip(r3.astype(int) + rng.randint(-40, 41, r3.shape), 0, 255).astype(np.uint8)
    recs.append(("rand40x40", r3, r4))
    with open(path, "wb") as f:
        for _, a, b in recs:
            h, w = a.shape
            f.write(w.to_bytes(4, "little"))
            f.write(h.to_bytes(4, "little"))
            f.write(a.tobytes())
            f.write(b.tobytes())
    return recs


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", default=None, help="write u8 case planes to this file")
    args = ap.parse_args()

    if args.dump:
        recs = dump_cases(args.dump)
        out = {}
        for name, a, b in recs:
            v = ms_ssim(a, b)
            out[name] = float(v)
            print(f"{name:14s} msssim = {v:.6f}")
        with open(args.dump + ".expect.json", "w") as f:
            json.dump(out, f, indent=1)
        return


if __name__ == "__main__":
    main()
