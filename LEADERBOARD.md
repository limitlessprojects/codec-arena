# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **4,598,500**
Candidate evaluations, all instruments (screens + oracle): **40,280,004,598,500**
Merge runs: 31.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 4 | 9500400020 | 28 | 14 | 31.69 | 0.1811 |
| 0 | 6990 | 28 | 14 | 31.69 | 0.1812 |
| 11 | 110006968 | 28 | 14 | 31.69 | 0.1812 |
| 5 | 50007162 | 28 | 13 | 31.69 | 0.1813 |
| 10 | 100006786 | 28 | 12 | 31.69 | 0.1814 |
| 12 | 120006944 | 28 | 12 | 31.69 | 0.1814 |
| 14 | 140007023 | 28 | 14 | 31.69 | 0.1814 |
| 8 | 80006988 | 28 | 13 | 31.69 | 0.1814 |
| 6 | 9500600007 | 28 | 15 | 31.69 | 0.1815 |
| 7 | 9500700019 | 28 | 13 | 31.69 | 0.1815 |
| 1 | 9500100037 | 28 | 12 | 31.69 | 0.1817 |
| 17 | 9501700008 | 28 | 13 | 31.69 | 0.1817 |
| 16 | 9501600008 | 28 | 12 | 31.68 | 0.1819 |
| 9 | 9500900026 | 28 | 15 | 31.68 | 0.1819 |
| 18 | 180007089 | 28 | 13 | 31.68 | 0.1820 |
| 15 | 9501500002 | 28 | 13 | 31.68 | 0.1821 |
| 2 | 9500200025 | 28 | 12 | 31.68 | 0.1822 |
| 19 | 190006973 | 28 | 12 | 31.68 | 0.1823 |
| 13 | 9501300002 | 28 | 14 | 31.67 | 0.1826 |
| 3 | 30006634 | 28 | 14 | 31.67 | 0.1831 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1810 bpp — quality gap 1.8 dB, bits gap 0.1810 vs 0.161 (x264 qp40 point).
