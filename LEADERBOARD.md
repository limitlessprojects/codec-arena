# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **5,047,720**
Candidate evaluations, all instruments (screens + oracle): **44,732,005,047,720**
Merge runs: 34.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 17 | 170007151 | 28 | 12 | 31.69 | 0.1811 |
| 5 | 9500500038 | 28 | 15 | 31.69 | 0.1817 |
| 11 | 110006825 | 28 | 12 | 31.69 | 0.1810 |
| 0 | 7136 | 28 | 12 | 31.69 | 0.1810 |
| 6 | 60006968 | 28 | 12 | 31.69 | 0.1818 |
| 18 | 180006977 | 28 | 12 | 31.69 | 0.1813 |
| 12 | 9501200039 | 28 | 12 | 31.69 | 0.1813 |
| 13 | 130006811 | 28 | 16 | 31.69 | 0.1810 |
| 2 | 20007101 | 28 | 12 | 31.69 | 0.1814 |
| 10 | 100007124 | 28 | 15 | 31.69 | 0.1813 |
| 8 | 9500800044 | 28 | 13 | 31.69 | 0.1814 |
| 7 | 70007068 | 28 | 12 | 31.69 | 0.1813 |
| 15 | 9501500005 | 28 | 12 | 31.69 | 0.1812 |
| 9 | 9500900008 | 28 | 12 | 31.69 | 0.1813 |
| 3 | 9500300026 | 28 | 12 | 31.69 | 0.1817 |
| 1 | 10007015 | 28 | 12 | 31.68 | 0.1824 |
| 19 | 9501900043 | 28 | 13 | 31.69 | 0.1837 |
| 4 | 40007001 | 28 | 15 | 31.68 | 0.1830 |
| 14 | 9501400013 | 28 | 15 | 31.69 | 0.1810 |
| 16 | 9501600036 | 28 | 12 | 31.69 | 0.1813 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1811 bpp — quality gap 1.8 dB, bits gap 0.1811 vs 0.161 (x264 qp40 point).
