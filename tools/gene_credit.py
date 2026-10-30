#!/usr/bin/env python3
"""gene_credit.py — which genes actually earn their keep?

Two evidence sources, both committed to the repo:
  1. LESSONS.md — every merge appends per-generation selection signals:
     for each gene, (mean gene value of top-10% bots) - (population mean).
     A gene that selection keeps pushing upward in winners has positive
     signal; a gene never mentioned is either neutral or unexplored.
  2. halloffame/champion.json history (git) — the crowning genomes
     themselves: which genes moved away from their seed defaults, and the
     canalization probe's worst_gene (where the champion is fragile).

Output: GENE_CREDIT.md — table of per-gene credit, usage counts, and the
"silent list" (genes selection has never rewarded).

Usage:  python3 tools/gene_credit.py --repo . --out GENE_CREDIT.md
        (--lessons LESSONS.md --history N commits to scan)
"""
import argparse, json, os, subprocess, sys

GENE_NAMES = [
    "keyint", "dz_dc", "search", "baseq", "q_low", "q_mid", "q_high",
    "deadzone", "skip", "p_qmul", "intra_b0", "dither", "halfpel",
    "refresh", "adaptq", "chroma_q", "intra_pred", "deblock",
    "entropy", "cfl", "cdef", "qpel", "sb16",
    "mv_dz", "mv_q", "gop_q", "row_q", "skip_mv", "intra_gop",
]
# where each gene sits in the champion's flat g[] vector
IDX = {n: i for i, n in enumerate(GENE_NAMES)}
# seed defaults for the 6 v0.4+ structural genes (0.0 = legacy behavior)
STRUCTURAL = {"intra_pred", "deblock", "entropy", "cfl", "cdef", "qpel", "sb16"}


def parse_lessons(path):
    """LESSONS.md lines: '- gen 5 shard 2 (fit 21.4): keyint +0.4, cfl -0.21, ...'"""
    import re
    sig = {g: [] for g in GENE_NAMES}
    n_lines = 0
    pat = re.compile(r"^\s*-\s*gen (\d+) shard (\d+) \(fit ([\-\d.]+)\):\s*(.*)$")
    for line in open(path, encoding="utf-8", errors="replace"):
        m = pat.match(line)
        if not m:
            continue
        n_lines += 1
        for tok in m.group(4).split(","):
            tok = tok.strip()
            if not tok:
                continue
            parts = tok.rsplit(" ", 1)
            if len(parts) != 2:
                continue
            gene, val = parts[0], parts[1]
            if gene in sig:
                try:
                    sig[gene].append(float(val))
                except ValueError:
                    pass
    return sig, n_lines


def champion_history(repo, max_n=40):
    """[(commit, date, genome_g_list, canalization_worst_gene_or_None)]"""
    out = []
    log = subprocess.run(
        ["git", "-C", repo, "log", "--format=%H %ad", "--date=short", "--",
         "halloffame/champion.json"],
        capture_output=True, text=True).stdout.splitlines()
    for line in log[:max_n]:
        sha, date = line.split()
        blob = subprocess.run(
            ["git", "-C", repo, "show", f"{sha}:halloffame/champion.json"],
            capture_output=True, text=True)
        if blob.returncode != 0:
            continue
        try:
            c = json.loads(blob.stdout)
            g = c.get("g")
            if not g or len(g) < len(GENE_NAMES):
                continue
            worst = (c.get("canalization") or {}).get("worst_gene")
            out.append((sha[:7], date, [float(x) for x in g], worst))
        except Exception:
            continue
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--lessons", default="LESSONS.md")
    ap.add_argument("--out", default="GENE_CREDIT.md")
    ap.add_argument("--history", type=int, default=40)
    args = ap.parse_args()

    lessons_p = os.path.join(args.repo, args.lessons)
    sig, n_lines = parse_lessons(lessons_p) if os.path.exists(lessons_p) else ({g: [] for g in GENE_NAMES}, 0)
    hist = champion_history(args.repo, args.history)

    rows = []
    for g in GENE_NAMES:
        vals = sig[g]
        n = len(vals)
        mean = sum(vals) / n if n else 0.0
        pos = sum(1 for v in vals if v > 0)
        neg = sum(1 for v in vals if v < 0)
        # champion drift: last-vs-first genome value for this gene across crowns
        drift = ""
        if len(hist) >= 2:
            first, last = hist[-1][2][IDX[g]], hist[0][2][IDX[g]]
            if abs(last - first) > 0.05:
                drift = f"{first:.2f} → {last:.2f}"
            else:
                drift = f"pinned {last:.2f}"
        rows.append((g, n, mean, pos, neg, drift))

    rows.sort(key=lambda r: -r[2])
    used = [r for r in rows if r[1] > 0]
    silent = [r[0] for r in rows if r[1] == 0]

    md = ["# Gene Credit Report", "",
          "Which genes does selection actually reward? Two evidence streams:",
          "**(1)** selection signals from every recorded generation (top-10% mean",
          "minus population mean; positive = winners carry more of this gene),",
          "**(2)** how each gene's value drifted across the champion lineage,",
          "plus where the champion genome is fragile (canalization probe).", ""]
    md.append(f"Generations mined: **{n_lines}** · crowns scanned: **{len(hist)}** · "
              f"genes with any signal: **{len(used)}/{len(GENE_NAMES)}**")
    md.append("")
    md.append("| gene | signal count | mean signal | + / − | champion drift |")
    md.append("|---|---|---|---|---|")
    for g, n, mean, pos, neg, drift in rows:
        md.append(f"| {g} | {n} | {mean:+.3f} | {pos} / {neg} | {drift or '—'} |")
    md.append("")
    md.append("## The silent list")
    md.append("")
    if silent:
        md.append("Genes selection has never rewarded (zero signal in the ledger): "
                  + ", ".join(f"**{g}**" for g in silent) + ".")
        md.append("")
        md.append("Reading: the proposal distribution mutates all genes uniformly,")
        md.append("so silence means selection has had no reason to move them — either")
        md.append("the feature is RD-neutral on this corpus (candidate for removal or")
        md.append("for a corpus that stresses it) or its useful range is narrow and")
        md.append("the 0.08 signal threshold is too coarse to see it.")
    else:
        md.append("Every gene has shown signal at least once.")
    md.append("")
    if hist:
        worsts = [h[3] for h in hist if h[3]]
        if worsts:
            from collections import Counter
            md.append("## Fragility (canalization worst_gene across crowns)")
            md.append("")
            for gene, cnt in Counter(worsts).most_common():
                md.append(f"- **{gene}**: {cnt} crown(s) most fragile to ±0.02 perturbation")
            md.append("")
    with open(os.path.join(args.repo, args.out), "w") as f:
        f.write("\n".join(md))
    print(f"wrote {args.out} ({n_lines} generations, {len(hist)} crowns, "
          f"{len(used)} genes with signal, {len(silent)} silent)")


if __name__ == "__main__":
    main()
