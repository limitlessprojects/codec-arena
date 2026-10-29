# ROADMAP v0.6a + v0.7 — the perceptual switch and the honesty protocol

Landed together because they attack the same enemy: the plateau. The gene
credit ledger (GENE_CREDIT.md) showed why evolution stalled — 46T evaluations
had squeezed every drop out of rate-control genes while every structural gene
sat flat or negative, and the population canalized onto one strategy pinned to
seven... five synthetic clips. Two root causes: the metric (PSNR at 0.18 bpp
rewards blur, so the landscape is flat exactly where perception isn't) and the
corpus (five clips x 3,627 generations = memorization, not compression).

## v0.6a — MS-SSIM in the Zig oracle (fitness v2)

- `src/msssim.zig`: standard Wang/Simoncelli/Bovik 2003 MS-SSIM — 5 scales,
  2x2 average-pool downsampling, 11-tap separable Gaussian (sigma 1.5),
  weights [0.0448, 0.2856, 0.3001, 0.2363, 0.1333]; scales 1-4 score
  contrast*structure, the last scale full SSIM. Y-plane only; chroma stays
  report-only (psnr_u/psnr_v). Pure DSP, deterministic, unit-tested in CI.
- `codec.zig`: `ClipStats.msssim` computed per frame in the decode path; the
  oracle CSV gains an 8th column (consumers parse len>=5, so old readers
  survive).
- `brain/evolve.py`: `quality()` switches the fitness term to
  `-10*log10(1-MS-SSIM)` (dB scale, clamped by `q_ceiling`), governed by
  `config.metric = "msssim_db"`. With `metric = "psnr"` the v0.5c formula is
  reproduced bit-exactly (regression-tested).
- Lambda recalibrated 14 -> 8 for the new scale (1 MS-SSIM dB ~ 0.125 bpp at
  our operating point; keeps the rate term ~10-15% of quality).
- PSNR is demoted to REPORT-ONLY: still measured, still in BD-rate and the
  leaderboard, but selection no longer sees it.
- Why the scale moves: expect champion fit to land around 11-16 (MS-SSIM dB
  is a compressed range). This is NOT a regression — the merge gate
  re-baselines on the metric switch (below).

## v0.7 — corpus rotation + holdout (the honesty protocol)

- Corpus grows 5 -> 10 clips (all deterministic stdlib, legacy five
  byte-identical — sha256-sealed in corpus/manifest.json):
  - pool additions: `text` (screen-like glyphs, hard edges), `zoom` (true
    subpel radial motion — halfpel/qpel finally get real work), `edge`
    (rotating diagonal bars — directional structure).
  - holdout: `haze` (soft drifting fog), `pulse` (concentric rings, zero
    translation — motion search is a trap here).
- Rotation: each generation evaluates k=6 of the 8 pool clips, sampled by
  `pick_subset(pool, k, seed, shard, gen)` — deterministic, replayable, and
  holdout-free. The oracle gets a `--clips FILE` subset filter; every gen's
  clipset is journaled to `clipsets.jsonl`.
- Crowning honesty: the end-of-run evaluation (final population, canalization
  probe, RD sweep) runs on the FULL corpus including holdout. champion.json
  metrics are therefore cross-shard comparable AND a generalization score —
  genes that overfit the pool pay for it at crowning time.
- `corpus_tag: "v07"` and `metric` are stamped into every champion.json.

## Metric-era protocol (merge layer)

- `tools/merge_results.py` scores every record under ITS OWN metric era and
  refuses numeric comparison across eras: on the first v0.6a merge, the
  PSNR-era champion (170007151, fit 27.01) is archived to
  `halloffame/champion_psnr.json` and the run's best becomes the first
  MS-SSIM-era champion. Watcher re-anchors silently (no REGRESSION alert).
- `tools/pareto.py`: the quality axis is per-era (msssim vs psnr); cross-era
  records are incomparable, never dominated on a metric they never had.

## Deliberate consequences

- The surrogate (screens) still predicts on learned weights fitted to the old
  scale; screens are relative rankings, so the first refit (~gen 4) re-scales
  them. Transient, self-healing.
- Anchor codecs get re-benchmarked on the 10-clip corpus by the anchor job on
  the next run; BD-rate lines in between are 5-clip apples vs 10-clip apples.
- Oracle cost rises (MS-SSIM adds ~9M MAC/frame). Rotation partially offsets
  (6 clips per gen vs 5). If CI wall time suffers, the next lever is a
  stride-2 window grid, not a weaker metric.

## Still on the board (v0.8 candidates, ranked by the gene data)

1. Block partitioning + 16x16/32x32 transforms (codec is 8x8-only today).
2. Directional intra rebuild (intra_pred pinned at 0.04 = tool doesn't pay).
3. Loop restoration / real CDEF (silent genes; ~0.5-1 dB in AV1 terms).
4. Inter rework: MV prediction + qpel revival (zoom clip gives it a job).
5. NSGA-II/MAP-Elites archive search on top of the new landscape.
