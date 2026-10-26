# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **2,053,720**
Candidate evaluations, all instruments (screens + oracle): **15,052,002,053,720**
Merge runs: 14.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 9 | 9500900003 | 28 | 9 | 24.71 | 0.3993 |
| 19 | 9501900031 | 28 | 2 | 24.77 | 0.4045 |
| 0 | 7140 | 28 | 2 | 24.79 | 0.4062 |
| 5 | 9500500045 | 28 | 11 | 24.81 | 0.4081 |
| 15 | 9501500045 | 28 | 2 | 24.77 | 0.4080 |
| 6 | 9500600002 | 28 | 2 | 24.70 | 0.4032 |
| 14 | 9501400037 | 28 | 2 | 24.74 | 0.4072 |
| 17 | 9501700024 | 28 | 2 | 24.71 | 0.4061 |
| 12 | 9501200019 | 28 | 2 | 24.70 | 0.4055 |
| 10 | 9501000018 | 28 | 8 | 24.62 | 0.4015 |
| 4 | 9500400027 | 28 | 3 | 24.86 | 0.4205 |
| 7 | 70006978 | 28 | 1 | 24.79 | 0.4163 |
| 11 | 9501100044 | 28 | 2 | 24.85 | 0.4207 |
| 18 | 9501800003 | 28 | 1 | 24.87 | 0.4273 |
| 16 | 160007124 | 28 | 8 | 24.88 | 0.4303 |
| 13 | 9501300044 | 28 | 9 | 24.75 | 0.4241 |
| 3 | 9500300045 | 28 | 9 | 24.80 | 0.4313 |
| 2 | 9500200022 | 28 | 2 | 24.80 | 0.4414 |
| 1 | 9500100044 | 28 | 8 | 24.73 | 0.4580 |
| 8 | 9500800020 | 28 | 8 | 24.10 | 0.4790 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
