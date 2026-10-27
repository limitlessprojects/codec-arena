# Research Notes (the bar, with receipts)

Compiled 2026-10-24. Sources listed so future-us can re-verify.

## Where the frontier actually is

- **Learned image compression plateaued**: CLIC 2025 results show no
  significant year-over-year improvement vs CLIC 2024 at the anchor
  (mabyduck.com blog, Dec 2025). Best decoders run seconds-per-image at
  0.075 bpp — complexity remains the catch.
- **Neural video codecs beat VVC on RD, lose on complexity**: DCVC-RT
  delivers ≈ **−21% BD-rate vs VTM (H.266 ref)** at real-time decode
  (streaminglearningcenter.com, May 2025); follow-ups (arXiv 2510.14431)
  push another −12% vs DCVC-RT. Decode complexity 50–100× an ASIC decoder
  remains the structural drawback.
- **Classical codecs keep grinding**: SVT-AV1 at slow presets reaches the
  same VMAF as x264-medium at ≈ **55% less bitrate** on typical content
  (forasoft 2026 benchmark); SVT-AV1 4.x / x265 4.2 / NVENC Blackwell ship
  through 2026 without reordering the frontier.

## Why an evolutionary arena is the right cheap instrument

- Codec search spaces (partitioning, quantization matrices, search ranges,
  rate-control schedules) are **combinatorial with weak gradients** — exactly
  where population methods earn their keep; big labs tune these by hand and
  ablation, which is slow and unpublished.
- The competitions circuit (CLIC, IEEE ISCAS/VCIP grand challenges, PCS)
  optimizes **BD-rate under complexity constraints** — our fitness
  (`PSNR − λ·bpp − complexity`) is a small-scale mirror of that objective.
- Nobody runs a *public, continuous, population-scale* strategy search with
  an external anchor. That's the gap this repo occupies. (Related work:
  GA-based encoder parameter tuning exists in the literature — our novelty
  is the open arena + cumulative counter + honest bar, not "GA invented
  here".)

## The 100-year context (why wins are incremental)

Temporal redundancy (1929–1959) → DCT (1972) → motion-compensated hybrid
codecs (1988–2003) → hardware standardization (2003–). Modern gains are
10–30% per generation, fought for at PCS/CLIC/VCIP. Anyone promising more is
selling something; anyone measuring it honestly is welcome here.

## Implications for our targets

- Seed pool (~18 dB @ 2 bpp) vs x264 (35.4 dB @ 0.161 bpp) on our corpus:
  the naive-codec gap is ~17 dB / ~12×. That gap is our search space; even
  single-digit-% closures are meaningful, publishable micro-wins.
- Complexity penalties in fitness keep solutions on the "cheap decoder" side
  of the frontier — the side neural codecs abandoned, and the side storage
  farms actually need.

## Mining pass — 2026-10-28 (v0.5b era)

Second deep pass over the best encoders alive plus the upcoming wave, each
mapped to a concrete absorption path in the arena's genome/codec.

### From the SVT-AV1 pit (github.com/AOMediaCodec/SVT-AV1)
- **Variance-boost / superblock qindex**: per-block q modulation driven by
  local spatial variance — the encoder spends bits where detail lives.
  *Arena mapping*: our adaptq gene + row_q/mv_q regulators already modulate
  per block; the missing piece is a **spatial-activity context** (block SAD
  variance is encoder-side only, but block variance of the RECON is
  decoder-derivable — a natural v0.6b regulator context, zero side-info).
- **Temporal filtering (ARF/TPL family)**: forward-reference filtering and
  lookahead rate allocation. Biggest single RD lever in SVT-AV1's arsenal.
  *Arena mapping*: needs multi-reference frames (v0.7+); park until the
  partition rung lands. Lesson recorded: the arena's single-reference GOP is
  leaving real bits on the table vs every production encoder.
- **Adaptive transform blocks (10-bit TF)**: transform size adapts to
  content. *Arena mapping*: our fixed 8x8 DCT is the v0.7 rung's target.

### From the VVC camp (VVenC / Fraunhofer HHI)
- **Dependent quantization (DQ)**: quantization decisions coupled across
  coefficients (state-machine quantizer) — recovers rate without a trellis
  pass. *Arena mapping*: our (run,level) AC contexts are the natural host;
  a v0.6b "level-context band split" is DQ-lite (cheap, decoder-mirrored).
- **XPSNR perceptual optimization (VVenC's XPO)**: distortion metric weights
  q decisions. *Arena mapping*: our fitness IS the exchange rate
  (PSNR − λ·bpp); a perceptual band-weight variant of the fitness is a
  *screen-level* experiment, not a codec change — zero bitstream cost.
- **Two-pass rate control**: park — the arena's operating point discipline
  (RD sweep per champion) already covers the single-pass case.

### The AV2 wave (AOMedia, launched end-2025)
- Same complexity generation as VVC ECM. Watch list for the next mining
  pass: their take on MC interpolation filters (we just shipped the 4-tap
  Wiener), in-loop tools, and entropy context design. When libaom-style
  reference code lands, mine it the same way we mined AV1.

### The revolutionary fringe (implicit neural representations)
- INR codecs overfit a compact network to ONE video (arXiv 2506.24127 and
  the DCVC line): global structure captured, per-video optimization.
- **The arena already IS a crude INR**: each shard overfits a genome to its
  corpus slice through 28 generations of RD-guided selection. The lesson is
  not "add a neural net" — it is that per-content optimization is the
  frontier, and our warm-start seeding (champion-lineage tribes) is the
  classical version of it. Revisit when a neural module can live inside a
  GitHub-runner CI budget (~4 GB RAM, 4 cores, 90 min/shard).
