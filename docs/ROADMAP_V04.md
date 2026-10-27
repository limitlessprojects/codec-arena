# ROADMAP v0.4 — learning from the best of the best

The arena's fitness is `psnr − 14·bpp − complexity`. The bar is x264 at the
same PSNR instrument. The champion gap (~8.6 dB) is structural: it cannot be
closed by tuning 22 parameters over a fixed architecture. This document is
the extraction of what the best encoders in the world actually do, mapped to
arena rungs, and the operating doctrine for how the arena compounds.

## What the best of the best actually do

| source | technique | why it wins | arena status |
|---|---|---|---|
| H.264 / x264 | **Spatial intra prediction** (DC/planar/angular, from reconstructed neighbors) | removes 30–60% of intra-block energy before the transform | ✅ **v0.4 rung 1** — gene `intra_pred` (g16): NONE / {NONE,DC} / 5-mode / 8-mode sets, clamp-aware mode decision, bit-packed per-plane mode map |
| H.264 / x264 | **In-loop deblocking** | smooths block edges before they become references and output; compounds across motion | ✅ **v0.4 rung 2** — gene `deblock` (g17): H.264-lite alpha/beta edge filter, frame-atomic, zero side info |
| H.264 / x264 | Context-adaptive entropy coding (CAVLC→CABAC) | 5–15% bitrate at equal quality vs flat varints | ⬜ v0.5 rung: adaptive binary arithmetic coding of (run, level) with per-band contexts |
| x264 / x265 | Quarter-pel motion compensation (6-tap Wiener) | ~0.3–0.6 dB over half-pel bilinear | ⬜ v0.5 rung (gene `halfpel` already proves the signaling pattern) |
| x265 / HM | RD-optimized quantization (RDOQ) + rate-distortion mode decision | spends bits where the RD curve pays | ⬜ v0.6 rung: lambda-guided mode decision replaces pure SAD |
| AV1 (libaom/SVT-AV1) | CDEF + loop restoration | in-loop refinement beyond deblocking | ⬜ v0.7 rung |
| AV1 / VVC | Partitioning (8×8 → 4×4/16×16 tree) | rate control at the block-size axis | ⬜ v0.7+ (biggest code change; do after entropy) |
| SVT-AV1 | symbol-decoder-first architecture | encoder/decoder can never disagree | ✅ already the arena's law — one shared code path per mechanism |

The pattern across every generation of codecs: **structure beats tuning**.
Each structural rung resets the search landscape and re-prices every genome;
the genes then re-tune automatically — that is what 8.9 trillion evaluations
a day is for.

## v0.4 migration law (the reason it is safe)

Gene value `0.0` on `intra_pred`/`deblock` is **byte-exact legacy behavior**.
Verified locally against the standing champion: bot 9501400041 with
`(0.0, 0.0)` measures `24.85 dB / 0.4057 bpp / fit 19.170` — identical to the
pre-v0.4 oracle. Therefore:

- the Hall of Fame floor (fit 19.1702) stays comparable across the upgrade;
- old pop files (v1/v2) parse and migrate with the new genes at 0.0;
- the surrogate model extends 159 → 161 floats with the new linear weights at
  zero — screens stay exactly as skilled as before, and per-shard refits
  learn the new genes' worth from live oracle rows;
- richer mode sets always include NONE as mode 0, so prediction can only be
  selected when it strictly reduces pre-quant error — features can never
  crater a genome, only reprice it.

## The Sacco doctrine (how we run the compound)

NewFortis Sacco started in 1976 with 857 teachers and a rulebook. Fifty years
later it pays out over a billion shillings a year and wins "best large SACCO"
awards. Nothing about that is magic; it is the same mechanics this arena runs
on, and we adopt them explicitly:

1. **Pool the idle.** A SACCO turns members' dormant savings into working
   capital. The arena turns GitHub's free hosted runners — idle by default —
   into a ~9-13 trillion-evaluations-per-day search. The compute was always
   there; the bylaw change was to actually use it (heartbeat-driven cadence,
   ~8-12 runs/day at $0).
2. **Compound daily; never borrow.** Counters are member equity: oracle and
   search evals only ever accumulate from real work, never borrow from each
   other, and a lost push race fails loudly instead of silently shrinking the
   book. Dividends are the champion-gated reports — paid only on genuine
   improvement, never on noise.
3. **Amend the bylaws to widen membership.** NewFortis outgrew "teachers
   only" by amending its by-laws. v0.4 admits two new members to the gene
   pool (intra prediction, deblocking) with a migration rule that protects
   every existing member's recorded value. More rungs will be admitted the
   same way — each one gene-gated, each one migration-safe.
4. **Patient horizon.** The SACCO thinks in decades. The arena's 10-year
   thesis is pinned in the playbook: small codecs + free compounding compute
   + structural rungs = asymmetric upside with near-zero downside. A run
   that "only" adds 0.01 to champion fit is a deposit, not a failure.

## Next rungs in order of expected leverage

1. **v0.5 — adaptive entropy coding** (CABAC-lite on (run, level), per-band
   contexts, gene-gated like v0.4). Expected: the single biggest bpp win
   available without touching transform or partitioning.
2. **v0.5b — quarter-pel MC** (4-tap interpolation, gene-gated beside
   `halfpel`).
3. **v0.6 — RD-guided intra/inter decision** (replace SAD proxy with
   lambda-weighted rate+distortion; reuses the arena's own λ=14 as the
   starting exchange rate).
4. **v0.7 — partitions and larger transforms** (block-size tree, 16×16
   transform for intra).

Each rung ships with: byte-exact legacy at gene 0.0, closed-loop roundtrip
tests, champion determinism check, and a surrogate layout that starts
neutral and learns from live oracle rows.
