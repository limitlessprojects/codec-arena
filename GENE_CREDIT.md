# Gene Credit Report

Which genes does selection actually reward? Two evidence streams:
**(1)** selection signals from every recorded generation (top-10% mean
minus population mean; positive = winners carry more of this gene),
**(2)** how each gene's value drifted across the champion lineage,
plus where the champion genome is fragile (canalization probe).

Generations mined: **3627** · crowns scanned: **7** · genes with any signal: **27/28**

| gene | signal count | mean signal | + / − | champion drift |
|---|---|---|---|---|
| entropy | 173 | +0.344 | 172 / 1 | pinned 0.90 |
| baseq | 483 | +0.176 | 475 / 8 | pinned 1.00 |
| skip | 1004 | +0.174 | 944 / 60 | pinned 1.00 |
| chroma_q | 605 | +0.128 | 561 / 44 | pinned 1.00 |
| q_mid | 410 | +0.113 | 399 / 11 | pinned 1.00 |
| p_qmul | 784 | +0.109 | 648 / 136 | pinned 1.00 |
| q_high | 258 | +0.099 | 230 / 28 | pinned 0.98 |
| deadzone | 809 | +0.094 | 689 / 120 | 0.38 → 1.00 |
| cdef | 1 | +0.082 | 1 / 0 | 0.09 → 0.00 |
| cfl | 8 | +0.035 | 5 / 3 | 0.00 → 0.08 |
| q_low | 414 | +0.024 | 242 / 172 | pinned 0.00 |
| refresh | 911 | +0.021 | 552 / 359 | 0.20 → 0.92 |
| mv_q | 74 | +0.017 | 42 / 32 | pinned 0.48 |
| qpel | 0 | +0.000 | 0 / 0 | 0.00 → 0.12 |
| gop_q | 50 | -0.000 | 23 / 27 | pinned 1.00 |
| intra_gop | 91 | -0.001 | 42 / 49 | 0.25 → 0.60 |
| dither | 377 | -0.005 | 158 / 219 | 0.47 → 1.00 |
| row_q | 3 | -0.025 | 1 / 2 | pinned 0.50 |
| deblock | 177 | -0.029 | 58 / 119 | pinned 0.00 |
| intra_b0 | 626 | -0.033 | 233 / 393 | pinned 0.00 |
| adaptq | 662 | -0.034 | 263 / 399 | 0.62 → 0.77 |
| halfpel | 652 | -0.057 | 223 / 429 | 0.07 → 0.22 |
| skip_mv | 57 | -0.074 | 13 / 44 | 0.39 → 0.00 |
| mv_dz | 125 | -0.112 | 10 / 115 | 0.38 → 0.00 |
| search | 342 | -0.115 | 56 / 286 | pinned 0.20 |
| dz_dc | 735 | -0.143 | 45 / 690 | 0.12 → 0.00 |
| intra_pred | 143 | -0.144 | 7 / 136 | pinned 0.04 |
| keyint | 424 | -0.345 | 0 / 424 | pinned 0.03 |

## The silent list

Genes selection has never rewarded (zero signal in the ledger): **qpel**.

Reading: the proposal distribution mutates all genes uniformly,
so silence means selection has had no reason to move them — either
the feature is RD-neutral on this corpus (candidate for removal or
for a corpus that stresses it) or its useful range is narrow and
the 0.08 signal threshold is too coarse to see it.

## Fragility (canalization worst_gene across crowns)

- **keyint**: 7 crown(s) most fragile to ±0.02 perturbation
