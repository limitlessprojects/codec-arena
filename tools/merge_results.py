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
import os


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
    report = []
    hof_champ = None
    if champs:
        def fits(c):
            return c.get("metrics", {}).get("psnr", 0) - 14.0 * c.get("metrics", {}).get("bpp", 99)
        cand = max(champs, key=fits)
        hof_p = os.path.join(repo, "halloffame", "champion.json")
        prev = None
        if os.path.exists(hof_p):
            try:
                with open(hof_p) as f:
                    prev = json.load(f)
            except Exception:
                prev = None
        if prev is None or fits(cand) > fits(prev):
            os.makedirs(os.path.dirname(hof_p), exist_ok=True)
            with open(hof_p, "w") as f:
                json.dump(cand, f, indent=1)
            hof_champ = cand
            m = cand["metrics"]
            report.append(f"champion: bot {cand['id']} (gen {cand['gen']}, tribe {cand['tribe']}) "
                          f"psnr={m['psnr']:.2f} bpp={m['bpp']:.4f}")
        else:
            hof_champ = prev
            m = prev["metrics"]
            report.append(f"champion retained: bot {prev['id']} "
                          f"psnr={m['psnr']:.2f} bpp={m['bpp']:.4f} "
                          f"(this run's best, bot {cand['id']}, did not beat it)")

    # ---- LEADERBOARD.md ----
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
               "| shard | bot | gen | tribe | psnr | bpp |", "|---|---|---|---|---|---|"]
        for c in sorted(champs, key=lambda c: -fits(c))[:20]:
            m = c["metrics"]
            lb.append(f"| {c['shard']} | {c['id']} | {c['gen']} | {c['tribe']} | "
                      f"{m['psnr']:.2f} | {m['bpp']:.4f} |")
        lb.append("")
        if base and base.get("target_psnr") and hof_champ is not None:
            c = hof_champ
            m = c["metrics"]
            lb.append(f"Champion vs the x264 bar ({base['target_psnr']} dB): "
                      f"champion {m['psnr']:.2f} dB @ {m['bpp']:.4f} bpp — "
                      f"quality gap {base['target_psnr'] - m['psnr']:.1f} dB, "
                      f"bits gap {m['bpp']:.4f} vs 0.161 (x264 qp40 point).")
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

    for line in report:
        print(line)
    print(f"lifetime_evals={state['lifetime_evals']} search_evals={state['search_evals']} "
          f"screens_this_run={n_screens} runs={state['runs']} "
          f"milestones={json.dumps(state.get('milestones', {}))} "
          f"search_milestones={json.dumps(state.get('search_milestones', {}))}")


if __name__ == "__main__":
    main()
