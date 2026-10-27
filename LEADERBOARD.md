# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **2,502,460**
Candidate evaluations, all instruments (screens + oracle): **19,504,002,502,460**
Merge runs: 17.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 0 | 9500000045 | 28 | 8 | 24.83 | 0.4072 |
| 1 | 9500100019 | 28 | 8 | 24.79 | 0.4046 |
| 12 | 9501200015 | 28 | 8 | 24.76 | 0.4030 |
| 13 | 130006513 | 28 | 2 | 24.76 | 0.4046 |
| 8 | 9500800015 | 28 | 1 | 24.79 | 0.4073 |
| 3 | 30007004 | 28 | 9 | 24.79 | 0.4081 |
| 10 | 9501000011 | 28 | 10 | 24.77 | 0.4067 |
| 16 | 9501600022 | 28 | 10 | 24.76 | 0.4070 |
| 11 | 110006469 | 28 | 2 | 24.76 | 0.4071 |
| 2 | 9500200033 | 28 | 8 | 24.88 | 0.4159 |
| 4 | 9500400034 | 28 | 11 | 24.71 | 0.4040 |
| 15 | 9501500019 | 28 | 8 | 24.83 | 0.4136 |
| 5 | 9500500017 | 28 | 1 | 24.76 | 0.4105 |
| 7 | 9500700038 | 28 | 1 | 24.67 | 0.4045 |
| 19 | 9501900025 | 28 | 2 | 24.85 | 0.4186 |
| 18 | 9501800015 | 28 | 6 | 24.86 | 0.4222 |
| 17 | 9501700002 | 28 | 2 | 24.66 | 0.4091 |
| 14 | 9501400007 | 28 | 8 | 24.90 | 0.4275 |
| 9 | 9500900028 | 28 | 11 | 24.84 | 0.4261 |
| 6 | 9500600011 | 28 | 10 | 24.49 | 0.4550 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
