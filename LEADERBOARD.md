# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **749,100**
Candidate evaluations, all instruments (screens + oracle): **2,120,000,749,100**
Merge runs: 5.  Oracle milestones: {"1e5": "run 2"}
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
| 16 | 9501600037 | 20 | 2 | 24.67 | 0.3988 |
| 8 | 80004981 | 20 | 8 | 24.75 | 0.4066 |
| 7 | 9500700040 | 20 | 10 | 24.66 | 0.4010 |
| 6 | 9500600031 | 20 | 1 | 24.75 | 0.4075 |
| 13 | 9501300019 | 20 | 2 | 24.66 | 0.4055 |
| 4 | 9500400031 | 20 | 8 | 24.72 | 0.4103 |
| 10 | 9501000030 | 20 | 9 | 24.68 | 0.4082 |
| 3 | 9500300002 | 20 | 1 | 24.68 | 0.4102 |
| 18 | 9501800022 | 20 | 8 | 24.69 | 0.4127 |
| 19 | 190005074 | 20 | 8 | 24.76 | 0.4222 |
| 2 | 9500200015 | 20 | 11 | 24.62 | 0.4155 |
| 15 | 9501500019 | 20 | 9 | 24.77 | 0.4381 |
| 0 | 9500000035 | 20 | 8 | 24.56 | 0.4355 |
| 11 | 9501100019 | 20 | 10 | 24.76 | 0.4560 |
| 12 | 9501200027 | 20 | 2 | 24.74 | 0.4784 |
| 14 | 9501400003 | 20 | 1 | 24.67 | 0.4749 |
| 1 | 9500100037 | 20 | 1 | 24.33 | 0.4516 |
| 9 | 9500900002 | 20 | 8 | 24.46 | 0.4630 |
| 17 | 9501700017 | 20 | 2 | 23.74 | 0.4180 |
| 5 | 9500500020 | 20 | 2 | 23.60 | 0.4372 |

Champion vs the x264 bar (33.48 dB): champion 24.67 dB @ 0.3988 bpp — quality gap 8.8 dB, bits gap 0.3988 vs 0.161 (x264 qp40 point).
