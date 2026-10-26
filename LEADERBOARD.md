# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **1,455,640**
Candidate evaluations, all instruments (screens + oracle): **9,116,001,455,640**
Merge runs: 10.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 2 | 9500200031 | 28 | 1 | 24.77 | 0.4009 |
| 1 | 10006730 | 28 | 9 | 24.74 | 0.3995 |
| 8 | 9500800019 | 28 | 2 | 24.80 | 0.4046 |
| 5 | 50007137 | 28 | 1 | 24.86 | 0.4094 |
| 9 | 90007125 | 28 | 10 | 24.79 | 0.4044 |
| 16 | 9501600023 | 28 | 1 | 24.78 | 0.4041 |
| 14 | 9501400002 | 28 | 1 | 24.89 | 0.4120 |
| 11 | 9501100031 | 28 | 8 | 24.79 | 0.4070 |
| 7 | 9500700036 | 28 | 10 | 24.72 | 0.4056 |
| 15 | 9501500027 | 28 | 8 | 25.46 | 0.4593 |
| 17 | 9501700033 | 28 | 10 | 24.74 | 0.4095 |
| 0 | 9500000032 | 28 | 9 | 24.82 | 0.4157 |
| 18 | 9501800011 | 28 | 2 | 24.98 | 0.4276 |
| 4 | 9500400040 | 28 | 11 | 24.71 | 0.4105 |
| 19 | 9501900040 | 28 | 9 | 24.60 | 0.4035 |
| 12 | 120006794 | 28 | 11 | 24.76 | 0.4170 |
| 13 | 9501300007 | 28 | 8 | 24.64 | 0.4112 |
| 3 | 9500300017 | 28 | 9 | 25.09 | 0.4467 |
| 10 | 9501000020 | 28 | 8 | 24.97 | 0.4731 |
| 6 | 9500600002 | 28 | 1 | 24.73 | 0.4727 |

Champion vs the x264 bar (33.48 dB): champion 24.77 dB @ 0.4009 bpp — quality gap 8.7 dB, bits gap 0.4009 vs 0.161 (x264 qp40 point).
