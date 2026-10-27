# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **2,652,040**
Candidate evaluations, all instruments (screens + oracle): **20,988,002,652,040**
Merge runs: 18.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 15 | 9501500002 | 28 | 2 | 24.74 | 0.4030 |
| 2 | 9500200019 | 28 | 11 | 24.73 | 0.4034 |
| 9 | 9500900015 | 28 | 9 | 24.73 | 0.4034 |
| 3 | 9500300019 | 28 | 2 | 24.76 | 0.4060 |
| 14 | 9501400015 | 28 | 9 | 24.85 | 0.4142 |
| 18 | 9501800044 | 28 | 11 | 24.81 | 0.4117 |
| 7 | 9500700033 | 28 | 10 | 24.69 | 0.4036 |
| 1 | 10007154 | 28 | 8 | 24.77 | 0.4095 |
| 12 | 9501200037 | 28 | 1 | 24.59 | 0.3982 |
| 6 | 9500600006 | 28 | 11 | 24.65 | 0.4039 |
| 10 | 9501000036 | 28 | 2 | 24.63 | 0.4042 |
| 5 | 50007165 | 28 | 9 | 24.69 | 0.4100 |
| 8 | 9500800015 | 28 | 10 | 24.68 | 0.4098 |
| 0 | 6964 | 28 | 10 | 24.79 | 0.4179 |
| 4 | 40007054 | 28 | 2 | 24.55 | 0.4048 |
| 13 | 130006736 | 28 | 8 | 24.65 | 0.4120 |
| 16 | 9501600017 | 28 | 11 | 24.75 | 0.4205 |
| 11 | 9501100019 | 28 | 8 | 24.69 | 0.4168 |
| 17 | 9501700002 | 28 | 9 | 24.89 | 0.4883 |
| 19 | 9501900039 | 28 | 8 | 24.03 | 0.4333 |

Champion vs the x264 bar (33.48 dB): champion 24.85 dB @ 0.4057 bpp — quality gap 8.6 dB, bits gap 0.4057 vs 0.161 (x264 qp40 point).
