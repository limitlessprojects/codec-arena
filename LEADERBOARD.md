# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **3,550,320**
Candidate evaluations, all instruments (screens + oracle): **29,892,003,550,320**
Merge runs: 24.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 9 | 90006982 | 28 | 13 | 31.62 | 0.1828 |
| 19 | 9501900004 | 28 | 12 | 31.61 | 0.1825 |
| 1 | 9500100030 | 28 | 13 | 31.61 | 0.1845 |
| 13 | 130006945 | 28 | 12 | 31.59 | 0.1851 |
| 10 | 9501000052 | 28 | 12 | 31.58 | 0.1846 |
| 11 | 110007068 | 28 | 12 | 31.59 | 0.1860 |
| 6 | 9500600033 | 28 | 13 | 31.57 | 0.1874 |
| 18 | 9501800015 | 28 | 15 | 31.63 | 0.1919 |
| 2 | 9500200026 | 28 | 13 | 31.53 | 0.1882 |
| 16 | 9501600040 | 28 | 12 | 31.53 | 0.1889 |
| 12 | 120007024 | 28 | 15 | 31.55 | 0.1910 |
| 7 | 9500700012 | 28 | 12 | 31.58 | 0.1958 |
| 5 | 9500500052 | 28 | 12 | 31.57 | 0.1980 |
| 15 | 9501500015 | 28 | 17 | 31.24 | 0.1816 |
| 17 | 9501700008 | 28 | 12 | 31.19 | 0.1839 |
| 4 | 40007086 | 28 | 12 | 31.20 | 0.1854 |
| 8 | 80006990 | 28 | 12 | 31.19 | 0.1865 |
| 3 | 9500300048 | 28 | 13 | 31.20 | 0.1878 |
| 0 | 6958 | 28 | 13 | 31.19 | 0.1879 |
| 14 | 9501400044 | 28 | 13 | 31.19 | 0.1889 |

Champion vs the x264 bar (33.48 dB): champion 31.62 dB @ 0.1828 bpp — quality gap 1.9 dB, bits gap 0.1828 vs 0.161 (x264 qp40 point).
