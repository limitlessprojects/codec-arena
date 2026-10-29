#!/usr/bin/env python3
"""merge_results.py — nightly arena merge: shards -> leaderboard, lessons,
hall of fame, lifetime counter, milestone report.

Inputs: a directory containing extracted artifacts:
  <in>/shard-XX/{results_all.csv,pop_final.txt,leaderboard.md,lessons.jsonl,
                  rd.json,champion.json,evals_count.txt,history.json}
  <in>/baseline.json   (optional; from anchor job)

Writes: LEADERBOARD.md, LESSONS.md (append), state/lifetime_evals.json,
halloffame/champion.json, benchmarks/baseline.json, and prints a milestone
report to stdout for the CI to turn into an issue.
"""
import argparse
import glob
import json
import math
import os
import sys


# Complexity-penalty exchange rates, read from brain/config.json so the merge
# layer and the evolution brain can never drift apart. Falls back to the
# v0.5b-era constants if the file is unreadable.
def load_cfg(repo):
    defaults = {"lambda": 14.0, "msssim_lambda": 3.5, "q_metric": "msssim_db",
                "mu_dec": 0.013, "nu_enc": 0.005,
                "dec_free": 8.0, "enc_free_s": 1.0}
    p = os.path.join(repo, "brain", "config.json")
    try:
        with open(p) as f:
            raw = json.load(f)
        for k in defaults:
            if k in raw:
                defaults[k] = raw[k] if k == "q_metric" else float(raw[k])
    except Exception:
        pass
    return defaults


def msssim_db(m):
    """Mean per-clip MS-SSIM (in M units) -> dB scale, clamped."""
    return -10.0 * math.log10(max(1e-9, min(1.0 - 1e-9, 1.0 - m)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in-dir", required=True)
    ap.add_argument("--repo", default=".")
    args = ap.parse_args()

    repo = args.repo
    shard_dirs = sorted(glob.glob(os.path.join(args.in_dir, "shard-*")))
    champs = []
    n_evals = 0
    n_screens = 0
    lessons = []

    for sd in shard_dirs:
        ec = os.path.join(sd, "evals_count.txt")
        if os.path.exists(ec):
            with open(ec) as f:
                n_evals += int(f.read().strip() or 0)
        sc = os.path.join(sd, "screens_count.txt")
        if os.path.exists(sc):
            with open(sc) as f:
                n_screens += int(f.read().strip() or 0)
        cj = os.path.join(sd, "champion.json")
        if os.path.exists(cj):
            with open(cj) as f:
                champs.append(json.load(f))
        lj = os.path.join(sd, "lessons.jsonl")
        if os.path.exists(lj):
            with open(lj) as f:
                for line in f:
                    line = line.strip()
                    if line:
                        lessons.append(json.loads(line))

    # ---- baseline ----
    base = None
    bp = os.path.join(args.in_dir, "baseline.json")
    if os.path.exists(bp):
        with open(bp) as f:
            base = json.load(f)
        os.makedirs(os.path.join(repo, "benchmarks"), exist_ok=True)
        with open(os.path.join(repo, "benchmarks", "baseline.json"), "w") as f:
            json.dump(base, f, indent=1)

    # ---- lifetime counters ----
    # lifetime_evals: real oracle measurements (encode+decode on the corpus).
    # search_evals: every candidate genome scored by ANY instrument
    #               (surrogate screens + oracle). The search-scale counter —
    #               this is "how many bots have attacked the problem".
    state_p = os.path.join(repo, "state", "lifetime_evals.json")
    state = {"lifetime_evals": 0, "runs": 0, "milestones": {}}
    if os.path.exists(state_p):
        with open(state_p) as f:
            state = json.load(f)
    if "search_evals" not in state:
        state["search_evals"] = state["lifetime_evals"]
    state["lifetime_evals"] += n_evals
    state["search_evals"] += n_evals + n_screens
    state["runs"] += 1
    for m, key in [("1e5", 100_000), ("1e6", 1_000_000), ("1e7", 10_000_000),
                   ("1e8", 100_000_000), ("1e9", 1_000_000_000)]:
        state.setdefault("milestones", {})
        if state["lifetime_evals"] >= key and m not in state["milestones"]:
            state["milestones"][m] = f"run {state['runs']}"
    for m, key in [("1e6", 1_000_000), ("1e9", 1_000_000_000),
                   ("1e12", 1_000_000_000_000)]:
        state.setdefault("search_milestones", {})
        if state["search_evals"] >= key and m not in state["search_milestones"]:
            state["search_milestones"][m] = f"run {state['runs']}"
    os.makedirs(os.path.dirname(state_p), exist_ok=True)
    with open(state_p, "w") as f:
        json.dump(state, f, indent=1)

    # ---- champion (global) ----
    # The Hall of Fame keeps the best bot EVER SEEN, not the best of this run:
    # a regression must never dethrone the champion, and the champion-gated
    # issue report must only fire on genuine improvements.
    #
    # v0.5c fix (fitness alignment): the merge gate previously compared on the
    # raw exchange rate psnr - lambda*bpp ONLY, while the scoreboard (and the
    # shard-side evolution) uses the complexity-penalized fitness from
    # brain/evolve.py:fitness(). That mismatch let a strictly slower encoder
    # (enc_ms10 963 -> 1403 at identical psnr/bpp) "win" by +0.0014 and dethrone
    # a better champion. The gate now scores with the SAME formula the brain
    # evolves against — one fitness, everywhere.
    report = []
    hof_champ = None
    if champs:
        cfg = load_cfg(repo)

        def fits(c):
            # Same formula as brain/evolve.py:fitness() (v0.6a): quality on
            # the MS-SSIM dB scale minus the rate/complexity penalties.
            # Legacy entries without the msssim column fall back to PSNR +
            # lambda (their era's scale); entries without enc/dec metrics
            # fall back to the quality-only rate rather than inventing
            # complexity numbers they never had.
            m = c.get("metrics", {})
            # ONE FITNESS EVERYWHERE: prefer the oracle-computed fitness-grade
            # msssim_db (mean of per-clip dB); dB(mean(M)) != mean(dB(M)) —
            # recomputing from the mean-M column would reintroduce the v0.5c
            # gate/brain drift. The msssim->dB path is only for champions
            # stamped before the msssim_db column existed.
            ms_db = m.get("msssim_db")
            if ms_db is None and m.get("msssim") is not None:
                ms_db = msssim_db(m["msssim"])
            if cfg.get("q_metric") == "msssim_db" and ms_db is not None:
                q = ms_db
                lam = cfg["msssim_lambda"]
            else:
                q = m.get("psnr", 0)
                lam = cfg["lambda"]
            score = q - lam * m.get("bpp", 99)
            enc = m.get("enc_ms10")
            dec = m.get("dec_mops")
            if enc is not None:
                score -= cfg["nu_enc"] * max(0.0, enc / 10.0 - cfg["enc_free_s"])
            if dec is not None:
                score -= cfg["mu_dec"] * max(0.0, dec - cfg["dec_free"])
            return score

        cand = max(champs, key=fits)
        # auditability: stamp the merge-layer fitness (same penalized formula
        # as the brain) so the stored fit ALWAYS reconciles with the displayed
        # psnr/bpp/complexity. The raw shard-side fitness (measured at the
        # shard's own operating point) is kept as fit_shard for provenance.
        cand["fit_merge"] = round(fits(cand), 4)
        if "fit" in cand:
            cand["fit_shard"] = cand["fit"]
        hof_p = os.path.join(repo, "halloffame", "champion.json")
        prev = None
        if os.path.exists(hof_p):
            try:
                with open(hof_p) as f:
                    prev = json.load(f)
            except Exception:
                prev = None
        # v0.6a migration law: PSNR-era and MS-SSIM-era fitness live on
        # different scales. A cross-era comparison must never silently
        # dethrone (the numbers are incomparable); the incumbent keeps the
        # seat until an explicit re-stamp migrates it to the new scale.
        def era(c):
            m = c.get("metrics", {})
            return "msssim" if (m.get("msssim_db") is not None or m.get("msssim") is not None) else "psnr"
        cross_era = prev is not None and era(cand) != era(prev)
        if cross_era:
            report.append(f"WARNING: metric-era mismatch — standing champion {prev['id']} "
                          f"({era(prev)}-era) vs candidate {cand['id']} ({era(cand)}-era): "
                          f"fitness scales are incomparable, candidate cannot dethrone. "
                          f"Re-stamp the champion to migrate eras.")
        if prev is None or (not cross_era and fits(cand) > fits(prev)):
            os.makedirs(os.path.dirname(hof_p), exist_ok=True)
            with open(hof_p, "w") as f:
                json.dump(cand, f, indent=1)
            hof_champ = cand
            m = cand["metrics"]
            ms_db = m.get("msssim_db")
            if ms_db is None and m.get("msssim") is not None:
                ms_db = msssim_db(m["msssim"])
            ms_s = f" msssim_db={ms_db:.4f}" if ms_db is not None else ""
            report.append(f"champion: bot {cand['id']} (gen {cand['gen']}, tribe {cand['tribe']}) "
                          f"psnr={m['psnr']:.2f} bpp={m['bpp']:.4f}{ms_s} fit={cand['fit_merge']:.4f}")
        else:
            hof_champ = prev
            # backfill the stamp on the standing champion (one-time)
            if "fit_merge" not in prev:
                prev["fit_merge"] = round(fits(prev), 4)
                if "fit" in prev:
                    prev["fit_shard"] = prev["fit"]
                with open(hof_p, "w") as f:
                    json.dump(prev, f, indent=1)
            m = prev["metrics"]
            ms = m.get("msssim")
            ms_s = f" msssim={ms:.4f}" if ms is not None else ""
            report.append(f"champion retained: bot {prev['id']} "
                          f"psnr={m['psnr']:.2f} bpp={m['bpp']:.4f}{ms_s} "
                          f"(this run's best, bot {cand['id']}, did not beat it)")

    # ---- Pareto front archive (v0.5d) ----
    # The scalar fitness crowns one bot; the archive honors every trade-off
    # specialist (faster-at-equal-quality, smaller-at-equal-quality). NSGA-II
    # spirit, merge-side only — no protocol change, no selection impact.
    pareto_section = []
    try:
        sys.path.insert(0, os.path.join(repo, "tools"))
        import pareto as _pareto
        front, n_in = _pareto.update_archive(repo, champs)
        pareto_section = _pareto.leaderboard_section(front)
        report.append(f"pareto front: {len(front)} non-dominated champions "
                      f"(archive +{n_in} this run)")
    except Exception as e:
        print(f"WARNING: pareto archive skipped: {e}")

    # ---- BD-rate vs anchors (v0.5d) ----
    # The standard codec comparison metric, computed from the champion's RD
    # sweep (rd.json) against the anchor codec curves (baseline.json).
    bd_section = []
    try:
        import bdrate as _bdrate
        rd_p = os.path.join(args.in_dir, f"shard-{hof_champ['shard']}", "rd.json") if hof_champ else None
        if rd_p and os.path.exists(rd_p) and base and isinstance(base.get("codecs"), dict):
            with open(rd_p) as f:
                rd = json.load(f)
            bds = _bdrate.champion_vs_anchors(rd, base)
            if bds:
                bd_section = ["",
                              f"## Champion BD-rate vs anchors (champion curve minus anchor curve; "
                              f"negative = champion needs fewer bits, positive = more)", "",
                              "| codec | BD-rate |", "|---|---|"]
                for cname, bd in bds:
                    bd_section.append(f"| {cname} | {bd:+.2f}% |")
                bd_section.append("")
                report.append("champion BD-rate vs anchors: "
                              + ", ".join(f"{c} {b:+.1f}%" for c, b in bds))
    except Exception as e:
        print(f"WARNING: BD-rate skipped: {e}")

    # ---- LEADERBOARD.md ----
    # (fits() and cfg from the champion block above; one fitness everywhere.)
    lb = ["# Leaderboard", "",
          "Every bot that ever lived in the arena is measured against the same",
          "corpus, the same decoder, the same exchange rate. Champions graduate",
          "to the Hall of Fame; the rest feed the lessons ledger.", "",
          f"Oracle evaluations (real encode+decode): **{state['lifetime_evals']:,}**",
          f"Candidate evaluations, all instruments (screens + oracle): **{state['search_evals']:,}**",
          f"Merge runs: {state['runs']}.  Oracle milestones: {json.dumps(state.get('milestones', {}))}",
          f"Search milestones: {json.dumps(state.get('search_milestones', {}))}", "",
          "The two counters never borrow from each other: a surrogate screen is",
          "a candidate judged cheaply; only the oracle (real encode+decode) can",
          "put a bot on this board.", ""]
    if base and isinstance(base.get("codecs"), dict):
        lb += ["## The bar (real codecs, same corpus, same PSNR instrument)", "",
               "| codec | PSNR | bpp |", "|---|---|---|"]
        for cname, pts in base["codecs"].items():
            if isinstance(pts, list) and pts:
                p = min(pts, key=lambda q: abs(q["psnr"] - (base.get("target_psnr") or 34)))
                lb.append(f"| {cname} | {p['psnr']} | {p['bpp']} |")
        lb.append("")
    if champs:
        lb += ["## Shard champions (this run)", "",
               "| shard | bot | gen | tribe | psnr | bpp | ms-ssim |", "|---|---|---|---|---|---|---|"]
        for c in sorted(champs, key=lambda c: -fits(c))[:20]:
            m = c["metrics"]
            ms = m.get("msssim") or 0.0
            lb.append(f"| {c['shard']} | {c['id']} | {c['gen']} | {c['tribe']} | "
                      f"{m['psnr']:.2f} | {m['bpp']:.4f} | {ms:.4f} |")
        lb.append("")
        if base and base.get("target_psnr") and hof_champ is not None:
            c = hof_champ
            m = c["metrics"]
            lb.append(f"Champion vs the x264 bar ({base['target_psnr']} dB): "
                      f"champion {m['psnr']:.2f} dB @ {m['bpp']:.4f} bpp — "
                      f"quality gap {base['target_psnr'] - m['psnr']:.1f} dB, "
                      f"bits gap {m['bpp']:.4f} vs 0.161 (x264 qp40 point).")
            lb.append("")
        if pareto_section:
            lb += pareto_section
        if bd_section:
            lb += bd_section
        lb += ["## Gene credit (which genes selection rewards)", "",
               "See [GENE_CREDIT.md](GENE_CREDIT.md) — mined from every recorded",
               "generation's selection signals plus the champion lineage drift."]
        lb.append("")
    with open(os.path.join(repo, "LEADERBOARD.md"), "w") as f:
        f.write("\n".join(lb))

    # ---- LESSONS.md append ----
    if lessons:
        with open(os.path.join(repo, "LESSONS.md"), "a") as f:
            f.write(f"\n## Merge run {state['runs']}\n\n")
            seen_gens = set()
            for l in lessons[-200:]:
                key = (l.get("gen"), l.get("shard"))
                if key in seen_gens:
                    continue
                seen_gens.add(key)
                sig = l.get("signals", {})
                if sig:
                    top = sorted(sig.items(), key=lambda kv: -abs(kv[1]))[:5]
                    sigs = ", ".join(f"{k} {'+' if v > 0 else ''}{v}" for k, v in top)
                    f.write(f"- gen {l.get('gen')} shard {l.get('shard')} "
                            f"(fit {l.get('best_fit')}): {sigs}\n")

    # ---- gene credit report (v0.5d) ----
    # Which genes does selection actually reward? Mined from LESSONS.md + the
    # champion lineage. Cheap, honest, and the direct answer to "what is the
    # evolution using?".
    try:
        import subprocess as _sp2
        r = _sp2.run([sys.executable, os.path.join(repo, "tools", "gene_credit.py"),
                      "--repo", repo, "--out", "GENE_CREDIT.md"],
                     capture_output=True, text=True)
        if r.returncode == 0:
            print(f"gene credit: {r.stdout.strip()}")
        else:
            print(f"WARNING: gene_credit failed rc={r.returncode}: {r.stderr.strip()[-200:]}")
    except Exception as e:
        print(f"WARNING: gene_credit skipped: {e}")

    # ---- champion warm-start reseeding (v0.5b ops) ----
    # Every run used to re-walk from the same static v3-era seed file; shards
    # whose deterministic RNG path landed in a bad basin (shard 2: 24.98 dB @
    # 0.4694 bpp vs the pack at 26.3-27.1) stayed stuck forever. Rebuild
    # pop/seed.txt from the standing champion (jittered lineage tribes) plus
    # the classic archetypes so every run INHERITS the champion's basin.
    try:
        import subprocess as _sp
        hof_p = os.path.join(repo, "halloffame", "champion.json")
        seed_p = os.path.join(repo, "pop", "seed.txt")
        if os.path.exists(hof_p):
            os.makedirs(os.path.dirname(seed_p), exist_ok=True)
            r = _sp.run([sys.executable, os.path.join(repo, "tools", "gen_seed.py"),
                         "--champion", hof_p, "--out", seed_p],
                        capture_output=True, text=True)
            if r.returncode == 0:
                print(f"seed rewarmed: {r.stdout.strip()}")
            else:
                print(f"WARNING: seed rewarm failed rc={r.returncode}: {r.stderr.strip()[-200:]}")
    except Exception as e:
        print(f"WARNING: seed rewarm skipped: {e}")

    for line in report:
        print(line)
    print(f"lifetime_evals={state['lifetime_evals']} search_evals={state['search_evals']} "
          f"screens_this_run={n_screens} runs={state['runs']} "
          f"milestones={json.dumps(state.get('milestones', {}))} "
          f"search_milestones={json.dumps(state.get('search_milestones', {}))}")


if __name__ == "__main__":
    main()
