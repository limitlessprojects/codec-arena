# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **857,640**
Candidate evaluations, all instruments (screens + oracle): **3,180,000,857,640**
Merge runs: 6.  Oracle milestones: {"1e5": "run 2"}
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
| 2 | 9500200011 | 20 | 9 | 24.79 | 0.4069 |
| 11 | 9501100040 | 20 | 8 | 24.79 | 0.4098 |
| 4 | 9500400035 | 20 | 8 | 24.80 | 0.4115 |
| 19 | 9501900032 | 20 | 9 | 24.86 | 0.4173 |
| 17 | 9501700005 | 20 | 8 | 24.72 | 0.4106 |
| 14 | 140004965 | 20 | 9 | 24.67 | 0.4075 |
| 6 | 9500600017 | 20 | 5 | 24.86 | 0.4220 |
| 13 | 9501300015 | 20 | 1 | 24.70 | 0.4119 |
| 10 | 100004974 | 20 | 8 | 24.89 | 0.4271 |
| 1 | 9500100031 | 20 | 2 | 24.77 | 0.4202 |
| 9 | 9500900041 | 20 | 4 | 24.57 | 0.4119 |
| 0 | 9500000003 | 20 | 8 | 24.44 | 0.4045 |
| 3 | 9500300042 | 20 | 8 | 24.66 | 0.4239 |
| 5 | 9500500009 | 20 | 1 | 25.18 | 0.4631 |
| 15 | 9501500029 | 20 | 8 | 24.75 | 0.4364 |
| 8 | 9500800017 | 20 | 9 | 24.64 | 0.4318 |
| 7 | 9500700011 | 20 | 8 | 24.84 | 0.4470 |
| 18 | 9501800017 | 20 | 10 | 24.01 | 0.4135 |
| 16 | 9501600017 | 20 | 2 | 24.73 | 0.4806 |
| 12 | 9501200015 | 20 | 10 | 24.69 | 0.4806 |

Champion vs the x264 bar (33.48 dB): champion 24.79 dB @ 0.4069 bpp — quality gap 8.7 dB, bits gap 0.4069 vs 0.161 (x264 qp40 point).
