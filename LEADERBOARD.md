# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **1,754,640**
Candidate evaluations, all instruments (screens + oracle): **12,084,001,754,640**
Merge runs: 12.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 9 | 9500900032 | 28 | 1 | 24.89 | 0.4104 |
| 14 | 140006984 | 28 | 11 | 24.75 | 0.4005 |
| 8 | 9500800015 | 28 | 1 | 24.70 | 0.3979 |
| 5 | 9500500040 | 28 | 9 | 24.78 | 0.4064 |
| 12 | 9501200015 | 28 | 11 | 24.79 | 0.4086 |
| 13 | 9501300020 | 28 | 9 | 24.71 | 0.4032 |
| 19 | 9501900012 | 28 | 8 | 24.81 | 0.4104 |
| 15 | 9501500040 | 28 | 2 | 24.78 | 0.4090 |
| 17 | 9501700002 | 28 | 1 | 24.81 | 0.4118 |
| 2 | 20007147 | 28 | 8 | 24.78 | 0.4099 |
| 0 | 9500000019 | 28 | 1 | 24.68 | 0.4028 |
| 18 | 180007011 | 28 | 11 | 24.74 | 0.4090 |
| 16 | 160007157 | 28 | 8 | 24.68 | 0.4087 |
| 7 | 9500700015 | 28 | 9 | 24.59 | 0.4035 |
| 10 | 9501000022 | 28 | 10 | 24.74 | 0.4144 |
| 11 | 9501100024 | 28 | 8 | 24.92 | 0.4433 |
| 1 | 9500100041 | 28 | 1 | 24.84 | 0.4422 |
| 3 | 9500300036 | 28 | 4 | 24.70 | 0.4544 |
| 6 | 9500600040 | 28 | 8 | 25.69 | 0.5409 |
| 4 | 40006971 | 28 | 11 | 24.64 | 0.4725 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
