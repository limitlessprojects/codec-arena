# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **2,203,300**
Candidate evaluations, all instruments (screens + oracle): **16,536,002,203,300**
Merge runs: 15.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 19 | 190006986 | 28 | 10 | 24.75 | 0.4014 |
| 5 | 9500500015 | 28 | 0 | 24.76 | 0.4026 |
| 13 | 9501300015 | 28 | 1 | 24.67 | 0.3977 |
| 11 | 9501100007 | 28 | 9 | 24.73 | 0.4030 |
| 7 | 9500700031 | 28 | 8 | 24.83 | 0.4104 |
| 0 | 7089 | 28 | 2 | 24.83 | 0.4105 |
| 6 | 9500600045 | 28 | 11 | 24.79 | 0.4078 |
| 3 | 9500300033 | 28 | 9 | 24.77 | 0.4073 |
| 8 | 80007021 | 28 | 1 | 24.72 | 0.4040 |
| 10 | 9501000044 | 28 | 1 | 24.72 | 0.4042 |
| 15 | 9501500044 | 28 | 2 | 24.85 | 0.4137 |
| 18 | 9501800015 | 28 | 2 | 24.74 | 0.4068 |
| 9 | 9500900029 | 28 | 2 | 24.80 | 0.4111 |
| 14 | 9501400015 | 28 | 8 | 24.77 | 0.4104 |
| 4 | 9500400042 | 28 | 1 | 24.78 | 0.4126 |
| 1 | 9500100015 | 28 | 1 | 24.66 | 0.4041 |
| 16 | 9501600044 | 28 | 11 | 24.78 | 0.4144 |
| 2 | 20006700 | 28 | 2 | 25.06 | 0.4345 |
| 12 | 120007080 | 28 | 2 | 24.65 | 0.4066 |
| 17 | 9501700031 | 28 | 8 | 24.77 | 0.4233 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
