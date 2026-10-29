# ROADMAP v0.6a + v0.7 — the perceptual switch and the honesty protocol

Landed together because they attack the same enemy: the plateau. The gene
credit ledger (GENE_CREDIT.md) showed why evolution stalled — ~49T evaluations
squeezed every drop out of rate-control genes while every structural gene sat
flat or negative, and the population canalized onto one strategy pinned to
five synthetic clips. Two root causes: the metric (PSNR at 0.18 bpp rewards
blur, so the landscape is flat exactly where perception isn't) and the corpus
(five clips x 3,627 generations = memorization, not compression).

## v0.6a — MS-SSIM in the Zig oracle (deployed design, CI-validated)

- `src/msssim.zig`: standard Wang/Simoncelli/Bovik 2003 MS-SSIM — separable
  11-tap Gaussian (sigma 1.5), valid-mode convolution, 2x2 box downsampling,
  5 scales, weights [0.0448, 0.2856, 0.3001, 0.2363, 0.1333]. Pure DSP,
  deterministic. Cross-validated to 5 decimals against a numpy reference
  (`tools/ref_msssim.py` + `arena msssimcheck`).
- Oracle CSV: `msssim` (mean M, human report) + `msssim_db` (mean of
  per-clip dB — THE selection signal; dB(mean(M)) != mean(dB(M)), and the
  merge gate consumes the fitness-grade one).
- `brain/evolve.py`: `quality_db()` selects on msssim_db under
  `config.q_metric = "msssim_db"`; the rate lambda switches with the scale
  (`msssim_lambda = 3.5`, measured break-even via `tools/calibrate_lambda.py`;
  PSNR rows keep `lambda = 14`). Complexity penalties rescaled to the new
  scale (mu_dec 0.013, nu_enc 0.005). `metric = "psnr"` shape is regression-
  tested.
- PSNR is demoted to REPORT-ONLY: still measured, still in BD-rate and the
  leaderboard, but selection no longer sees it.
- Era migration law (merge layer): cross-era numeric comparison is refused —
  the incumbent keeps the seat; the champion was re-measured by the oracle
  and re-stamped (fit_merge 7.3117, fit_ver v0.6a-msssim). The watcher
  re-anchors silently on fit_ver changes.
- Early diagnosis already pays: the `grid` clip alternates perfect/wrecked
  frames — PSNR-mean masked it (58.55 dB); MS-SSIM caught it. Inter fix
  queued for v0.8.

## v0.7 — corpus rotation + holdout (the honesty protocol)

- Corpus grows 5 -> 10 clips (all deterministic stdlib; the legacy five are
  byte-identical, sha256-sealed in corpus/manifest.json):
  - pool additions: `text` (screen-like glyphs, hard edges), `zoom` (true
    subpel radial motion — halfpel/qpel finally get real work), `edge`
    (rotating diagonal bars — directional structure).
  - holdout: `haze` (soft drifting fog), `pulse` (concentric rings, zero
    translation — motion search is a trap here).
- Rotation: each search generation evaluates k=6 of the 8 pool clips, via
  `pick_subset(pool, k, seed, shard, gen)` — deterministic, replayable,
  holdout-free. The oracle gets a `--clips FILE` subset filter; every gen's
  clipset is journaled to `clipsets.jsonl`.
- Crowning honesty: the end-of-run evaluations (final population, canalization
  probe, RD sweep) run on the FULL corpus including holdout. champion.json
  metrics are therefore cross-shard comparable AND a generalization score —
  genes that overfit the pool pay for it at crowning time.
- `corpus_tag: "v07"` and `metric` (q_metric) are stamped into champion.json.

## Metric-era plumbing (pareto + watcher)

- `tools/pareto.py`: the quality axis is per-era via `_qaxis` —
  msssim_db (fitness-grade) > msssim > psnr; cross-era records are
  incomparable, never dominated on a metric they never had.
- Watcher: prefers `fit_merge` (always current-era), re-anchors silently on
  era changes, metric-aware fallback otherwise.

## Deliberate consequences

- The surrogate (screens) still predicts on learned weights fitted to the old
  scale; screens are relative rankings, so refits re-scale them. Transient,
  self-healing.
- Anchor codecs get re-benchmarked on the 10-clip corpus by the anchor job on
  the next run; BD-rate lines in between are 5-clip apples vs 10-clip apples.
- Oracle cost rises (MS-SSIM adds ~9M MAC/frame); rotation partially offsets
  (6 pool clips per gen vs the old 5). If CI wall time suffers, the next
  lever is a stride-2 window grid, not a weaker metric.

## Still on the board (v0.8 candidates, ranked by the gene data)

1. Inter/frame-type fix for the grid clip's wrecked frames (v0.6a found it).
2. Block partitioning + 16x16/32x32 transforms (codec is 8x8-only today).
3. Directional intra rebuild (intra_pred pinned at 0.04 = tool doesn't pay).
4. Loop restoration / real CDEF (silent genes; ~0.5-1 dB in AV1 terms).
5. Inter rework: MV prediction + qpel revival (zoom clip gives it a job).
6. NSGA-II/MAP-Elites archive search on top of the new landscape.
