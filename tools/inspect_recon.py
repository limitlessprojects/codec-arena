#!/usr/bin/env python3
"""inspect_recon.py — dig into per-frame metric behavior for one clip.
Compares source vs dumped recon frame-by-frame: PSNR, numpy MS-SSIM,
error structure (where the error lives), per-scale SSIM components."""
import sys
import math
import numpy as np
sys.path.insert(0, "tools")
from ref_msssim import ms_ssim, gaussian_kernel_1d, filt_valid, downsample2, W5, C1, C2


def load_planar(path, w, h, frames):
    ysz, csz = w * h, w * h // 4
    data = np.fromfile(path, dtype=np.uint8)
    y = data[:frames * ysz].reshape(frames, h, w)
    u = data[frames * ysz:frames * (ysz + csz)].reshape(frames, h // 2, w // 2)
    v = data[frames * (ysz + csz):frames * (ysz + 2 * csz)].reshape(frames, h // 2, w // 2)
    return y, u, v


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "grid"
    w, h, frames = 320, 192, 24
    sy, su, sv = load_planar(f"corpus/raw/{name}.yuv", w, h, frames)
    ry, ru, rv = load_planar(f"/tmp/recon/{name}.recon.yuv", w, h, frames)
    print(f"clip {name}: per-frame Y comparison (src vs recon)")
    for f in range(frames):
        a, b = sy[f], ry[f]
        d = a.astype(np.float64) - b.astype(np.float64)
        mse = (d * d).mean()
        psnr = 99 if mse <= 1e-7 else 10 * math.log10(255**2 / mse)
        m = ms_ssim(a, b)
        # error structure
        p999 = np.percentile(np.abs(d), 99.9)
        mx = np.abs(d).max()
        print(f"  f{f:2d}  psnr {psnr:7.2f}  msssim {m:.5f}  mse {mse:9.4f}  "
              f"max|e| {mx:6.1f}  p99.9|e| {p999:6.2f}  frac|e|>4 {(np.abs(d)>4).mean():.5f}")
    # per-scale components on worst frame
    diffs = [ms_ssim(sy[f], ry[f]) for f in range(frames)]
    worst = int(np.argmin(diffs))
    print(f"\nworst frame f{worst}: per-scale (l, cs):")
    k = gaussian_kernel_1d()
    x, y = sy[worst].astype(np.float64), ry[worst].astype(np.float64)
    for s in range(5):
        mx1 = filt_valid(x, k); my1 = filt_valid(y, k)
        mxx = filt_valid(x * x, k); myy = filt_valid(y * y, k); mxy = filt_valid(x * y, k)
        l = (2 * mx1 * my1 + C1) / (mx1 * mx1 + my1 * my1 + C1)
        cs = (2 * (mxy - mx1 * my1) + C2) / ((mxx - mx1 * mx1) + (myy - my1 * my1) + C2)
        print(f"  scale {s+1}: l={l.mean():.5f} cs={cs.mean():.5f}  ({x.shape[1]}x{x.shape[0]})")
        x = downsample2(x); y = downsample2(y)


if __name__ == "__main__":
    main()
