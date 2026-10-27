# ROADMAP v0.5 — the AV1 lineup rung

*Companion to ROADMAP_V04 (the Sacco doctrine + the x264 rungs). v0.5 is the
answer to a new question: what do the best codecs alive actually do that we
don't? The AV1 family — libaom, SVT-AV1, rav1e, dav1d — is the strongest
lineup on the bar table (svtav1: 34.86 dB @ 0.0636 bpp on this corpus). This
rung imports the three AV1 structures with the highest leverage-to-weight
ratio, gene-gated and migration-safe exactly like v0.4.*

## What was learned from the AV1 lineup

1. **Adaptive binary arithmetic coding** (g18 `entropy`). AV1's entropy core
   is a symbol-to-symbol adaptive multisymbol arithmetic coder (daala EC
   lineage); x264/CABAC decompose symbols into binary decisions with
   adaptive state. v0.5 ports the binary form: an LZMA-style carry-propagating
   range coder + 47 adaptive 11-bit probability contexts (LZMA update rule,
   truncated so 1 <= p <= 2047), coding markers, motion vectors, and
   (run, level) pairs through truncated-unary + raw-bit binarization with
   escape tiers. The mode map keeps its bit-packed form. Gene 0 = the exact
   v0.4 byte stream.
2. **Chroma-from-luma** (g19 `cfl`). AV1 predicts chroma from the
   co-located reconstructed luma (Valin/Egge): decimate 16x16 luma to 8x8 by
   2x2 mean, remove the mean, scale by a signed alpha, add the chroma DC
   base. Implemented as FOUR extra chroma intra modes (alpha x 2 = -2, -1,
   +1, +2) — they ride the existing per-plane mode map, so CFL costs zero
   extra signaling. Zero side info: both sides share the same pre-deblock
   luma recon when chroma is coded.
3. **CDEF-lite** (g20 `cdef`). AV1's constrained directional enhancement
   filter, simplified: 4 line orientations picked by constrained-gradient
   argmin on the RECONSTRUCTED block (decoder-derivable, zero signaling),
   5-tap constrained averaging along the line with qp-scaled damping, skip
   on isotropic blocks. Frame-atomic, shared enc/dec path, after deblocking.
4. **SMOOTH + PAETH intra modes** (folded into the intra_pred gene's top
   tier, >= 0.925). AV1's smooth family and PNG's nearest-edge predictor
   join the mode set as modes 8 and 9.

## The migration law (same as v0.4, now proven twice)

- genome v4: 21 effectors + 6 regulators = 27 genes, 32-token pop lines.
  v1/v2/v3 lines parse with the new genes at 0.0 = exact legacy behavior.
- The standing champion (a v2-line bot) measures **24.85 dB / 0.4057 bpp /
  fit 19.1702 byte-exact** under the v0.5 binary — the Hall of Fame floor
  stays comparable.
- Surrogate model v4: 164 = 1 + 27 linear + 136 quadratic over the legacy
  16; old models (153/159/161) migrate by inserting neutral zeros at the
  right slots, so per-shard refits stay alive across the upgrade.

## Local measurement at the champion operating point (corpus of 5 clips)

| variant | PSNR | bpp | fit = psnr - 14 bpp |
|---|---|---|---|
| champion, legacy paths (migration law) | 24.85 | 0.4057 | 19.1702 |
| + 8-mode intra (v0.4 rung alone) | 24.85 | 0.4526 | 18.51 |
| + entropy gene (AC stream) | 25.87 | 0.1340 | **23.99** |
| + entropy + cfl | 25.87 | 0.1392 | 23.92 |
| + entropy + cfl + cdef | 26.04 | 0.1388 | **24.10** |
| + entropy + cfl + cdef + 10-mode | 26.04 | 0.1492 | 23.95 |

Readings: the entropy rung is the single largest jump in arena history
(fit +4.8) — the varint stream was ~4.7x too fat, and the adaptive-Q loop
reinvests the freed bytes into quality. CDEF adds ~0.17 dB at near-zero
bit cost. CFL and the 10-mode set are roughly neutral at this operating
point on this corpus — which is exactly what the arena is for: evolution,
not the architect, decides where they pay.

## Bugs the discipline caught before they could ship

- **Vanishing probability**: the naive signed-shift LZMA update
  ((0 - p) >> 5 = -1 for p <= 31) can drive a context probability to 0,
  which zeroes the coded subinterval and spins the renormalization loop
  forever. Fix: truncated move + hard clamps (1 <= p <= 2047). Found by
  local RD instrumentation, not by luck.
- **Undefined decoder handle**: the AC reader's inner state was built with
  an unassigned stream pointer — valid-looking stack garbage in the test
  binary, a segfault in the release binary. Fix: explicit initialization;
  the closed-loop tests now cover the AC-on path end to end.
- **v4 parser slot bug**: v3-only g16/g17 branch zeroed the v0.4 genes on
  32-token lines. Caught because variant B/C measured identical to legacy;
  fixed and locked with a 21-gene round-trip parse test.

## Next rungs in order of expected leverage

0. **v0.5b — quarter-pel MC — SHIPPED** (4-tap Wiener interpolation,
   gene-gated beside `halfpel`). The AV1-lineup pattern: Wiener-filtered
   halves (`-1,9,9,-1 >> 4`, clamped — x264 convention), bilinear quarters,
   diagonal halves = vertical 4-tap of the horizontal half plane (H.264's
   j-from-b canonical order). 5x5 quarter lattice, 5-bit subpel code
   (code = (qx+2)*5+(qy+2), 12 = integer center). Production MC reads
   prebuilt half-planes (the libaom/SVT-AV1 interpolated-reference-buffer
   pattern) — per-pixel filtering cost went +267% -> +39% with the cache,
   and a stage-2 cost gate (skip the quarter ring when no half-pel beat the
   integer MV) bought back another ~20% while IMPROVING RD slightly.
   Measured at the champion operating point (29.67 dB @ 0.2113 bpp):
   qpel-on = +0.07 dB for +0.0088 bpp -> -0.053 fitness. Strictly-safe
   (gene 0.0 byte-exact, champion determinism verified) — selection decides.
   Also shipped in this rung: **champion warm-start seeding** — every run
   used to re-walk from the same static v3-era seed; shards whose
   deterministic RNG path landed in a bad basin (shard 2: 24.98 dB @ 0.4694
   bpp vs the pack at 26.3-27.1) stayed stuck forever. merge now rebuilds
   pop/seed.txt as 6 jittered champion-lineage tribes (sigma 0.02..0.22) +
   archetypes + explorers; the basin is inherited, not re-discovered.
1. **v0.6 — RD-guided intra/inter decisions** (lambda-weighted rate+distortion
   using the arena's own exchange rate).
2. **v0.6b — context refinement**: band-split level contexts (DC / low / high
   bands), intra/inter context split — cheap bits on top of the AC engine.
3. **v0.7 — partitions and larger transforms** (block-size tree, 16x16 intra
   transform).

Each rung ships with: byte-exact legacy at gene 0.0, closed-loop roundtrip
tests, champion determinism check, and a surrogate layout that starts
neutral and learns from live oracle rows.
