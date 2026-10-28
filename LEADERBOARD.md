# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **4,448,760**
Candidate evaluations, all instruments (screens + oracle): **38,796,004,448,760**
Merge runs: 30.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 5 | 9500500028 | 28 | 15 | 31.69 | 0.1810 |
| 12 | 9501200019 | 28 | 14 | 31.69 | 0.1811 |
| 3 | 9500300005 | 28 | 12 | 31.69 | 0.1811 |
| 13 | 130007081 | 28 | 16 | 31.69 | 0.1812 |
| 7 | 70006982 | 28 | 12 | 31.69 | 0.1812 |
| 10 | 100007079 | 28 | 14 | 31.69 | 0.1813 |
| 1 | 10007090 | 28 | 13 | 31.69 | 0.1814 |
| 16 | 9501600002 | 28 | 14 | 31.69 | 0.1814 |
| 0 | 9500000017 | 28 | 15 | 31.68 | 0.1808 |
| 15 | 150007130 | 28 | 13 | 31.69 | 0.1816 |
| 8 | 9500800039 | 28 | 12 | 31.69 | 0.1816 |
| 14 | 140007051 | 28 | 14 | 31.69 | 0.1819 |
| 18 | 180007081 | 28 | 13 | 31.69 | 0.1819 |
| 6 | 9500600020 | 28 | 12 | 31.68 | 0.1816 |
| 4 | 40007112 | 28 | 14 | 31.68 | 0.1819 |
| 9 | 90007040 | 28 | 13 | 31.68 | 0.1819 |
| 19 | 190007165 | 28 | 12 | 31.68 | 0.1822 |
| 17 | 9501700012 | 28 | 12 | 31.68 | 0.1823 |
| 11 | 110007133 | 28 | 14 | 31.68 | 0.1826 |
| 2 | 9500200052 | 28 | 12 | 31.67 | 0.1837 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1810 bpp — quality gap 1.8 dB, bits gap 0.1810 vs 0.161 (x264 qp40 point).
