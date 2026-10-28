# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **4,149,280**
Candidate evaluations, all instruments (screens + oracle): **35,828,004,149,280**
Merge runs: 28.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 14 | 140006316 | 28 | 12 | 31.68 | 0.1818 |
| 12 | 9501200020 | 28 | 12 | 31.68 | 0.1822 |
| 5 | 50007043 | 28 | 12 | 31.68 | 0.1824 |
| 15 | 150006798 | 28 | 12 | 31.68 | 0.1827 |
| 7 | 9500700033 | 28 | 12 | 31.67 | 0.1823 |
| 11 | 110007033 | 28 | 12 | 31.68 | 0.1831 |
| 2 | 9500200027 | 28 | 12 | 31.68 | 0.1831 |
| 18 | 9501800041 | 28 | 13 | 31.67 | 0.1825 |
| 17 | 9501700002 | 28 | 15 | 31.67 | 0.1827 |
| 13 | 130006976 | 28 | 12 | 31.67 | 0.1829 |
| 4 | 40006861 | 28 | 12 | 31.67 | 0.1829 |
| 8 | 9500800013 | 28 | 12 | 31.67 | 0.1830 |
| 1 | 10006742 | 28 | 12 | 31.67 | 0.1832 |
| 6 | 60006972 | 28 | 14 | 31.67 | 0.1833 |
| 9 | 9500900019 | 28 | 14 | 31.67 | 0.1833 |
| 10 | 100006990 | 28 | 12 | 31.68 | 0.1846 |
| 19 | 190006988 | 28 | 12 | 31.68 | 0.1848 |
| 0 | 9500000042 | 28 | 12 | 31.66 | 0.1835 |
| 3 | 30007159 | 28 | 12 | 31.67 | 0.1843 |
| 16 | 9501600008 | 28 | 12 | 31.65 | 0.1852 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1812 bpp — quality gap 1.8 dB, bits gap 0.1812 vs 0.161 (x264 qp40 point).
