#!/usr/bin/env python3
"""evolve.py — the reference evolution brain of Codec Arena.

One shard = one independent island. Genetics: elitism + tournament selection +
uniform crossover + gaussian mutation with annealed sigma + rare big jumps.
The Zig binary (arena) is the oracle: it encodes+decodes the corpus for every
bot and reports PSNR / bitrate / complexity. Fitness is computed here.

  score = psnr - LAMBDA * bpp - MU * dec_mops - NU * enc_ms

LAMBDA is "the exchange rate between bits and distortion" — the market price
a bot pays for quality. Everything else is bookkeeping.

Outputs (to --out-dir, becomes a CI artifact):
  results_all.csv     every evaluation this shard ever made
  pop_final.txt       final population (breed from these next run)
  leaderboard.md      shard-local top table
  lessons.md          what this shard learned (gene deltas of winners)
  rd.json             champion rate-distortion sweep vs anchor target
  evals_count.txt     number of evaluations performed (for lifetime counter)
"""
import argparse
import json
import os
import random
import subprocess
import sys
import time

NG = 16
GENE_NAMES = [
    "keyint", "blk", "search", "baseq", "q_low", "q_mid", "q_high",
    "deadzone", "skip", "p_qmul", "ent_mode", "dither", "halfpel",
    "refresh", "adaptq", "chroma_q",
]


def load_pop(path):
    pop = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            t = line.split()
            if len(t) != 5 + NG:
                continue
            pop.append({
                "id": int(t[0]), "gen": int(t[1]), "pa": int(t[2]),
                "pb": int(t[3]), "tribe": int(t[4]),
                "g": [float(x) for x in t[5:]],
            })
    return pop


def genome_line(g):
    return f"{g['id']} {g['gen']} {g['pa']} {g['pb']} {g['tribe']} " + " ".join(
        f"{x:.4f}" for x in g["g"])


def run_eval(zig_bin, corpus, pop, out_csv, fast=True):
    with open(out_csv + ".pop", "w") as f:
        for g in pop:
            f.write(genome_line(g) + "\n")
    cmd = [zig_bin, "eval", "--corpus", corpus, "--pop", out_csv + ".pop", "--out", out_csv]
    if not fast:
        cmd.append("--slow")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        raise RuntimeError(f"arena eval failed rc={r.returncode}")
    res = {}
    with open(out_csv) as f:
        for line in f:
            t = line.strip().split(",")
            if len(t) != 5:
                continue
            res[int(t[0])] = {
                "psnr": float(t[1]), "bpp": float(t[2]),
                "enc_ms10": float(t[3]), "dec_mops": float(t[4]),
            }
    os.remove(out_csv + ".pop")
    return res


def fitness(g, r, cfg):
    score = r["psnr"] - cfg["lambda"] * r["bpp"]
    score -= cfg["mu_dec"] * max(0.0, r["dec_mops"] - cfg["dec_free"])
    score -= cfg["nu_enc"] * max(0.0, r["enc_ms10"] / 10.0 - cfg["enc_free_s"])
    return score


def clamp01(x):
    return max(0.0, min(1.0, x))


def mutate(g, sigma, rng):
    h = list(g["g"])
    i = rng.randrange(NG)
    h[i] = clamp01(h[i] + rng.gauss(0, sigma))
    if rng.random() < 0.15:  # second gene sometimes
        j = rng.randrange(NG)
        h[j] = clamp01(h[j] + rng.gauss(0, sigma * 0.5))
    return h


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shard", type=int, required=True)
    ap.add_argument("--gens", type=int, default=10)
    ap.add_argument("--pop", type=int, default=256)
    ap.add_argument("--elite", type=int, default=8)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--zig", default="zig-out/bin/arena")
    ap.add_argument("--corpus", default="corpus/raw")
    ap.add_argument("--pop-file", default=None,
                    help="starting population (default pop/seed.txt)")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--config", default="brain/config.json")
    ap.add_argument("--anchor", default="benchmarks/baseline.json")
    ap.add_argument("--rd-sweep", action="store_true", default=True)
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    with open(args.config) as f:
        cfg = json.load(f)
    rng = random.Random(args.seed * 1000003 + args.shard)

    start_path = args.pop_file or "pop/seed.txt"
    population = load_pop(start_path)
    # pad or trim to requested size
    while len(population) < args.pop:
        src = population[rng.randrange(len(population))]
        child = dict(src)
        child["g"] = mutate(src, 0.2, rng)
        child["id"] = args.shard * 10_000_000 + len(population)
        child["gen"] = 0
        population.append(child)
    population = population[:args.pop]

    all_csv = open(os.path.join(args.out_dir, "results_all.csv"), "w")
    n_evals = 0
    sigma0 = cfg["sigma0"]
    history = []

    for gen in range(args.gens):
        t0 = time.time()
        res = run_eval(args.zig, args.corpus, population,
                       os.path.join(args.out_dir, "res.csv"))
        n_evals += len(population)
        for g in population:
            r = res.get(g["id"])
            if r is None:
                continue
            g["fit"] = fitness(g, r, cfg)
            all_csv.write(f"{g['id']},{g['gen']},{g['fit']:.4f},{r['psnr']:.2f},"
                          f"{r['bpp']:.4f},{r['dec_mops']:.2f}\n")
        population = [g for g in population if "fit" in g]
        population.sort(key=lambda g: -g["fit"])
        best = population[0]
        mean_fit = sum(g["fit"] for g in population) / len(population)
        history.append({"gen": gen, "best": best["fit"],
                        "psnr": best.get("psnr", res[best["id"]]["psnr"]),
                        "bpp": res[best["id"]]["bpp"],
                        "mean": mean_fit})

        # lessons: how do winners differ from the median bot?
        top = population[:max(2, len(population) // 10)]
        lesson = {}
        for i, name in enumerate(GENE_NAMES):
            top_m = sum(g["g"][i] for g in top) / len(top)
            pop_m = sum(g["g"][i] for g in population) / len(population)
            if abs(top_m - pop_m) > 0.08:
                lesson[name] = round(top_m - pop_m, 3)
        lline = {"gen": gen, "shard": args.shard, "best_fit": round(best["fit"], 3),
                 "signals": lesson}

        # breed next generation
        sigma = sigma0 * (cfg["sigma_decay"] ** gen)
        next_pop = [dict(g) for g in population[:args.elite]]
        for g in next_pop:
            g["gen"] = gen + 1
        while len(next_pop) < args.pop:
            a = tournament(population, 4, rng)
            b = tournament(population, 4, rng)
            child_g = [a["g"][i] if rng.random() < 0.5 else b["g"][i] for i in range(NG)]
            if rng.random() < cfg["jump_p"]:
                child_g[rng.randrange(NG)] = rng.random()
            else:
                child_g = mutate({"g": child_g}, sigma, rng)
            nxt = {"id": args.shard * 10_000_000 + gen * args.pop + len(next_pop),
                   "gen": gen + 1, "pa": a["id"], "pb": b["id"],
                   "tribe": a["tribe"], "g": child_g}
            next_pop.append(nxt)
        population = next_pop
        dt = time.time() - t0
        print(f"[shard {args.shard}] gen {gen}: best={best['fit']:.3f} "
              f"psnr={history[-1]['psnr']:.2f} bpp={history[-1]['bpp']:.3f} "
              f"mean={mean_fit:.3f} ({dt:.1f}s)", flush=True)
        with open(os.path.join(args.out_dir, "lessons.jsonl"), "a") as lf:
            lf.write(json.dumps(lline) + "\n")

    all_csv.close()

    # final eval of last population (so results match the exported pop)
    res = run_eval(args.zig, args.corpus, population,
                   os.path.join(args.out_dir, "res_final.csv"))
    n_evals += len(population)
    for g in population:
        r = res.get(g["id"])
        if r is not None:
            g["fit"] = fitness(g, r, cfg)
    population.sort(key=lambda g: -g["fit"])

    with open(os.path.join(args.out_dir, "pop_final.txt"), "w") as f:
        for g in population:
            f.write(genome_line(g) + "\n")

    # leaderboard fragment
    champ = population[0]
    r = res[champ["id"]]
    with open(os.path.join(args.out_dir, "leaderboard.md"), "w") as f:
        f.write(f"| {args.shard} | {champ['id']} | {champ['gen']} | {champ['tribe']} | "
                f"{r['psnr']:.2f} | {r['bpp']:.4f} | {champ['fit']:.3f} |\n")

    # RD sweep of champion: scale the baseq gene, re-evaluate
    anchor_psnr = None
    if os.path.exists(args.anchor):
        with open(args.anchor) as f:
            base = json.load(f)
        anchor_psnr = base.get("target_psnr")
    rd_points = []
    if args.rd_sweep and anchor_psnr:
        for m in cfg.get("rd_multipliers", [0.6, 0.75, 0.9, 1.0, 1.15, 1.35, 1.6]):
            gg = dict(champ)
            gg["g"] = list(champ["g"])
            gg["g"][3] = clamp01(champ["g"][3] * m)
            gg["id"] = champ["id"]
            rr = run_eval(args.zig, args.corpus, [gg],
                          os.path.join(args.out_dir, "rd.csv"))
            rr = rr[champ["id"]]
            n_evals += 1
            rd_points.append({"mult": m, "psnr": rr["psnr"], "bpp": rr["bpp"]})
        # pick point closest to anchor PSNR from above-or-near
        best_pt = min(rd_points, key=lambda p: abs(p["psnr"] - anchor_psnr))
        with open(os.path.join(args.out_dir, "rd.json"), "w") as f:
            json.dump({"shard": args.shard, "anchor_psnr": anchor_psnr,
                       "champion": best_pt, "curve": rd_points}, f, indent=1)

    with open(os.path.join(args.out_dir, "champion.json"), "w") as f:
        json.dump({"shard": args.shard, **champ, "metrics": res[champ["id"]]}, f, indent=1)
    with open(os.path.join(args.out_dir, "evals_count.txt"), "w") as f:
        f.write(str(n_evals))
    with open(os.path.join(args.out_dir, "history.json"), "w") as f:
        json.dump(history, f, indent=1)
    print(f"[shard {args.shard}] DONE evals={n_evals}")


def tournament(pop, k, rng):
    best = None
    for _ in range(k):
        c = pop[rng.randrange(len(pop))]
        if best is None or c["fit"] > best["fit"]:
            best = c
    return best


if __name__ == "__main__":
    main()
