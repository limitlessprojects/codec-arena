# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **5,197,460**
Candidate evaluations, all instruments (screens + oracle): **46,216,005,197,460**
Merge runs: 35.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 4 | 9500400005 | 28 | 12 | 31.70 | 0.1842 |
| 10 | 100007045 | 28 | 13 | 31.68 | 0.1821 |
| 3 | 30007084 | 28 | 12 | 31.68 | 0.1815 |
| 5 | 50006953 | 28 | 13 | 31.68 | 0.1826 |
| 11 | 9501100015 | 28 | 13 | 31.68 | 0.1814 |
| 6 | 9500600022 | 28 | 12 | 31.69 | 0.1817 |
| 16 | 160007117 | 28 | 12 | 31.69 | 0.1818 |
| 19 | 9501900026 | 28 | 12 | 31.69 | 0.1815 |
| 13 | 9501300012 | 28 | 12 | 31.68 | 0.1817 |
| 7 | 9500700017 | 28 | 12 | 31.68 | 0.1820 |
| 12 | 120006848 | 28 | 12 | 31.69 | 0.1809 |
| 17 | 170007101 | 28 | 14 | 31.69 | 0.1809 |
| 1 | 10007160 | 28 | 17 | 31.68 | 0.1829 |
| 8 | 80006725 | 28 | 14 | 31.68 | 0.1822 |
| 18 | 9501800029 | 28 | 12 | 31.68 | 0.1815 |
| 14 | 140006960 | 28 | 14 | 31.68 | 0.1818 |
| 0 | 9500000011 | 28 | 12 | 31.68 | 0.1818 |
| 15 | 9501500022 | 28 | 16 | 31.68 | 0.1820 |
| 9 | 9500900038 | 28 | 14 | 31.70 | 0.1858 |
| 2 | 20007016 | 28 | 14 | 31.69 | 0.1832 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1811 bpp — quality gap 1.8 dB, bits gap 0.1811 vs 0.161 (x264 qp40 point).
