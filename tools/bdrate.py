#!/usr/bin/env python3
"""bdrate.py — Bjontegaard delta-rate, the standard codec comparison metric.

Answers "how many % fewer bits does codec A need for the same quality as
codec B?" over a rate-distortion CURVE, not a single point. The arena keeps
RD curves per champion (rd.json: baseq-gene sweep) and per anchor codec
(benchmarks/baseline.json: qp sweeps) — this tool joins them.

Method: monotone piecewise-cubic (PCHIP) integration of log-rate vs PSNR,
the recommended variant over the original cubic-spline BD (which can
oscillate on sparse points). Pure stdlib — no scipy.

References: Bjontegaard 2001; the 2024 tutorial overview (arXiv:2401.04039);
FAU-LMS/bjontegaard python implementations.

Usage:  python3 tools/bdrate.py --rd shard-3/rd.json --baseline benchmarks/baseline.json
        (or import bd_rate(curve_a, curve_b) -> percent)
"""
import math


def _pchip_slopes(xs, ys):
    """Fritsch-Carlson monotone slopes for PCHIP."""
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0] = d[0]
    m[-1] = d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    return m, h


def _pchip_eval(xs, ys, x):
    m, h = _pchip_slopes(xs, ys)
    # locate interval
    lo, hi = 0, len(xs) - 1
    if x <= xs[0]:
        i = 0
    elif x >= xs[-1]:
        i = len(xs) - 2
    else:
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if xs[mid] <= x:
                lo = mid
            else:
                hi = mid
        i = lo
    t = (x - xs[i]) / h[i]
    t2, t3 = t * t, t * t * t
    h00 = 2 * t3 - 3 * t2 + 1
    h10 = t3 - 2 * t2 + t
    h01 = -2 * t3 + 3 * t2
    h11 = t3 - t2
    return h00 * ys[i] + h10 * h[i] * m[i] + h01 * ys[i + 1] + h11 * h[i] * m[i + 1]


def _integrate(xs, ys, lo, hi):
    """Trapezoid integral of the PCHIP curve over [lo, hi]. Points outside the
    data range use the end-segment Hermite (exact for locally-linear RD data,
    mild extrapolation otherwise — bounded by one point spacing)."""
    total = 0.0
    steps = 200
    prev = _pchip_eval(xs, ys, lo)
    for k in range(1, steps + 1):
        x = lo + (hi - lo) * k / steps
        cur = _pchip_eval(xs, ys, x)
        total += (prev + cur) * (hi - lo) / steps / 2
        prev = cur
    return total


def bd_rate(ref, test):
    """BD-rate in %: negative = test needs fewer bits than ref at equal PSNR.
    ref/test: lists of {"psnr": float, "bpp": float}, >= 4 points recommended,
    >= 2 required. PSNR axis is the integration variable (quality range must
    overlap; clipped to the common range)."""
    if len(ref) < 2 or len(test) < 2:
        return None
    r = sorted([(p["psnr"], math.log(p["bpp"])) for p in ref])
    t = sorted([(p["psnr"], math.log(p["bpp"])) for p in test])
    lo = max(r[0][0], t[0][0])
    hi = min(r[-1][0], t[-1][0])
    if hi <= lo:
        return None
    rx = [p for p, _ in r if lo <= p <= hi]
    ry = [v for p, v in r if lo <= p <= hi]
    tx = [p for p, _ in t if lo <= p <= hi]
    ty = [v for p, v in t if lo <= p <= hi]
    if len(rx) < 2 or len(tx) < 2:
        return None
    int_r = _integrate(rx, ry, lo, hi)
    int_t = _integrate(tx, ty, lo, hi)
    avg_r = int_r / (hi - lo)
    avg_t = int_t / (hi - lo)
    return (math.exp(avg_t - avg_r) - 1.0) * 100.0


def champion_vs_anchors(rd, baseline):
    """Join a shard champion's rd.json with the anchor baseline.json.
    Returns [(codec, bd_rate_pct), ...] sorted best-first."""
    curve = [{"psnr": p["psnr"], "bpp": p["bpp"]} for p in rd.get("curve", [])]
    if len(curve) < 2:
        return []
    out = []
    for codec, pts in (baseline.get("codecs") or {}).items():
        if not isinstance(pts, list) or len(pts) < 2:
            continue
        ap = [{"psnr": q["psnr"], "bpp": q["bpp"]} for q in pts]
        bd = bd_rate(ap, curve)  # positive => champion needs MORE bits (worse)
        if bd is not None:
            out.append((codec, round(bd, 2)))
    return sorted(out, key=lambda kv: kv[1])


if __name__ == "__main__":
    import argparse, json
    ap = argparse.ArgumentParser()
    ap.add_argument("--rd", required=True)
    ap.add_argument("--baseline", required=True)
    args = ap.parse_args()
    with open(args.rd) as f:
        rd = json.load(f)
    with open(args.baseline) as f:
        base = json.load(f)
    print(f"champion shard {rd.get('shard')} vs anchors (BD-rate %, negative = fewer bits needed):")
    for codec, bd in champion_vs_anchors(rd, base):
        print(f"  {codec:10s} {bd:+8.2f}%")
