# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **3,999,540**
Candidate evaluations, all instruments (screens + oracle): **34,344,003,999,540**
Merge runs: 27.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 1 | 10007134 | 28 | 15 | 31.69 | 0.1812 |
| 16 | 160006967 | 28 | 13 | 31.68 | 0.1818 |
| 0 | 7124 | 28 | 12 | 31.68 | 0.1823 |
| 12 | 9501200040 | 28 | 12 | 31.68 | 0.1823 |
| 8 | 80007049 | 28 | 12 | 31.68 | 0.1826 |
| 4 | 9500400007 | 28 | 12 | 31.68 | 0.1830 |
| 15 | 9501500022 | 28 | 13 | 31.68 | 0.1832 |
| 13 | 9501300044 | 28 | 12 | 31.67 | 0.1825 |
| 19 | 190006527 | 28 | 14 | 31.67 | 0.1826 |
| 10 | 9501000037 | 28 | 13 | 31.67 | 0.1827 |
| 6 | 60006982 | 28 | 13 | 31.67 | 0.1828 |
| 9 | 9500900019 | 28 | 12 | 31.67 | 0.1828 |
| 17 | 9501700039 | 28 | 12 | 31.67 | 0.1829 |
| 18 | 180007046 | 28 | 12 | 31.67 | 0.1829 |
| 7 | 9500700004 | 28 | 12 | 31.67 | 0.1830 |
| 11 | 9501100027 | 28 | 13 | 31.67 | 0.1832 |
| 2 | 20006750 | 28 | 13 | 31.67 | 0.1833 |
| 3 | 9500300029 | 28 | 12 | 31.67 | 0.1833 |
| 5 | 9500500005 | 28 | 12 | 31.66 | 0.1837 |
| 14 | 140006948 | 28 | 12 | 31.65 | 0.1855 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1812 bpp — quality gap 1.8 dB, bits gap 0.1812 vs 0.161 (x264 qp40 point).
