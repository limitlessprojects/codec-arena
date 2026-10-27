# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **2,352,880**
Candidate evaluations, all instruments (screens + oracle): **18,020,002,352,880**
Merge runs: 16.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 5 | 9500500003 | 28 | 11 | 24.82 | 0.4052 |
| 4 | 9500400019 | 28 | 9 | 24.84 | 0.4068 |
| 3 | 9500300027 | 28 | 11 | 24.70 | 0.3994 |
| 13 | 9501300032 | 28 | 10 | 24.77 | 0.4070 |
| 19 | 190007058 | 28 | 10 | 24.78 | 0.4091 |
| 14 | 9501400044 | 28 | 8 | 24.79 | 0.4100 |
| 9 | 9500900031 | 28 | 9 | 24.71 | 0.4046 |
| 1 | 9500100015 | 28 | 11 | 24.85 | 0.4162 |
| 2 | 20007098 | 28 | 1 | 24.67 | 0.4037 |
| 16 | 9501600002 | 28 | 10 | 24.82 | 0.4153 |
| 11 | 9501100027 | 28 | 2 | 24.68 | 0.4056 |
| 12 | 9501200002 | 28 | 10 | 24.71 | 0.4086 |
| 8 | 9500800004 | 28 | 2 | 24.70 | 0.4080 |
| 15 | 9501500044 | 28 | 8 | 24.69 | 0.4083 |
| 18 | 9501800019 | 28 | 8 | 24.87 | 0.4212 |
| 6 | 60006968 | 28 | 9 | 24.70 | 0.4103 |
| 0 | 9500000002 | 28 | 9 | 24.77 | 0.4197 |
| 7 | 9500700015 | 28 | 2 | 24.84 | 0.4500 |
| 17 | 9501700002 | 28 | 11 | 24.72 | 0.4771 |
| 10 | 100006947 | 28 | 2 | 25.43 | 0.5291 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
