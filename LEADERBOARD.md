# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **2,951,440**
Candidate evaluations, all instruments (screens + oracle): **23,956,002,951,440**
Merge runs: 20.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 7 | 9500700017 | 28 | 2 | 27.01 | 0.0918 |
| 5 | 50006822 | 28 | 8 | 27.13 | 0.1050 |
| 15 | 9501500019 | 28 | 9 | 26.99 | 0.0990 |
| 16 | 160007036 | 28 | 1 | 26.70 | 0.1029 |
| 11 | 9501100011 | 28 | 9 | 26.60 | 0.0985 |
| 6 | 9500600030 | 28 | 8 | 26.57 | 0.0984 |
| 3 | 9500300050 | 28 | 1 | 26.56 | 0.0978 |
| 12 | 9501200008 | 28 | 11 | 26.43 | 0.0901 |
| 14 | 9501400015 | 28 | 10 | 26.63 | 0.1048 |
| 2 | 9500200017 | 28 | 2 | 26.41 | 0.0897 |
| 0 | 9500000050 | 28 | 1 | 26.37 | 0.0875 |
| 1 | 9500100026 | 28 | 2 | 26.29 | 0.0824 |
| 10 | 9501000015 | 28 | 8 | 26.61 | 0.1057 |
| 13 | 9501300019 | 28 | 8 | 26.54 | 0.1029 |
| 4 | 40007123 | 28 | 1 | 26.25 | 0.0895 |
| 17 | 9501700013 | 28 | 2 | 26.22 | 0.0890 |
| 19 | 9501900017 | 28 | 1 | 26.21 | 0.0887 |
| 9 | 9500900019 | 28 | 2 | 26.05 | 0.0783 |
| 18 | 9501800006 | 28 | 9 | 26.12 | 0.0912 |
| 8 | 9500800028 | 28 | 2 | 24.82 | 0.4067 |

Champion vs the x264 bar (33.48 dB): champion 27.01 dB @ 0.0918 bpp — quality gap 6.5 dB, bits gap 0.0918 vs 0.161 (x264 qp40 point).
