#!/usr/bin/env python3
"""gen_seed.py — gen-0 population: 12 tribes x 8 bots, deterministic.

Line format (v2): id gen pa pb tribe g0..g15 r0..r5
Regulators r0..r5: mv_dz mv_q gop_q row_q skip_mv intra_gop.
Archetypes get personality seeds; explorers get neutral 0.5 (the search
discovers regulation rather than being told).
"""
import argparse
import random

TRIBES = [
    # name          [g0 keyint, g1 blk, g2 search, g3 baseq, g4 qlo, g5 qmid, g6 qhi, g7 dz, g8 skip, g9 pqm, g10 ent, g11 dith, g12 hp, g13 ref, g14 adapt, g15 chroma]
    ("motion-hawk",  [0.8, 1.0, 0.95, 0.35, 0.5, 0.5, 0.5, 0.2, 0.1, 0.4, 0.0, 0.5, 1.0, 0.3, 0.3, 0.5]),
    ("quant-max",    [0.7, 1.0, 0.4,  0.85, 0.4, 0.5, 0.8, 0.6, 0.3, 0.6, 0.0, 0.5, 0.0, 0.3, 0.2, 0.8]),
    ("i-purist",     [0.02, 1.0, 0.2, 0.45, 0.6, 0.5, 0.4, 0.3, 0.2, 0.8, 0.0, 0.5, 0.0, 0.0, 0.1, 0.5]),
    ("dz-squeezer",  [0.6, 1.0, 0.6,  0.55, 0.5, 0.5, 0.5, 0.95, 0.2, 0.5, 0.5, 0.5, 0.0, 0.3, 0.3, 0.4]),
    ("halfpel",      [0.6, 1.0, 0.7,  0.45, 0.5, 0.5, 0.5, 0.3, 0.15, 0.5, 0.0, 0.5, 1.0, 0.4, 0.4, 0.5]),
    ("adaptive",     [0.5, 1.0, 0.6,  0.5,  0.5, 0.5, 0.5, 0.35, 0.2, 0.5, 0.0, 0.5, 0.0, 0.5, 0.95, 0.5]),
    ("refresher",    [0.4, 1.0, 0.5,  0.5,  0.5, 0.5, 0.5, 0.3, 0.2, 0.5, 0.0, 0.5, 0.0, 0.95, 0.3, 0.5]),
    ("balanced",     [0.5, 1.0, 0.5,  0.5,  0.5, 0.5, 0.5, 0.3, 0.2, 0.5, 0.5, 0.5, 0.0, 0.4, 0.5, 0.5]),
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="pop/seed.txt")
    ap.add_argument("--per-tribe", type=int, default=8)
    args = ap.parse_args()

    # regulator personalities: [mv_dz, mv_q, gop_q, row_q, skip_mv, intra_gop]
    # neutral = 0.5. A few archetypes lean into regulation, most stay near it.
    REGS = [
        [0.7, 0.65, 0.5, 0.45, 0.5, 0.55],  # motion-hawk: trust motion signals
        [0.5, 0.4, 0.6, 0.5, 0.6, 0.5],     # quant-max
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],     # i-purist: neutral
        [0.6, 0.5, 0.45, 0.5, 0.55, 0.5],   # dz-squeezer
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],     # halfpel
        [0.5, 0.55, 0.6, 0.5, 0.5, 0.6],    # adaptive
        [0.45, 0.5, 0.55, 0.6, 0.5, 0.5],   # refresher
        [0.5, 0.5, 0.5, 0.5, 0.5, 0.5],     # balanced: neutral
    ]
    rng = random.Random(0x4A2E1A)
    lines = []
    bid = 0
    # 8 archetypes + 4 random explorer tribes
    for ti, (name, base) in enumerate(TRIBES):
        for k in range(args.per_tribe):
            jitter = [min(1.0, max(0.0, g + rng.gauss(0, 0.06))) for g in base]
            regs = [min(1.0, max(0.0, r + rng.gauss(0, 0.05))) for r in REGS[ti]]
            lines.append(f"{bid} 0 0 0 {ti} " + " ".join(f"{g:.4f}" for g in jitter)
                         + " " + " ".join(f"{r:.4f}" for r in regs))
            bid += 1
    for ti in range(8, 12):
        for k in range(args.per_tribe):
            genes = [round(rng.random(), 4) for _ in range(16)]
            lines.append(f"{bid} 0 0 0 {ti} " + " ".join(f"{g:.4f}" for g in genes)
                         + " " + " ".join("0.5000" for _ in range(6)))
            bid += 1

    with open(args.out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"seeded {bid} bots -> {args.out}")

if __name__ == "__main__":
    main()
