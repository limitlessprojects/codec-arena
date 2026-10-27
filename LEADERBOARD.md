# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **3,400,580**
Candidate evaluations, all instruments (screens + oracle): **28,408,003,400,580**
Merge runs: 23.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 3 | 9500300019 | 28 | 12 | 31.54 | 0.1925 |
| 4 | 9500400015 | 28 | 13 | 31.57 | 0.1983 |
| 10 | 100006999 | 28 | 14 | 31.55 | 0.1983 |
| 19 | 190006974 | 28 | 15 | 31.59 | 0.2017 |
| 8 | 9500800031 | 28 | 12 | 31.51 | 0.1995 |
| 6 | 9500600011 | 28 | 16 | 31.57 | 0.2050 |
| 16 | 9501600026 | 28 | 15 | 31.45 | 0.1996 |
| 13 | 9501300015 | 28 | 17 | 31.54 | 0.2062 |
| 2 | 9500200052 | 28 | 12 | 31.52 | 0.2055 |
| 15 | 9501500015 | 28 | 12 | 31.55 | 0.2090 |
| 9 | 9500900019 | 28 | 15 | 31.57 | 0.2110 |
| 7 | 9500700015 | 28 | 14 | 31.54 | 0.2129 |
| 18 | 9501800019 | 28 | 13 | 31.49 | 0.2103 |
| 0 | 9500000010 | 28 | 12 | 31.51 | 0.2121 |
| 5 | 9500500029 | 28 | 14 | 31.50 | 0.2130 |
| 14 | 9501400015 | 28 | 14 | 31.48 | 0.2131 |
| 11 | 9501100015 | 28 | 16 | 31.40 | 0.2076 |
| 1 | 9500100019 | 28 | 12 | 31.40 | 0.2112 |
| 17 | 9501700052 | 28 | 12 | 31.40 | 0.2118 |
| 12 | 120007015 | 28 | 12 | 31.48 | 0.2197 |

Champion vs the x264 bar (33.48 dB): champion 31.54 dB @ 0.1925 bpp — quality gap 1.9 dB, bits gap 0.1925 vs 0.161 (x264 qp40 point).
