# RESEARCH_V05C — what the genes said, where the code errs, and the road to v0.6

*Date: 2026-10-29. Written after the gene-credit mining (3627 generations,
7 crowns), a full error-hunt over the metric path, and a survey of the
current (2024–2026) learned-compression and evolutionary-search literature.*

---

## 1. Executive summary

Three questions were asked: **which genes are actually used**, **where is the
code wrong**, and **what do the best compressors (and biology) know that we
don't**. The answers, in one breath each:

1. The population has converged on **entropy coding + maxed quantizers +
   minimal motion** — the "AV1 pillars" we added (intra modes, deblocking,
   sub-pel motion) are being selected *against* on the current synthetic
   corpus, and the brand-new qpel gene has never once been rewarded. The
   corpus, not the codec, is now the binding constraint.
2. Three real defects were found and fixed: a **chroma-blind fitness**
   (PSNR measured on luma only — CfL/chroma_q damage was invisible), a
   **bot-id collision** that let two genomes share one measurement, and the
   earlier merge-gate fitness misalignment (v0.5c). Two new instruments
   landed: a **Pareto front archive** and **BD-rate vs anchors**.
3. The literature validates our two-instrument design (surrogate + oracle is
   now standard in evolutionary NAS), and points at four concrete next rungs:
   perceptual quality metrics, multi-objective selection inside the brain,
   corpus rotation with a holdout, and flux-weighted mutation (borrowed from
   slime mold).

---

## 2. Gene credit — what selection actually rewards

Full table: [GENE_CREDIT.md](GENE_CREDIT.md) (regenerated every merge).
Mined from 3627 recorded generations (top-10%-vs-population signal) and the
7-crown champion lineage.

### The winners
| gene | mean signal | reading |
|---|---|---|
| **entropy** | **+0.344** (172/173 gens positive) | The v0.5 arithmetic coder is the single biggest win in arena history — it *is* the champion leap from fit 19→27. |
| baseq / q_mid / q_high / deadzone / p_qmul | +0.10…+0.18, all pinned at ~1.0 | The quantizer family is saturated at maximum aggressiveness. bpp is the binding constraint; no more free lunch here. |
| skip | +0.174 (944/1004) | Skipping non-essential blocks is universally rewarded. |
| chroma_q | +0.128 | Yet chroma quality was never measured (fixed this release) — selection was optimizing chroma *rate*, blind to chroma *distortion*. |

### The losers (selected AGAINST on this corpus)
| gene | mean signal | reading |
|---|---|---|
| **keyint** | **−0.345** (0/424 — never once positive) | The most decisive signal in the ledger. Winners push it to 0.03 and it is the fragile axis (worst_gene) in **all 7 crowns**. |
| intra_pred | −0.144 (7/136 positive), pinned 0.04 | The v0.4 flagship is switched OFF by selection. |
| deblock | −0.029, pinned 0.00 | Also off. |
| dz_dc / mv_dz / search | −0.115…−0.143 | Motion search effort is actively suppressed — cheap motion wins here. |
| **qpel** | **zero signal in 3627 generations** | The v0.5b gene has never been rewarded. halfpel itself is negative (−0.057). |

### What this means (the honest diagnosis)
The corpus is five synthetic clip archetypes (drift/grid/storm/quake/grain):
smooth gradients, balls, synthetic noise. On such content the legacy
predictors already do well, spatial intra modes cost more bits than they
save, and sub-pel motion has nothing real to track. **The evolution is not
broken — it is faithfully optimizing a benchmark that stopped teaching new
lessons.** The x264/AV1 pillars would pay on natural video; they cannot pay
here. This is the strongest possible argument for the corpus-rotation rung
below, and it re-frames "28 genes, 44.73T evals": the *search* machinery is
fine; the *landscape* is starved.

---

## 3. Where the code errs — found & fixed in this release (v0.5d)

1. **Chroma-blind fitness (metric-path error).** The oracle measured PSNR on
   the luma plane only; U/V were decoded but never scored. Every chroma
   decision (cfl, chroma_q, chroma-from-luma) was rated purely on the bits it
   spent, never the damage it did. *Fixed*: `codec.zig` now accumulates
   `psnr_u`/`psnr_v`; the eval CSV appends two columns (v0.5c rows are byte-
   identical prefixes); `anchor.py` reports Y/U/V per anchor point. **Fitness
   still selects on psnr_y** (the migration law — HOF comparability is
   sacred); the v0.6 metric switch will be a config change with a measured
   legacy bridge, exactly like v0.4's gene migration.
2. **Bot-id collision in the padding path (evolve.py).** Padded gen-0 bots
   drew ids from the same `shard*1e7 + n` space as generation-0 bred/promoted
   bots — duplicate ids inside one eval call mean the results dict silently
   overwrites: two different genomes scored with one bot's measurement.
   *Fixed*: padding now draws from a reserved sub-range (`+8_000_000`).
3. **BD-rate integration-range bug (found in our own new tool before it ever
   shipped).** Clipped curves were integrated over their own extent but
   normalized by the common range — a 23% answer came out as 102%.
   *Fixed*: both curves integrate over the exact common PSNR interval
   (PCHIP, monotone — matches brute force to the second decimal).
4. **Pareto dominance early-exit (same story — caught by the v0.5c incident
   replay).** Equal-psnr/equal-bpp + faster-encode must dominate; the first
   draft returned False. *Fixed* with axis-intersection dominance.

### Queued (found, not yet fixed)
- `--rd-sweep`/`--probe` use `store_true` + `default=True` — the flags can't
  actually disable anything. Cosmetic; fix with the next evolve.py surgery.
- `screen --lambda N` names a candidate *count* after the RD exchange rate
  λ. Naming hazard across the codebase; rename at the next Zig pass.
- The surrogate's quadratic terms cover only the 16 legacy effectors; the six
  structural genes ride linear-only. Fine while they sit at 0/1, wrong as
  soon as they take interior values (qpel drifted to 0.12) — the screen then
  systematically misprices them. Extend the quad block in v0.6.

---

## 4. The 8-point program → concrete rungs

| # | proposal | arena status | rung |
|---|---|---|---|
| 1 | Perceptual fitness (MS-SSIM/LPIPS) | Agreed at low bpp (0.18 bpp is mush-territory). LPIPS needs a network — not Zig-friendly; **MS-SSIM is** (pure DSP, ~100 lines of Zig). Chroma columns now flowing as the bridge data. | **v0.6a**: MS-SSIM in the oracle, reported alongside PSNR; **v0.6b**: config-switch fitness to `0.5·PSNR + 0.5·MS-SSIM` with a full-population re-score + HOF re-baseline (documented, one-time). |
| 2 | Multi-objective (NSGA-II) | Scalar fitness stays the *crowning* rule (one champion, clean issues), but the **Pareto front archive ships today** (merge-side, `halloffame/pareto.json`, LEADERBOARD section). Full NSGA-II rank-density selection inside evolve.py is the v0.6c rung. | **shipped (light) → v0.6c** |
| 3 | MAP-Elites | Archive exists (this release). Descriptor axes that cost nothing: bpp × enc_ms10 (shipped), content-type (needs corpus tags — see #7). | **shipped (light) → v0.6d**: seed next runs from archive cells, not just the champion. |
| 4 | Hybridize GA + gradients | Our 44.73T "evals" are 99.99% 60ns surrogate screens (oracle: 4.7M) — the compute frame differs from a plain GA. Still: continuous genes + uniform proposals waste budget. CMA-ES on the continuous subspace (or simply **flux-weighted per-gene sigma**, see §6) is the cheap win. | **v0.6e** |
| 5 | Benchmark properly | Anchors: x264/x265/SVT-AV1/libaom on our corpus. **BD-rate vs anchors ships today.** Kodak/CLIC/DIV2K/Tecnick + JPEG-AI/AVIF/VVC anchors = real CI weight; JPEG AI is the learned-codec standard to race. | **shipped (BD-rate) → v0.7**: standard corpora in the anchor job only (never in selection). |
| 6 | Distill, don't just evolve | No networks to distill yet; but KD-NVC (arXiv 2606.04595) validates the pattern. Arena version: **hard latency budget** as a gate (not penalty) + a distilled "fast config" derived from the champion's gene mask. | **v0.6f**: `enc_budget_ms10` config, default off. |
| 7 | Robustness / anti-overfitting | **The gene-credit table IS the overfitting receipt** (intra/deblock/qpel selected against = corpus artifacts). Rungs: (a) tag corpus clips by content-type, (b) rotate a slice of the corpus per run (seeded, deterministic per run-number), (c) holdout clips the selector never sees, scored at crowning only, (d) stratified reporting in LESSONS. | **v0.7** — the single highest-leverage change after v0.6a. |
| 8 | Search efficiency | Surrogate screens already implement "cheap predictor, expensive confirm". Missing: operator-level credit assignment (which mutation ops produce crowns?) — needs an op-tag in lessons.jsonl (one-line evolve.py patch) — and MAP-Elites warm-start (#3). | **v0.6e** |

---

## 5. What the current literature says (2024–2026)

- **Conditional-coding neural video codecs are the frontier**: Microsoft's
  DCVC family (DCVC-DC → DCVC-FM → DCVC-RT, the latter real-time at CVPR
  2025) treats the decoded previous frame as conditioning, not residual
  input — lower entropy bound than residual coding. EV-NVC (2025) reports
  −30.6% BD-rate vs HM-16.25 low-delay with variable-rate-in-one-model.
  *Lesson for us*: our inter frame already conditions on the decoded prior —
  the champions' `keyint→0.03` is a crude version of the same insight.
- **Entropy models move by context structure**: checkerboard context models
  (He et al., CVPR 2021, 577+ cites) made autoregressive context parallel;
  cubic/neighborhood variants (C-CTX 2026) keep pushing. *Lesson*: our
  entropy gene currently gates one coder; a context-shape gene family is the
  natural v0.7 extension.
- **Predictor-guided evolution is standard**: 2025's evolutionary NAS papers
  (dual-contrastive performance predictors, bi-level ENAS) all evolve with a
  learned predictor in the loop and oracle-confirm elites — the exact
  two-instrument design the arena shipped in v0.2. Good: we're on-protocol
  with the field. Bad: they all add *predictor uncertainty* to the
  acquisition step, which our screen kernel lacks.
- **Perceptual metrics in benchmarks**: the learned-compression benchmark
  methodology (videoprocessing.ai) reports MS-SSIM and LPIPS rate-distortion
  curves side by side; CLIC winners have optimized GAN/perceptual losses
  since 2021. BD-rate (PCHIP variant recommended over the original cubic
  spline) is the universal cross-codec yardstick — ours now matches the
  reference implementations.
- **JPEG AI** is the first standardized learned image codec — the honest
  "best of the best" still-image bar to add to the anchor job.

---

## 6. What mycelium and algae teach (and the exact mechanisms we borrow)

### Physarum (slime mold) — flux-reinforced transport
Tero et al. (Science 2007, 574+ cites) modeled how Physarum's tubes adapt:
a tube carrying high nutrient **flux thickens**, an unused tube prunes —
convergence to near-Steiner-optimal transport networks (it famously rebuilt
the Tokyo rail map). Two mechanisms map directly:

1. **Flux-weighted mutation rates.** Our `mutate()` picks genes uniformly —
   every axis gets equal proposal pressure forever. Physarum says: *measure
   the flow, then thicken the pipes that carry it.* Concretely: keep a
   per-gene EMA of `|Δfit| × parentage` (how much fitness flow each gene
   axis has carried recently) and draw mutation indices ∝ that weight, with
   a floor so silent genes never starve entirely (dormant tubes regrow when
   the environment changes — keyint taught us environments change). This is
   the arena-native version of adaptive operator rates and it is ~15 lines
   in evolve.py. → **v0.6e**
2. **Forage-then-refine phases.** Physarum explores broadly, then prunes
   hard. Our sigma anneals per-run, but every run re-walks the same corpus.
   With corpus rotation (#7), the forage phase should *re-trigger on
   landscape change* — detect via the canalization probe's median delta
   jumping, and reset sigma + jump_p when it does.

### Algae pyrenoids — concentrate the scarce resource at the active site
Eukaryotic algae run a CO₂-concentrating mechanism: Rubisco (the enzyme that
fixes carbon) is packed into a liquid-liquid phase-separated pyrenoid, and
thylakoid tubules deliver CO₂ *directly at the active site* (Fei et al.,
Nature Plants 2022 — the modeling shows the geometry saturates the enzyme).
The lesson is about **economy of the scarce resource**: don't diffuse it —
pipe it to where the reaction happens. Arena translation:

- The scarce resource is **oracle time** (~0.26 s/bot). Today candidates
  reach the oracle via one uniform-ish gate. The pyrenoid pattern says:
  batch-deliver oracle evaluations *around the current elites* (the active
  site) — i.e., epsilon-mutant clouds around the top-k genomes get first
  claim on the oracle budget, with the immigrant stream kept small but
  nonzero (the stroma still needs ambient CO₂). The canalization probe
  already proves the value of elite-local evaluation: it finds polish
  gains on every crown.
- The **CO₂/O₂ ratio at the active site** is a signal-to-noise metaphor:
  prefer spending oracle on candidates whose *surrogate uncertainty* is
  high AND whose surrogate score is high — score-plus-uncertainty
  acquisition, the single most-requested upgrade in the NAS literature.

### Bet-hedging / seed banks (both organisms)
Algae cysts and fungal spores persist through bad environments and repopulate
when conditions shift. Our MAP-Elites archive + pareto.json is exactly a seed
bank — **reactivate** archive lineages (not just the champion) into the seed
population when a run's best stagnates for k generations or when the corpus
rotates. Diversity is stored, not re-derived.

---

## 7. Benchmark honesty statement

Until the v0.7 corpus work lands, the truthful claim is: *best-known bot
within our evolutionary run, on a synthetic five-archetype corpus, measured
in luma PSNR, versus x264/x265/SVT-AV1/libaom anchors run on the same
corpus*. The champions are genuinely optimized (the gene ledger shows real
selection pressure, and the complexity-penalized crowning is now aligned
end-to-end) — but PSNR-on-synthetic-content says little about natural video,
and chroma quality has only just become visible. The instrument upgrades in
this release (Pareto front, BD-rate, Y/U/V separation) exist precisely to
make the next claims measurable.

---

## 8. Shipped in v0.5d (this release)

- `tools/gene_credit.py` + `GENE_CREDIT.md` — the gene-credit ledger, mined every merge.
- `tools/pareto.py` + `halloffame/pareto.json` — the non-dominated champion archive.
- `tools/bdrate.py` — PCHIP BD-rate, champion RD sweep vs anchor curves, in LEADERBOARD + crowning issues.
- Chroma visibility: `psnr_u`/`psnr_v` measured, reported, and anchored (fitness unchanged — migration law).
- evolve.py padding-id collision fix.
- This document.
