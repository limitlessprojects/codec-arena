# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **5,496,940**
Candidate evaluations, all instruments (screens + oracle): **49,184,005,496,940**
Merge runs: 37.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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

| shard | bot | gen | tribe | psnr | bpp | ms-ssim |
|---|---|---|---|---|---|---|
| 4 | 40006997 | 28 | 14 | 31.69 | 0.1810 | 0.0000 |
| 19 | 190007047 | 28 | 12 | 31.69 | 0.1816 | 0.0000 |
| 17 | 170007122 | 28 | 14 | 31.69 | 0.1819 | 0.0000 |
| 8 | 80007141 | 28 | 12 | 31.68 | 0.1825 | 0.0000 |
| 1 | 10006980 | 28 | 10 | 31.69 | 0.1820 | 0.0000 |
| 0 | 7050 | 28 | 12 | 31.68 | 0.1811 | 0.0000 |
| 7 | 70006796 | 28 | 12 | 31.68 | 0.1820 | 0.0000 |
| 12 | 9501200027 | 28 | 12 | 31.68 | 0.1818 | 0.0000 |
| 15 | 9501500022 | 28 | 14 | 31.69 | 0.1820 | 0.0000 |
| 18 | 180006975 | 28 | 14 | 31.69 | 0.1821 | 0.0000 |
| 16 | 9501600038 | 28 | 12 | 31.68 | 0.1821 | 0.0000 |
| 14 | 140007029 | 28 | 13 | 31.67 | 0.1832 | 0.0000 |
| 10 | 9501000005 | 28 | 14 | 31.66 | 0.1836 | 0.0000 |
| 9 | 90007112 | 28 | 12 | 31.68 | 0.1819 | 0.0000 |
| 5 | 50006556 | 28 | 13 | 31.69 | 0.1816 | 0.0000 |
| 3 | 30006352 | 28 | 17 | 31.69 | 0.1821 | 0.0000 |
| 13 | 9501300008 | 28 | 12 | 31.69 | 0.1819 | 0.0000 |
| 2 | 9500200032 | 28 | 12 | 31.68 | 0.1817 | 0.0000 |
| 11 | 9501100044 | 28 | 16 | 31.68 | 0.1821 | 0.0000 |
| 6 | 60006964 | 28 | 12 | 31.68 | 0.1821 | 0.0000 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1811 bpp — quality gap 1.8 dB, bits gap 0.1811 vs 0.161 (x264 qp40 point).

## The Pareto front (non-dominated champions ever)

| bot | psnr | bpp | enc_ms10 | dec_mops |
|---|---|---|---|---|
| 130007008 | 31.69 | 0.1817 | 1783.2 | 13.59 |
| 9501400024 | 31.69 | 0.1819 | 1782.6 | 13.6 |
| 9501500022 | 31.69 | 0.1820 | 1402.4 | 13.59 |
| 40006997 | 31.69 | 0.1810 | 958.6 | 13.62 |
| 110007001 | 31.68 | 0.1816 | 1784.2 | 13.59 |
| 30006954 | 31.68 | 0.1820 | 947.2 | 13.63 |
| 90006782 | 31.68 | 0.1817 | 1404.9 | 13.59 |
| 7050 | 31.68 | 0.1811 | 1011.4 | 13.6 |
| 160007165 | 31.67 | 0.1831 | 962.3 | 13.6 |

A bot on this line is unbeatable on at least one trade-off axis —
the crowning rule uses the scalar fitness, this board honors the
specialists (faster-at-equal-quality, smaller-at-equal-quality).
## Gene credit (which genes selection rewards)

See [GENE_CREDIT.md](GENE_CREDIT.md) — mined from every recorded
generation's selection signals plus the champion lineage drift.
