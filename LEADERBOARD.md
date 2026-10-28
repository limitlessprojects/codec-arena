# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **4,897,980**
Candidate evaluations, all instruments (screens + oracle): **43,248,004,897,980**
Merge runs: 33.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 4 | 9500400015 | 28 | 12 | 31.67 | 0.1828 |
| 15 | 150007068 | 28 | 12 | 31.69 | 0.1811 |
| 1 | 10007095 | 28 | 17 | 31.69 | 0.1813 |
| 3 | 9500300007 | 28 | 12 | 31.69 | 0.1812 |
| 11 | 110007125 | 28 | 14 | 31.69 | 0.1810 |
| 5 | 9500500022 | 28 | 12 | 31.69 | 0.1812 |
| 18 | 9501800029 | 28 | 12 | 31.69 | 0.1812 |
| 7 | 9500700040 | 28 | 12 | 31.69 | 0.1813 |
| 13 | 9501300008 | 28 | 12 | 31.69 | 0.1813 |
| 2 | 20006908 | 28 | 12 | 31.69 | 0.1813 |
| 19 | 190007092 | 28 | 12 | 31.69 | 0.1812 |
| 9 | 90007088 | 28 | 12 | 31.69 | 0.1810 |
| 17 | 9501700040 | 28 | 13 | 31.69 | 0.1822 |
| 6 | 60006965 | 28 | 17 | 31.69 | 0.1813 |
| 8 | 9500800044 | 28 | 16 | 31.69 | 0.1813 |
| 16 | 160006862 | 28 | 12 | 31.69 | 0.1810 |
| 12 | 9501200005 | 28 | 12 | 31.69 | 0.1810 |
| 14 | 140007019 | 28 | 15 | 31.69 | 0.1812 |
| 10 | 9501000038 | 28 | 14 | 31.69 | 0.1810 |
| 0 | 9500000019 | 28 | 14 | 31.69 | 0.1813 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1811 bpp — quality gap 1.8 dB, bits gap 0.1811 vs 0.161 (x264 qp40 point).
