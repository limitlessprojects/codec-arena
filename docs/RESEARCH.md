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
