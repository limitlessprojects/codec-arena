# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **5,347,200**
Candidate evaluations, all instruments (screens + oracle): **47,700,005,347,200**
Merge runs: 36.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
Search milestones: {"1e6": "run 4", "1e9": "run 4", "1e12": "run 4"}

The two counters never borrow from each other: a surrogate screen is
a candidate judged cheaply; only the oracle (real encode+decode) can
put a bot on this board.

## The bar (real codecs, same corpus, same PSNR instrument)

| codec | PSNR | bpp |
|---|---|---|
| x264 | 33.48 | 0.1275 |
| x265 | 32.29 | 0.0846 |
| svtav1 | 34.86 | 0.0636 |
| libaom | 33.93 | 0.0734 |

## Shard champions (this run)

| shard | bot | gen | tribe | psnr | bpp |
|---|---|---|---|---|---|
| 3 | 30006954 | 28 | 14 | 31.68 | 0.1820 |
| 16 | 160007165 | 28 | 14 | 31.67 | 0.1831 |
| 12 | 9501200027 | 28 | 13 | 31.68 | 0.1824 |
| 10 | 100006952 | 28 | 14 | 31.64 | 0.1865 |
| 2 | 9500200025 | 28 | 17 | 31.69 | 0.1813 |
| 9 | 90006782 | 28 | 14 | 31.68 | 0.1817 |
| 5 | 50006731 | 28 | 17 | 31.68 | 0.1816 |
| 7 | 9500700010 | 28 | 16 | 31.69 | 0.1813 |
| 13 | 130007008 | 28 | 12 | 31.69 | 0.1817 |
| 18 | 9501800052 | 28 | 12 | 31.69 | 0.1817 |
| 1 | 9500100040 | 28 | 12 | 31.69 | 0.1817 |
| 14 | 9501400024 | 28 | 13 | 31.69 | 0.1819 |
| 4 | 40007165 | 28 | 12 | 31.68 | 0.1813 |
| 11 | 110007001 | 28 | 12 | 31.68 | 0.1816 |
| 8 | 80007014 | 28 | 17 | 31.68 | 0.1822 |
| 6 | 60007072 | 28 | 12 | 31.68 | 0.1815 |
| 0 | 7107 | 28 | 13 | 31.68 | 0.1822 |
| 15 | 9501500026 | 28 | 13 | 31.68 | 0.1824 |
| 17 | 9501700029 | 28 | 12 | 31.69 | 0.1840 |
| 19 | 190007160 | 28 | 12 | 31.68 | 0.1818 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1811 bpp — quality gap 1.8 dB, bits gap 0.1811 vs 0.161 (x264 qp40 point).

## The Pareto front (non-dominated champions ever)

| bot | psnr | bpp | enc_ms10 | dec_mops |
|---|---|---|---|---|
| 130007008 | 31.69 | 0.1817 | 1783.2 | 13.59 |
| 9501400024 | 31.69 | 0.1819 | 1782.6 | 13.6 |
| 9500200025 | 31.69 | 0.1813 | 1407.3 | 13.62 |
| 110007001 | 31.68 | 0.1816 | 1784.2 | 13.59 |
| 9501200027 | 31.68 | 0.1824 | 975.6 | 13.62 |
| 30006954 | 31.68 | 0.1820 | 947.2 | 13.63 |
| 90006782 | 31.68 | 0.1817 | 1404.9 | 13.59 |
| 160007165 | 31.67 | 0.1831 | 962.3 | 13.6 |

A bot on this line is unbeatable on at least one trade-off axis —
the crowning rule uses the scalar fitness, this board honors the
specialists (faster-at-equal-quality, smaller-at-equal-quality).
## Gene credit (which genes selection rewards)

See [GENE_CREDIT.md](GENE_CREDIT.md) — mined from every recorded
generation's selection signals plus the champion lineage drift.
