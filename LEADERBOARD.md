# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **3,700,060**
Candidate evaluations, all instruments (screens + oracle): **31,376,003,700,060**
Merge runs: 25.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 2 | 9500200004 | 28 | 12 | 31.67 | 0.1826 |
| 8 | 80007134 | 28 | 14 | 31.66 | 0.1837 |
| 11 | 9501100032 | 28 | 13 | 31.67 | 0.1849 |
| 10 | 100006907 | 28 | 16 | 31.70 | 0.1871 |
| 12 | 120006783 | 28 | 13 | 31.68 | 0.1861 |
| 1 | 10007033 | 28 | 13 | 31.61 | 0.1816 |
| 18 | 9501800020 | 28 | 12 | 31.66 | 0.1852 |
| 14 | 140006505 | 28 | 15 | 31.62 | 0.1824 |
| 4 | 40006559 | 28 | 12 | 31.62 | 0.1826 |
| 9 | 9500900017 | 28 | 12 | 31.62 | 0.1826 |
| 13 | 130007029 | 28 | 12 | 31.67 | 0.1863 |
| 3 | 30007044 | 28 | 12 | 31.61 | 0.1826 |
| 15 | 9501500002 | 28 | 12 | 31.60 | 0.1822 |
| 7 | 70007025 | 28 | 12 | 31.60 | 0.1824 |
| 16 | 160006985 | 28 | 12 | 31.60 | 0.1825 |
| 6 | 60006967 | 28 | 12 | 31.61 | 0.1834 |
| 0 | 9500000039 | 28 | 15 | 31.60 | 0.1827 |
| 19 | 9501900022 | 28 | 13 | 31.59 | 0.1831 |
| 17 | 9501700030 | 28 | 13 | 31.59 | 0.1850 |
| 5 | 50007068 | 28 | 12 | 31.26 | 0.1796 |

Champion vs the x264 bar (33.48 dB): champion 31.67 dB @ 0.1826 bpp — quality gap 1.8 dB, bits gap 0.1826 vs 0.161 (x264 qp40 point).
