# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **1,904,140**
Candidate evaluations, all instruments (screens + oracle): **13,568,001,904,140**
Merge runs: 13.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 12 | 9501200015 | 28 | 8 | 24.77 | 0.4007 |
| 16 | 9501600017 | 28 | 4 | 24.77 | 0.4022 |
| 2 | 9500200019 | 28 | 1 | 24.76 | 0.4018 |
| 14 | 9501400032 | 28 | 11 | 24.79 | 0.4041 |
| 11 | 9501100015 | 28 | 1 | 24.78 | 0.4039 |
| 13 | 9501300027 | 28 | 9 | 24.79 | 0.4059 |
| 9 | 9500900002 | 28 | 2 | 24.77 | 0.4045 |
| 8 | 9500800015 | 28 | 10 | 24.77 | 0.4052 |
| 18 | 9501800002 | 28 | 9 | 24.69 | 0.3995 |
| 10 | 9501000019 | 28 | 3 | 24.75 | 0.4041 |
| 3 | 9500300015 | 28 | 9 | 24.79 | 0.4071 |
| 15 | 150006040 | 28 | 9 | 24.77 | 0.4065 |
| 17 | 170006995 | 28 | 8 | 24.73 | 0.4050 |
| 6 | 9500600017 | 28 | 8 | 24.77 | 0.4103 |
| 5 | 9500500032 | 28 | 9 | 24.72 | 0.4090 |
| 1 | 9500100017 | 28 | 8 | 24.67 | 0.4056 |
| 4 | 9500400041 | 28 | 2 | 24.65 | 0.4108 |
| 7 | 9500700017 | 28 | 2 | 24.70 | 0.4190 |
| 0 | 9500000006 | 28 | 9 | 24.71 | 0.4232 |
| 19 | 9501900019 | 28 | 9 | 24.72 | 0.4260 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
