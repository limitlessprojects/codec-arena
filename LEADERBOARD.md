# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **4,748,240**
Candidate evaluations, all instruments (screens + oracle): **41,764,004,748,240**
Merge runs: 32.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 5 | 50006999 | 28 | 12 | 31.69 | 0.1810 |
| 7 | 70007116 | 28 | 14 | 31.69 | 0.1810 |
| 17 | 170007073 | 28 | 12 | 31.69 | 0.1811 |
| 9 | 90007162 | 28 | 14 | 31.69 | 0.1811 |
| 11 | 9501100043 | 28 | 12 | 31.69 | 0.1812 |
| 12 | 120007057 | 28 | 14 | 31.69 | 0.1812 |
| 16 | 160006866 | 28 | 12 | 31.69 | 0.1812 |
| 18 | 180007118 | 28 | 12 | 31.69 | 0.1812 |
| 2 | 20007049 | 28 | 15 | 31.69 | 0.1812 |
| 8 | 80007101 | 28 | 13 | 31.69 | 0.1812 |
| 1 | 10007063 | 28 | 12 | 31.69 | 0.1813 |
| 10 | 100007123 | 28 | 13 | 31.69 | 0.1813 |
| 13 | 130007001 | 28 | 12 | 31.69 | 0.1813 |
| 15 | 9501500049 | 28 | 15 | 31.69 | 0.1813 |
| 19 | 9501900005 | 28 | 12 | 31.69 | 0.1813 |
| 3 | 9500300030 | 28 | 13 | 31.69 | 0.1817 |
| 4 | 40007096 | 28 | 14 | 31.69 | 0.1817 |
| 0 | 7060 | 28 | 15 | 31.68 | 0.1813 |
| 14 | 9501400039 | 28 | 14 | 31.68 | 0.1825 |
| 6 | 60006814 | 28 | 12 | 31.67 | 0.1826 |

Champion vs the x264 bar (33.48 dB): champion 31.69 dB @ 0.1810 bpp — quality gap 1.8 dB, bits gap 0.1810 vs 0.161 (x264 qp40 point).
