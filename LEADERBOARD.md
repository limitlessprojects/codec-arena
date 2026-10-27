# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **3,101,140**
Candidate evaluations, all instruments (screens + oracle): **25,440,003,101,140**
Merge runs: 21.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 8 | 9500800017 | 28 | 2 | 29.67 | 0.2113 |
| 3 | 9500300025 | 28 | 2 | 27.15 | 0.1036 |
| 10 | 9501000032 | 28 | 8 | 27.15 | 0.1040 |
| 1 | 10006991 | 28 | 2 | 27.19 | 0.1107 |
| 14 | 9501400022 | 28 | 10 | 26.84 | 0.0857 |
| 17 | 170007005 | 28 | 1 | 26.71 | 0.1020 |
| 12 | 9501200046 | 28 | 4 | 26.66 | 0.1027 |
| 6 | 60006987 | 28 | 9 | 26.25 | 0.0780 |
| 18 | 180007140 | 28 | 8 | 26.30 | 0.0832 |
| 16 | 9501600004 | 28 | 8 | 26.35 | 0.0868 |
| 11 | 9501100017 | 28 | 1 | 26.24 | 0.0806 |
| 15 | 9501500053 | 28 | 11 | 26.39 | 0.0926 |
| 5 | 9500500022 | 28 | 11 | 26.21 | 0.0801 |
| 9 | 90006449 | 28 | 1 | 26.55 | 0.1044 |
| 0 | 9500000027 | 28 | 11 | 26.59 | 0.1074 |
| 7 | 9500700017 | 28 | 8 | 26.32 | 0.0892 |
| 13 | 9501300002 | 28 | 2 | 26.30 | 0.0903 |
| 4 | 9500400017 | 28 | 1 | 26.33 | 0.0933 |
| 19 | 9501900005 | 28 | 9 | 26.49 | 0.1064 |
| 2 | 9500200019 | 28 | 7 | 26.02 | 0.0817 |

Champion vs the x264 bar (33.48 dB): champion 29.67 dB @ 0.2113 bpp — quality gap 3.8 dB, bits gap 0.2113 vs 0.161 (x264 qp40 point).
