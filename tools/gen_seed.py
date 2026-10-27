#!/usr/bin/env python3
"""gen_seed.py — gen-0 population: 12 tribes x 8 bots, deterministic.

Line format (v5): id gen pa pb tribe g0..g21 r0..r5   (33 tokens)
Regulators r0..r5: mv_dz mv_q gop_q row_q skip_mv intra_gop.
v0.4 genes: g16 intra_pred (x264-style spatial intra prediction),
            g17 deblock   (H.264-lite in-loop deblocking).
v0.5 genes: g18 entropy, g19 cfl, g20 cdef.
v0.5b gene: g21 qpel (quarter-pel MC).
Archetypes get personality seeds; explorers get neutral 0.5 (the search
discovers regulation rather than being told).

--champion halloffame/champion.json: warm-start mode. Half the seed becomes
jittered champion-lineage tribes (the standing champion's basin, inherited
instead of re-discovered every run — the shard-2 stuck-basin fix), the rest
stays archetypes + explorers for coverage.
"""
import argparse
import json
import random

TRIBES = [
    # name          [g0 keyint, g1 dzdc, g2 search, g3 baseq, g4 qlo, g5 qmid, g6 qhi, g7 dz, g8 skip, g9 pqm, g10 ib0, g11 dith, g12 hp, g13 ref, g14 adapt, g15 chroma, g16 intra_pred, g17 deblock]
    ("motion-hawk",  [0.8, 1.0, 0.95, 0.35, 0.5, 0.5, 0.5, 0.2, 0.1, 0.4, 0.0, 0.5, 1.0, 0.3, 0.3, 0.5, 0.0, 0.0]),
    ("quant-max",    [0.7, 1.0, 0.4,  0.85, 0.4, 0.5, 0.8, 0.6, 0.3, 0.6, 0.0, 0.5, 0.0, 0.3, 0.2, 0.8, 0.0, 0.7]),
    ("i-purist",     [0.02, 1.0, 0.2, 0.45, 0.6, 0.5, 0.4, 0.3, 0.2, 0.8, 0.0, 0.5, 0.0, 0.0, 0.1, 0.5, 0.9, 0.0]),
    ("dz-squeezer",  [0.6, 1.0, 0.6,  0.55, 0.5, 0.5, 0.5, 0.95, 0.2, 0.5, 0.5, 0.5, 0.0, 0.3, 0.3, 0.4, 0.4, 0.3]),
    ("halfpel",      [0.6, 1.0, 0.7,  0.45, 0.5, 0.5, 0.5, 0.3, 0.15, 0.5, 0.0, 0.5, 1.0, 0.4, 0.4, 0.5, 0.0, 0.0]),
    ("adaptive",     [0.5, 1.0, 0.6,  0.5,  0.5, 0.5, 0.5, 0.35, 0.2, 0.5, 0.0, 0.5, 0.0, 0.5, 0.95, 0.5, 0.6, 0.4]),
    ("refresher",    [0.4, 1.0, 0.5,  0.5,  0.5, 0.5, 0.5, 0.3, 0.2, 0.5, 0.0, 0.5, 0.0, 0.95, 0.3, 0.5, 0.3, 0.2]),
    ("balanced",     [0.5, 1.0, 0.5,  0.5,  0.5, 0.5, 0.5, 0.3, 0.2, 0.5, 0.5, 0.5, 0.0, 0.4, 0.5, 0.5, 0.65, 0.5]),
]

# v0.5 additions ride at 0.0 = exact legacy behavior on archetype lines
V05_TAIL = [0.0, 0.0, 0.0, 0.0]  # entropy, cfl, cdef, qpel

# champion-lineage tribes: (tribe_tag, jitter sigma) — tight to loose
CHAMP_TRIBES = [
    (12, 0.02), (13, 0.04), (14, 0.07),
    (15, 0.11), (16, 0.16), (17, 0.22),
]


def champion_lines(champ_path, per_tribe, bid0):
    """Jittered champion-lineage bots (v5 lines). Genes clamp to [0,1];
    regulators jitter at half the effector sigma (canalization)."""
    with open(champ_path) as f:
        champ = json.load(f)
    g = [float(x) for x in champ["g"]]
    if len(g) == 27:
        g = g[:21] + [0.0] + g[21:]  # v4 -> v5: qpel at legacy 0.0
    assert len(g) == 28, f"champion genome length {len(g)} unexpected"
    regs = g[22:28]
    eff = g[0:22]
    rng = random.Random(0x4A2E1A ^ int(champ.get("id", 0) or 0))
    lines = []
    bid = bid0
    for tag, sigma in CHAMP_TRIBES:
        for _ in range(per_tribe):
            e = [min(1.0, max(0.0, x + rng.gauss(0, sigma))) for x in eff]
            r = [min(1.0, max(0.0, x + rng.gauss(0, sigma * 0.5))) for x in regs]
            lines.append(f"{bid} 0 0 0 {tag} " + " ".join(f"{x:.4f}" for x in e)
                         + " " + " ".join(f"{x:.4f}" for x in r))
            bid += 1
    return lines, bid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="pop/seed.txt")
    ap.add_argument("--per-tribe", type=int, default=8)
    ap.add_argument("--champion", default=None,
                    help="halloffame/champion.json — warm-start 6 lineage tribes "
                         "from the standing champion (archetypes shrink to 4/tribe)")
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
    warm = False
    if args.champion:
        try:
            lines, bid = champion_lines(args.champion, args.per_tribe, bid)
            warm = True
        except Exception as e:
            print(f"champion warm-start unavailable ({e}); pure archetypes", flush=True)
            lines, bid = [], 0
    arch_per = args.per_tribe // 2 if warm else args.per_tribe
    exp_per = args.per_tribe // 2 if warm else args.per_tribe
    # 8 archetypes + 4 random explorer tribes
    for ti, (name, base) in enumerate(TRIBES):
        for _ in range(arch_per):
            genes = [min(1.0, max(0.0, g + rng.gauss(0, 0.06))) for g in base]
            genes = genes + V05_TAIL  # entropy/cfl/cdef/qpel at legacy 0.0
            regs = [min(1.0, max(0.0, r + rng.gauss(0, 0.05))) for r in REGS[ti]]
            lines.append(f"{bid} 0 0 0 {ti} " + " ".join(f"{g:.4f}" for g in genes)
                         + " " + " ".join(f"{r:.4f}" for r in regs))
            bid += 1
    for ti in range(8, 12):
        for _ in range(exp_per):
            genes = [round(rng.random(), 4) for _ in range(18)]
            genes = genes + V05_TAIL
            lines.append(f"{bid} 0 0 0 {ti} " + " ".join(f"{g:.4f}" for g in genes)
                         + " " + " ".join("0.5000" for _ in range(6)))
            bid += 1

    with open(args.out, "w") as f:
        f.write("\n".join(lines) + "\n")
    mode = "warm-started from champion" if warm else "archetypes only"
    print(f"seeded {bid} bots ({mode}) -> {args.out}")


if __name__ == "__main__":
    main()
