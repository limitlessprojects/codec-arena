# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **3,849,800**
Candidate evaluations, all instruments (screens + oracle): **32,860,003,849,800**
Merge runs: 26.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 12 | 9501200024 | 28 | 13 | 31.68 | 0.1848 |
| 2 | 20007089 | 28 | 16 | 31.63 | 0.1820 |
| 4 | 9500400034 | 28 | 12 | 31.69 | 0.1864 |
| 7 | 9500700025 | 28 | 12 | 31.68 | 0.1857 |
| 3 | 9500300007 | 28 | 12 | 31.68 | 0.1861 |
| 13 | 9501300026 | 28 | 12 | 31.62 | 0.1824 |
| 16 | 9501600013 | 28 | 12 | 31.68 | 0.1868 |
| 6 | 60006805 | 28 | 13 | 31.62 | 0.1827 |
| 0 | 7095 | 28 | 12 | 31.62 | 0.1829 |
| 8 | 80007159 | 28 | 14 | 31.67 | 0.1865 |
| 14 | 140006722 | 28 | 14 | 31.62 | 0.1830 |
| 10 | 100006966 | 28 | 16 | 31.60 | 0.1819 |
| 11 | 9501100041 | 28 | 13 | 31.61 | 0.1828 |
| 18 | 9501800002 | 28 | 15 | 31.61 | 0.1828 |
| 1 | 10007032 | 28 | 12 | 31.60 | 0.1822 |
| 5 | 50007167 | 28 | 12 | 31.60 | 0.1824 |
| 19 | 9501900044 | 28 | 13 | 31.61 | 0.1834 |
| 9 | 90007068 | 28 | 12 | 31.59 | 0.1847 |
| 17 | 170007167 | 28 | 14 | 31.56 | 0.1895 |
| 15 | 9501500017 | 28 | 12 | 31.28 | 0.1775 |

Champion vs the x264 bar (33.48 dB): champion 31.67 dB @ 0.1826 bpp — quality gap 1.8 dB, bits gap 0.1826 vs 0.161 (x264 qp40 point).
