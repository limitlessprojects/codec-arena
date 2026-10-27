#!/usr/bin/env python3
"""evolve.py — the reference evolution brain of Codec Arena.

One shard = one independent island. Genetics: elitism + tournament selection +
uniform crossover + gaussian mutation with annealed sigma + rare big jumps.
The Zig binary (arena) is the oracle: it encodes+decodes the corpus for every
bot and reports PSNR / bitrate / complexity. Fitness is computed here.

  score = psnr - LAMBDA * bpp - MU * dec_mops - NU * enc_ms

LAMBDA is "the exchange rate between bits and distortion" — the market price
a bot pays for quality. Everything else is bookkeeping.

Two instruments (v0.2 — the trillion protocol):
  oracle  — real encode+decode, ~0.26s/bot, counts toward lifetime_evals.
  screen  — quadratic response surface (fit on the oracle's own history)
            scores candidate genomes in ~60ns. Each generation, --screens
            candidates are synthesized (crossover of elites + mutation +
            rare jumps + immigrants), ranked by the surrogate in the Zig
            SIMD kernel, and only the top --keep survivors are promoted
            into the population for real oracle measurement.
  lifetime_evals = oracle measurements.  search_evals = screens + oracle.
  Both counters are honest and never borrow from each other.

Outputs (to --out-dir, becomes a CI artifact):
  results_all.csv     every oracle evaluation this shard ever made
  pop_final.txt       final population (breed from these next run)
  leaderboard.md      shard-local top table
  lessons.md          what this shard learned (gene deltas of winners)
  rd.json             champion rate-distortion sweep vs anchor target
  evals_count.txt     oracle evaluations (lifetime counter)
  screens_count.txt   surrogate screens (search counter)
  surrogate_final.txt the surrogate weights this shard last used
"""
import argparse
import json
import os
import random
import subprocess
import sys
import time

NG_EFF = 22          # effectors (legacy 16; v0.4 adds intra_pred/deblock; v0.5 entropy/cfl/cdef; v0.5b qpel)
NR_REG = 6           # regulator genes (GRN v1)
NG = NG_EFF + NR_REG # 28 total; screens model 28 linear + 16^2 quad over legacy effectors
GENE_NAMES = [
    # effectors (1..22) — g[1] and g[10] repurposed in v0.3 (were placebo);
    # g[17] intra_pred and g[18] deblock added in v0.4 (x264's pillars);
    # g[19] entropy, g[20] cfl and g[21] cdef added in v0.5 (AV1's lineup);
    # g[22] qpel added in v0.5b (AV1 4-tap interpolation lattice)
    "keyint", "dz_dc", "search", "baseq", "q_low", "q_mid", "q_high",
    "deadzone", "skip", "p_qmul", "intra_b0", "dither", "halfpel",
    "refresh", "adaptq", "chroma_q", "intra_pred", "deblock",
    "entropy", "cfl", "cdef", "qpel",
    # regulators (23..28) — decoder-derivable context, bounded gains
    "mv_dz", "mv_q", "gop_q", "row_q", "skip_mv", "intra_gop",
]
REG_DEFAULT = 0.5    # neutral regulator: gain 0, phenotype identical to v0.1
NEW_GENE_DEFAULT = 0.0  # migration default: gene 0.0 == exact legacy behavior
N_NEW = 6            # v0.4 (2) + v0.5 (3) + v0.5b (1) structural genes riding at 0.0 on old lines


def load_pop(path):
    pop = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            t = line.split()
            if len(t) == 5 + 16:
                # v1 line: eff16 only -> flat g = eff16 + 6 new (0) + neutral reg6
                t = t + [str(NEW_GENE_DEFAULT)] * N_NEW + [str(REG_DEFAULT)] * NR_REG
            elif len(t) == 5 + 22:
                # v2 line: eff16 + reg6 -> flat g = eff16 + 6 new (0) + reg6
                t = t[: 5 + 16] + [str(NEW_GENE_DEFAULT)] * N_NEW + t[5 + 16 :]
            elif len(t) == 5 + 24:
                # v3 line: eff16 + v0.4 pair + reg6 -> insert 3 v0.5 genes + qpel (0)
                t = t[: 5 + 18] + [str(NEW_GENE_DEFAULT)] * 4 + t[5 + 18 :]
            elif len(t) == 5 + 27:
                # v4 line: eff21 + reg6 -> insert qpel (0) before the regs
                t = t[: 5 + 21] + [str(NEW_GENE_DEFAULT)] + t[5 + 21 :]
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


# ---- surrogate refit (per-shard adaptation; numpy optional) ----

def features(genes):
    """28 flat genes -> (165,): 1 | 28 linear | 136 quadratic over the 16
    LEGACY effectors (the v0.4/v0.5/v0.5b genes ride linear-only until a refit
    learns them; the compact v5 model layout mirrors screen.zig exactly)."""
    v = [1.0]
    v.extend(genes)
    for i in range(16):
        for j in range(i + 1):
            v.append(genes[i] * genes[j])
    return v


def load_weights(path):
    with open(path) as f:
        toks = f.read().split()
    n = int(toks[0])
    w = [float(x) for x in toks[1 : 1 + n]]
    # v1/v2/v3/v4 -> v5 migration: insert neutral zeros for the newer genes'
    # linear slots (the quad block over the legacy 16 is untouched; regs are
    # neutral at weight 0). Keeps per-shard refits alive across upgrades.
    if n == 153:   # v1: 1 + 16 + 136 -> +12 (6 new genes + 6 regs)
        w = w[:17] + [0.0] * 12 + w[17:]
    elif n == 159: # v2: 1 + 22 + 136 -> +6 (6 new genes)
        w = w[:17] + [0.0] * 6 + w[17:]
    elif n == 161: # v3: 1 + 24 + 136 -> +4 (3 v0.5 + qpel)
        w = w[:19] + [0.0] * 4 + w[19:]
    elif n == 164: # v4: 1 + 27 + 136 -> +1 (qpel, before the reg slots)
        w = w[:22] + [0.0] + w[22:]
    return w


def save_weights(path, w):
    with open(path, "w") as f:
        f.write(f"{len(w)}\n")
        f.write(" ".join(f"{x:.8e}" for x in w) + "\n")


def refit_surrogate(rows, prior_w, out_path, alpha=50.0):
    """Ridge refit toward the prior: min ||Xw-y||^2 + alpha||w-w_prior||^2.
    rows: list of (genes, fit). Returns True if a new model was written."""
    try:
        import numpy as np
    except ImportError:
        return False
    if len(rows) < 300:
        return False
    X = np.array([features(g) for g, _ in rows], dtype=np.float64)
    y = np.array([f for _, f in rows], dtype=np.float64)
    w0 = np.array(prior_w, dtype=np.float64)
    if w0.shape[0] != X.shape[1]:
        return False
    XtX = X.T @ X
    Xty = X.T @ y
    w = np.linalg.solve(XtX + alpha * np.eye(X.shape[1]), Xty + alpha * w0)
    save_weights(out_path, [float(v) for v in w])
    return True


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
    ap.add_argument("--screens", type=int, default=0,
                    help="surrogate screens per generation (0 = legacy GA path)")
    ap.add_argument("--keep", type=int, default=0,
                    help="screen survivors promoted per gen (default pop/8*6)")
    ap.add_argument("--threads", type=int, default=4, help="screen kernel threads")
    ap.add_argument("--model", default="state/surrogate.txt",
                    help="surrogate weights (153/159/161 legacy, 164 v4, or 165 v5 compact floats)")
    ap.add_argument("--rd-sweep", action="store_true", default=True)
    ap.add_argument("--probe", action="store_true", default=True,
                    help="canalization probe: epsilon-mutant sweep of the champion")
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
    n_screens = 0
    sigma0 = cfg["sigma0"]
    history = []

    # cascade setup: how many elites / promoted / classically-bred per gen
    use_screen = args.screens > 0 and os.path.exists(args.model)
    if use_screen:
        model_path = os.path.join(args.out_dir, "surrogate_live.txt")
        with open(args.model) as fsrc, open(model_path, "w") as fdst:
            fdst.write(fsrc.read())
        prior_w = load_weights(args.model)
        E = max(2, args.pop // 8)
        bred_n = max(2, args.pop // 8)
        K = args.keep if args.keep > 0 else args.pop - E - bred_n
        fit_rows = []  # (genes, fit) oracle rows for per-shard refits
    else:
        E, bred_n, K = args.elite, 0, 0

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
        if use_screen:
            # --- trillion path: elites + surrogate-promoted + classic bred ---
            population.sort(key=lambda g: -g["fit"])
            elites = population[:E]
            for g in elites:
                g["gen"] = gen + 1
            elite_path = os.path.join(args.out_dir, "elites.txt")
            with open(elite_path, "w") as f:
                for g in elites:
                    f.write(genome_line(g) + "\n")
            prom_path = os.path.join(args.out_dir, "promoted.txt")
            cnt_path = os.path.join(args.out_dir, "screens.txt")
            cmd = [args.zig, "screen", "--model", model_path,
                   "--elites", elite_path, "--out", prom_path,
                   "--count-out", cnt_path,
                   "--lambda", str(args.screens), "--keep", str(K),
                   "--seed", str(args.seed * 1000003 + args.shard * 131 + gen),
                   "--threads", str(args.threads),
                   "--sigma", f"{0.12 * (cfg['sigma_decay'] ** gen):.4f}",
                   "--jump", "0.02", "--imm", "0.01"]
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode != 0:
                print(r.stderr, file=sys.stderr)
                raise RuntimeError(f"arena screen failed rc={r.returncode}")
            with open(cnt_path) as f:
                n_screens += int(f.read().strip() or 0)
            promoted = []
            with open(prom_path) as f:
                for line in f:
                    t = line.split()
                    if len(t) != 5 + NG:
                        continue
                    promoted.append({"id": 0, "gen": 0,
                                     "pa": int(t[2]), "pb": int(t[3]),
                                     "tribe": int(t[4]),
                                     "g": [float(x) for x in t[5:]]})
            next_pop = [dict(g) for g in elites]
            for p in promoted[: K]:
                nxt = {"id": args.shard * 10_000_000 + gen * args.pop + len(next_pop),
                       "gen": gen + 1, "pa": p["pa"], "pb": p["pb"],
                       "tribe": p["tribe"], "g": p["g"]}
                next_pop.append(nxt)
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
            # per-shard surrogate adaptation (numpy optional, every 4 gens)
            for g in population:
                fit_rows.append((list(g["g"]), g["fit"]))
            if gen >= 3 and gen % 4 == 3:
                if refit_surrogate(fit_rows[-4000:], prior_w, model_path):
                    prior_w = load_weights(model_path)
        else:
            # --- legacy GA path (pop seeded purely by classical genetics) ---
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

    # ---- canalization probe: does a small mutation cause a small fitness
    # change? (the evolvability metric — biology calls it canalization).
    # Doubles as a polish step: a better epsilon-mutant is promoted. ----
    probe = None
    if args.probe and population:
        eps = 0.02
        champ0 = population[0]
        base_fit = champ0["fit"]
        mutants = []
        for i in range(NG):
            for s in (-eps, eps):
                mg = dict(champ0)
                mg["g"] = list(champ0["g"])
                mg["g"][i] = clamp01(mg["g"][i] + s)
                mg["id"] = 9_500_000_000 + args.shard * 100_000 + len(mutants)
                mutants.append((i, mg))
        res_p = run_eval(args.zig, args.corpus, [m[1] for m in mutants],
                         os.path.join(args.out_dir, "probe.csv"))
        n_evals += len(mutants)
        deltas = []
        best_m = None
        for i, mg in mutants:
            r = res_p.get(mg["id"])
            if r is None:
                continue
            f2 = fitness(mg, r, cfg)
            deltas.append((GENE_NAMES[i], f2 - base_fit))
            if best_m is None or f2 > best_m[0]:
                best_m = (f2, mg, r)
        if deltas:
            import statistics
            canal = statistics.median(abs(d[1]) for d in deltas)
            worst = max(deltas, key=lambda d: abs(d[1]))
            probe = {
                "canalization_median_delta": round(canal, 4),
                "n_mutants": len(deltas),
                "worst_gene": worst[0],
                "worst_delta": round(worst[1], 4),
            }
            if best_m and best_m[0] > base_fit:
                # polish: the best epsilon-mutant earns the crown
                champ0 = best_m[1]
                champ0["fit"] = best_m[0]
                population[0] = champ0
                res[champ0["id"]] = best_m[2]
                probe["polish_gain"] = round(best_m[0] - base_fit, 4)
                with open(os.path.join(args.out_dir, "pop_final.txt"), "w") as f:
                    for g in population:
                        f.write(genome_line(g) + "\n")
        with open(os.path.join(args.out_dir, "probe.json"), "w") as f:
            json.dump(probe, f, indent=1)

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
        cj = {"shard": args.shard, **champ, "metrics": res[champ["id"]]}
        if probe:
            cj["canalization"] = probe
        json.dump(cj, f, indent=1)
    with open(os.path.join(args.out_dir, "evals_count.txt"), "w") as f:
        f.write(str(n_evals))
    with open(os.path.join(args.out_dir, "screens_count.txt"), "w") as f:
        f.write(str(n_screens))
    if use_screen:
        save_weights(os.path.join(args.out_dir, "surrogate_final.txt"), prior_w)
    with open(os.path.join(args.out_dir, "history.json"), "w") as f:
        json.dump(history, f, indent=1)
    print(f"[shard {args.shard}] DONE evals={n_evals} screens={n_screens}")


def tournament(pop, k, rng):
    best = None
    for _ in range(k):
        c = pop[rng.randrange(len(pop))]
        if best is None or c["fit"] > best["fit"]:
            best = c
    return best


if __name__ == "__main__":
    main()
