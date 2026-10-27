# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **2,801,740**
Candidate evaluations, all instruments (screens + oracle): **22,472,002,801,740**
Merge runs: 19.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 7 | 9500700031 | 28 | 1 | 27.21 | 0.1082 |
| 5 | 50006964 | 28 | 10 | 27.21 | 0.1083 |
| 17 | 170007073 | 28 | 1 | 27.17 | 0.1062 |
| 14 | 9501400003 | 28 | 8 | 27.15 | 0.1063 |
| 15 | 9501500042 | 28 | 2 | 27.15 | 0.1092 |
| 6 | 9500600026 | 28 | 9 | 26.69 | 0.0994 |
| 8 | 9500800052 | 28 | 9 | 26.47 | 0.0905 |
| 4 | 9500400002 | 28 | 1 | 26.67 | 0.1051 |
| 11 | 9501100053 | 28 | 10 | 26.28 | 0.0779 |
| 1 | 9500100042 | 28 | 10 | 26.34 | 0.0858 |
| 9 | 9500900042 | 28 | 1 | 26.55 | 0.1013 |
| 13 | 9501300005 | 28 | 10 | 26.35 | 0.0873 |
| 16 | 9501600042 | 28 | 2 | 26.60 | 0.1056 |
| 2 | 9500200011 | 28 | 10 | 26.35 | 0.0879 |
| 12 | 9501200017 | 28 | 8 | 26.55 | 0.1026 |
| 18 | 9501800040 | 28 | 9 | 26.21 | 0.0788 |
| 10 | 9501000043 | 28 | 2 | 26.51 | 0.1008 |
| 3 | 30007072 | 28 | 8 | 26.23 | 0.0830 |
| 19 | 9501900024 | 28 | 11 | 26.18 | 0.0867 |
| 0 | 9500000028 | 28 | 8 | 26.24 | 0.0995 |

Champion vs the x264 bar (33.48 dB): champion 27.21 dB @ 0.1082 bpp — quality gap 6.3 dB, bits gap 0.1082 vs 0.161 (x264 qp40 point).
