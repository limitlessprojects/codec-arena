#!/usr/bin/env python3
"""pareto.py — the arena's first Pareto front archive (NSGA-II spirit, merge-side).

Why: the scalar fitness collapses quality/bitrate/speed into one number, which
is correct for crowning but hides legitimate specialists — a bot 0.5 dB worse
but 10x faster is an elite, not a loser. The archive keeps every non-dominated
bot among the shard champions ever seen.

Dominance: A dominates B iff A is >= on ALL objectives and > on at least one.
  objectives: maximize psnr; minimize bpp, enc_ms10, dec_mops.
Bots missing complexity metrics (legacy) dominate only on (psnr, bpp) and are
marked "legacy" — never compared on axes they never had.

Storage: halloffame/pareto.json  (list of champion records + their objectives)
Output:  printed summary for the merge report + LEADERBOARD section dict.

Usage:  python3 tools/pareto.py --repo . --champions shard dirs... (or import)
"""
import json, os


def _axes(c):
    """Objective vector per record: (name, direction) with direction +1 max / -1 min.
    Legacy records (no complexity metrics) only claim the quality/bits axes."""
    m = c["metrics"]
    ax = [("psnr", 1), ("bpp", -1)]
    if "enc_ms10" in m:
        ax.append(("enc_ms10", -1))
    if "dec_mops" in m:
        ax.append(("dec_mops", -1))
    return ax


def dominates(a, b):
    """True if a dominates b. Axes = intersection of what each record claims
    (legacy entries are never dominated on axes they never had). Standard rule:
    a >= b on EVERY shared axis and a > b on at least one — ties broken by any
    strictly-better axis count as domination (the v0.5c bug case: equal
    psnr/bpp, faster encode must dominate)."""
    aa, ba = dict(_axes(a)), dict(_axes(b))
    shared = [k for k in aa if k in ba]
    ge = all((a["metrics"][k] - b["metrics"][k]) * aa[k] >= 0 for k in shared)
    gt = any((a["metrics"][k] - b["metrics"][k]) * aa[k] > 0 for k in shared)
    return ge and gt


def pareto_filter(pool):
    """Non-dominated set (O(n^2), n small)."""
    front = []
    for i, a in enumerate(pool):
        dominated = False
        for j, b in enumerate(pool):
            if i != j and dominates(b, a):
                dominated = True
                break
        if not dominated:
            front.append(a)
    return front


def update_archive(repo, new_champs):
    """Merge this run's shard champions into the standing archive.

    Returns (front, added_count). Every input record must carry
    metrics{psnr,bpp[,enc_ms10,dec_mops]} and an id."""
    ap = os.path.join(repo, "halloffame", "pareto.json")
    pool = []
    if os.path.exists(ap):
        try:
            with open(ap) as f:
                pool = json.load(f)
        except Exception:
            pool = []
    for c in new_champs:
        m = c.get("metrics", {})
        rec = dict(c)
        rec["legacy"] = ("enc_ms10" not in m)
        pool.append(rec)
    # dedupe by id (keep the latest occurrence)
    seen = {}
    for rec in pool:
        seen[rec["id"]] = rec
    front = pareto_filter(list(seen.values()))
    os.makedirs(os.path.dirname(ap), exist_ok=True)
    with open(ap, "w") as f:
        json.dump(front, f, indent=1)
    return front, len(new_champs)


def leaderboard_section(front):
    lines = ["## The Pareto front (non-dominated champions ever)", "",
             "| bot | psnr | bpp | enc_ms10 | dec_mops |", "|---|---|---|---|---|"]
    for c in sorted(front, key=lambda c: -c["metrics"].get("psnr", 0)):
        m = c["metrics"]
        lines.append(f"| {c['id']} | {m.get('psnr', 0):.2f} | {m.get('bpp', 0):.4f} | "
                     f"{m.get('enc_ms10', '—')} | {m.get('dec_mops', '—')} |")
    lines.append("")
    lines.append("A bot on this line is unbeatable on at least one trade-off axis —")
    lines.append("the crowning rule uses the scalar fitness, this board honors the")
    lines.append("specialists (faster-at-equal-quality, smaller-at-equal-quality).")
    return lines


if __name__ == "__main__":
    import argparse, glob
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--in-dir", required=True, help="staging dir with shard-*/champion.json")
    args = ap.parse_args()
    champs = []
    for cj in glob.glob(os.path.join(args.in_dir, "shard-*", "champion.json")):
        with open(cj) as f:
            champs.append(json.load(f))
    front, n = update_archive(args.repo, champs)
    print(f"pareto: {n} champions in, front size {len(front)}")
    print("\n".join(leaderboard_section(front)))
