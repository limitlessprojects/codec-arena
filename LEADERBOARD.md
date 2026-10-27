# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **3,250,840**
Candidate evaluations, all instruments (screens + oracle): **26,924,003,250,840**
Merge runs: 22.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 1 | 9500100008 | 28 | 8 | 27.06 | 0.1257 |
| 12 | 120007153 | 28 | 2 | 26.68 | 0.1000 |
| 6 | 9500600025 | 28 | 10 | 26.66 | 0.1022 |
| 8 | 9500800005 | 28 | 2 | 26.67 | 0.1057 |
| 3 | 30007129 | 28 | 1 | 26.38 | 0.0870 |
| 17 | 9501700017 | 28 | 2 | 26.34 | 0.0843 |
| 9 | 90006837 | 28 | 10 | 26.31 | 0.0828 |
| 14 | 9501400016 | 28 | 2 | 26.50 | 0.0973 |
| 11 | 9501100050 | 28 | 11 | 26.39 | 0.0898 |
| 16 | 9501600027 | 28 | 10 | 26.32 | 0.0852 |
| 10 | 9501000018 | 28 | 3 | 26.30 | 0.0840 |
| 5 | 50007003 | 28 | 8 | 26.35 | 0.0883 |
| 15 | 9501500031 | 28 | 1 | 26.53 | 0.1023 |
| 0 | 9500000007 | 28 | 10 | 26.41 | 0.0952 |
| 13 | 130007165 | 28 | 9 | 26.36 | 0.0920 |
| 4 | 40006873 | 28 | 11 | 26.34 | 0.0926 |
| 19 | 9501900043 | 28 | 2 | 26.32 | 0.0918 |
| 18 | 9501800050 | 28 | 2 | 26.32 | 0.0926 |
| 7 | 70006974 | 28 | 2 | 25.95 | 0.0927 |
| 2 | 9500200017 | 28 | 8 | 24.98 | 0.4694 |

Champion vs the x264 bar (33.48 dB): champion 29.67 dB @ 0.2113 bpp — quality gap 3.8 dB, bits gap 0.2113 vs 0.161 (x264 qp40 point).
