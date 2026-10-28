# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **4,299,020**
Candidate evaluations, all instruments (screens + oracle): **37,312,004,299,020**
Merge runs: 29.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 11 | 110006953 | 28 | 12 | 31.69 | 0.1811 |
| 4 | 9500400011 | 28 | 12 | 31.69 | 0.1812 |
| 0 | 9500000027 | 28 | 12 | 31.69 | 0.1813 |
| 2 | 20007007 | 28 | 14 | 31.69 | 0.1813 |
| 7 | 70007164 | 28 | 17 | 31.69 | 0.1813 |
| 1 | 9500100052 | 28 | 12 | 31.69 | 0.1814 |
| 19 | 9501900027 | 28 | 15 | 31.69 | 0.1814 |
| 8 | 80007164 | 28 | 12 | 31.69 | 0.1814 |
| 3 | 30007018 | 28 | 15 | 31.69 | 0.1815 |
| 5 | 9500500020 | 28 | 12 | 31.69 | 0.1816 |
| 6 | 60006477 | 28 | 14 | 31.69 | 0.1817 |
| 9 | 90006814 | 28 | 13 | 31.69 | 0.1818 |
| 18 | 180007105 | 28 | 12 | 31.68 | 0.1817 |
| 10 | 100006977 | 28 | 13 | 31.68 | 0.1818 |
| 14 | 9501400002 | 28 | 12 | 31.68 | 0.1820 |
| 13 | 130006966 | 28 | 12 | 31.68 | 0.1823 |
| 15 | 9501500033 | 28 | 12 | 31.68 | 0.1823 |
| 17 | 170007133 | 28 | 12 | 31.68 | 0.1825 |
| 16 | 160006557 | 28 | 12 | 31.68 | 0.1826 |
| 12 | 120007080 | 28 | 17 | 31.70 | 0.1844 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1811 bpp — quality gap 1.8 dB, bits gap 0.1811 vs 0.161 (x264 qp40 point).
