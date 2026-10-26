# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **1,156,640**
Candidate evaluations, all instruments (screens + oracle): **6,148,001,156,640**
Merge runs: 8.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 19 | 9501900031 | 28 | 8 | 24.78 | 0.4031 |
| 6 | 9500600040 | 28 | 9 | 24.68 | 0.3988 |
| 8 | 9500800032 | 28 | 1 | 24.70 | 0.4011 |
| 0 | 7133 | 28 | 9 | 24.82 | 0.4097 |
| 9 | 9500900007 | 28 | 8 | 24.72 | 0.4032 |
| 10 | 9501000002 | 28 | 4 | 24.71 | 0.4027 |
| 12 | 9501200017 | 28 | 9 | 24.80 | 0.4093 |
| 17 | 170007045 | 28 | 8 | 24.78 | 0.4085 |
| 3 | 9500300017 | 28 | 2 | 24.74 | 0.4058 |
| 13 | 130006945 | 28 | 1 | 24.65 | 0.4000 |
| 18 | 180006792 | 28 | 8 | 24.86 | 0.4155 |
| 7 | 9500700017 | 28 | 8 | 24.72 | 0.4079 |
| 2 | 9500200041 | 28 | 8 | 24.71 | 0.4099 |
| 4 | 9500400032 | 28 | 2 | 24.66 | 0.4071 |
| 1 | 9500100021 | 28 | 8 | 24.87 | 0.4223 |
| 5 | 9500500027 | 28 | 2 | 24.69 | 0.4135 |
| 15 | 9501500002 | 28 | 10 | 24.86 | 0.4343 |
| 11 | 110007030 | 28 | 11 | 24.81 | 0.4315 |
| 16 | 9501600037 | 28 | 10 | 23.99 | 0.4001 |
| 14 | 9501400020 | 28 | 11 | 24.20 | 0.4771 |

Champion vs the x264 bar (33.48 dB): champion 24.78 dB @ 0.4031 bpp — quality gap 8.7 dB, bits gap 0.4031 vs 0.161 (x264 qp40 point).
