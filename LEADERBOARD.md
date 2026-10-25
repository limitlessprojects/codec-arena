# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **1,007,140**
Candidate evaluations, all instruments (screens + oracle): **4,664,001,007,140**
Merge runs: 7.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 12 | 9501200041 | 28 | 9 | 24.86 | 0.4080 |
| 0 | 9500000013 | 28 | 8 | 24.79 | 0.4033 |
| 17 | 170007096 | 28 | 1 | 24.77 | 0.4034 |
| 3 | 9500300029 | 28 | 9 | 24.85 | 0.4102 |
| 18 | 180006997 | 28 | 6 | 24.78 | 0.4056 |
| 16 | 9501600022 | 28 | 8 | 24.79 | 0.4077 |
| 11 | 9501100040 | 28 | 9 | 24.88 | 0.4149 |
| 19 | 9501900017 | 28 | 2 | 24.75 | 0.4063 |
| 1 | 9500100015 | 28 | 11 | 24.85 | 0.4140 |
| 13 | 9501300040 | 28 | 8 | 24.77 | 0.4086 |
| 14 | 9501400025 | 28 | 1 | 24.66 | 0.4041 |
| 10 | 9501000037 | 28 | 2 | 24.82 | 0.4156 |
| 4 | 40007051 | 28 | 11 | 24.78 | 0.4159 |
| 9 | 9500900040 | 28 | 3 | 24.84 | 0.4202 |
| 15 | 9501500031 | 28 | 2 | 24.85 | 0.4265 |
| 7 | 9500700022 | 28 | 2 | 24.80 | 0.4257 |
| 8 | 9500800031 | 28 | 2 | 24.93 | 0.4400 |
| 2 | 9500200028 | 28 | 11 | 24.91 | 0.4456 |
| 5 | 50006725 | 28 | 9 | 25.11 | 0.4966 |
| 6 | 60007037 | 28 | 9 | 24.62 | 0.4743 |

Champion vs the x264 bar (33.48 dB): champion 24.86 dB @ 0.4080 bpp — quality gap 8.6 dB, bits gap 0.4080 vs 0.161 (x264 qp40 point).
