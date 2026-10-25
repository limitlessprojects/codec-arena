# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **640,560**
Candidate evaluations, all instruments (screens + oracle): **1,060,000,640,560**
Merge runs: 4.  Oracle milestones: {"1e5": "run 2"}
Search milestones: {"1e6": "run 4", "1e9": "run 4", "1e12": "run 4"}

The two counters never borrow from each other: a surrogate screen is
a candidate judged cheaply; only the oracle (real encode+decode) can
put a bot on this board.

## The bar (real codecs, same corpus, same PSNR instrument)

| codec | PSNR | bpp |
|---|---|---|
| x264 | 35.4 | 0.161 |
| x265 | 33.93 | 0.1098 |
| svtav1 | 37.55 | 0.0819 |
| libaom | 35.95 | 0.0977 |

## Shard champions (this run)

| shard | bot | gen | tribe | psnr | bpp |
|---|---|---|---|---|---|
| 2 | 20004964 | 20 | 8 | 26.44 | 0.6459 |
| 13 | 130005105 | 20 | 2 | 26.44 | 0.6461 |
| 16 | 160005045 | 20 | 11 | 26.09 | 0.6223 |
| 7 | 70004977 | 20 | 2 | 25.35 | 0.5698 |
| 14 | 140004857 | 20 | 10 | 26.09 | 0.6228 |
| 4 | 40005041 | 20 | 2 | 26.09 | 0.6228 |
| 11 | 110005026 | 20 | 11 | 25.03 | 0.5484 |
| 6 | 60004983 | 20 | 2 | 25.81 | 0.6048 |
| 1 | 10004438 | 20 | 2 | 25.18 | 0.5603 |
| 15 | 150005057 | 20 | 10 | 25.81 | 0.6065 |
| 18 | 180005064 | 20 | 2 | 24.89 | 0.5410 |
| 0 | 5109 | 20 | 10 | 25.81 | 0.6072 |
| 5 | 50005043 | 20 | 1 | 25.58 | 0.5923 |
| 17 | 170004734 | 20 | 2 | 25.99 | 0.6218 |
| 12 | 120005085 | 20 | 9 | 26.10 | 0.6297 |
| 9 | 90004912 | 20 | 2 | 25.56 | 0.5913 |
| 10 | 100005097 | 20 | 8 | 24.86 | 0.5421 |
| 3 | 30004902 | 20 | 4 | 26.08 | 0.6293 |
| 19 | 190004902 | 20 | 2 | 25.07 | 0.5582 |
| 8 | 80004954 | 20 | 2 | 26.13 | 0.6369 |

Champion vs the x264 bar (35.4 dB): champion 26.44 dB @ 0.6459 bpp — quality gap 9.0 dB, bits gap 0.6459 vs 0.161 (x264 qp40 point).
