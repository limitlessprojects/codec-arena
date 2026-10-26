# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **1,605,140**
Candidate evaluations, all instruments (screens + oracle): **10,600,001,605,140**
Merge runs: 11.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 7 | 9500700013 | 28 | 0 | 24.76 | 0.3997 |
| 8 | 9500800003 | 28 | 9 | 24.77 | 0.4019 |
| 14 | 9501400015 | 28 | 2 | 24.80 | 0.4053 |
| 13 | 9501300041 | 28 | 10 | 24.82 | 0.4072 |
| 6 | 9500600017 | 28 | 8 | 24.71 | 0.4007 |
| 0 | 9500000031 | 28 | 9 | 24.76 | 0.4045 |
| 3 | 9500300032 | 28 | 9 | 24.75 | 0.4048 |
| 18 | 9501800005 | 28 | 1 | 24.73 | 0.4034 |
| 17 | 170007116 | 28 | 8 | 24.78 | 0.4078 |
| 2 | 9500200032 | 28 | 8 | 24.89 | 0.4157 |
| 9 | 9500900019 | 28 | 3 | 24.84 | 0.4130 |
| 4 | 9500400013 | 28 | 1 | 24.75 | 0.4087 |
| 16 | 160006975 | 28 | 1 | 24.68 | 0.4060 |
| 5 | 50007162 | 28 | 1 | 24.86 | 0.4199 |
| 15 | 9501500031 | 28 | 9 | 24.60 | 0.4014 |
| 1 | 9500100007 | 28 | 8 | 24.69 | 0.4095 |
| 19 | 9501900019 | 28 | 2 | 24.67 | 0.4092 |
| 12 | 120007040 | 28 | 8 | 24.76 | 0.4169 |
| 11 | 110007162 | 28 | 2 | 24.63 | 0.4709 |
| 10 | 9501000034 | 28 | 11 | 24.79 | 0.5183 |

Champion vs the x264 bar (33.48 dB): champion 24.76 dB @ 0.3997 bpp — quality gap 8.7 dB, bits gap 0.3997 vs 0.161 (x264 qp40 point).
