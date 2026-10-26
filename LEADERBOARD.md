# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **1,306,140**
Candidate evaluations, all instruments (screens + oracle): **7,632,001,306,140**
Merge runs: 9.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 14 | 9501400041 | 28 | 8 | 24.85 | 0.4057 |
| 7 | 70007002 | 28 | 2 | 24.81 | 0.4048 |
| 0 | 6990 | 28 | 2 | 24.79 | 0.4051 |
| 16 | 9501600032 | 28 | 8 | 24.86 | 0.4102 |
| 1 | 9500100019 | 28 | 2 | 24.79 | 0.4052 |
| 8 | 9500800032 | 28 | 8 | 24.83 | 0.4107 |
| 6 | 60006841 | 28 | 9 | 24.82 | 0.4127 |
| 2 | 9500200043 | 28 | 9 | 24.65 | 0.4026 |
| 15 | 150007093 | 28 | 11 | 24.91 | 0.4212 |
| 4 | 9500400036 | 28 | 2 | 24.74 | 0.4097 |
| 17 | 9501700041 | 28 | 10 | 24.88 | 0.4202 |
| 9 | 90006817 | 28 | 9 | 24.81 | 0.4175 |
| 10 | 100007115 | 28 | 10 | 24.83 | 0.4197 |
| 11 | 110007153 | 28 | 11 | 24.75 | 0.4150 |
| 18 | 9501800032 | 28 | 8 | 24.61 | 0.4062 |
| 3 | 9500300019 | 28 | 2 | 24.65 | 0.4134 |
| 13 | 9501300017 | 28 | 5 | 24.78 | 0.4257 |
| 12 | 9501200015 | 28 | 8 | 24.84 | 0.4478 |
| 19 | 9501900004 | 28 | 8 | 24.72 | 0.4738 |
| 5 | 9500500024 | 28 | 8 | 23.92 | 0.4292 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
