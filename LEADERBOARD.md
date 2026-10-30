# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **6,395,620**
Candidate evaluations, all instruments (screens + oracle): **58,088,006,395,620**
Merge runs: 43.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
Search milestones: {"1e6": "run 4", "1e9": "run 4", "1e12": "run 4"}

The two counters never borrow from each other: a surrogate screen is
a candidate judged cheaply; only the oracle (real encode+decode) can
put a bot on this board.

## The bar (real codecs, same corpus, same PSNR instrument)

| codec | PSNR | bpp |
|---|---|---|
| x264 | 32.73 | 0.1833 |
| x265 | 31.67 | 0.1208 |
| svtav1 | 35.06 | 0.0915 |
| libaom | 34.3 | 0.1057 |

## Shard champions (this run)

| shard | bot | gen | tribe | psnr | bpp | ms-ssim |
|---|---|---|---|---|---|---|
| 6 | 60007093 | 28 | 12 | 25.22 | 0.2044 | 0.8458 |
| 12 | 9501200017 | 28 | 12 | 25.00 | 0.2060 | 0.8421 |
| 13 | 130006963 | 28 | 12 | 25.03 | 0.2036 | 0.8416 |
| 11 | 110007124 | 28 | 12 | 24.97 | 0.2073 | 0.8421 |
| 16 | 160006969 | 28 | 12 | 25.01 | 0.2077 | 0.8417 |
| 5 | 9500500039 | 28 | 12 | 24.85 | 0.2066 | 0.8387 |
| 1 | 9500100030 | 28 | 12 | 24.86 | 0.2058 | 0.8385 |
| 18 | 9501800042 | 28 | 13 | 24.85 | 0.2090 | 0.8388 |
| 0 | 9500000045 | 28 | 13 | 24.79 | 0.2023 | 0.8341 |
| 7 | 9500700006 | 28 | 12 | 24.75 | 0.2055 | 0.8343 |
| 8 | 9500800017 | 28 | 12 | 24.76 | 0.2047 | 0.8342 |
| 14 | 9501400049 | 28 | 12 | 24.76 | 0.2084 | 0.8344 |
| 9 | 9500900047 | 28 | 17 | 24.70 | 0.1996 | 0.8331 |
| 2 | 20007100 | 28 | 12 | 24.83 | 0.2023 | 0.8391 |
| 3 | 9500300040 | 28 | 14 | 24.86 | 0.2083 | 0.8388 |
| 17 | 170006962 | 28 | 12 | 24.84 | 0.2059 | 0.8382 |
| 4 | 9500400008 | 28 | 12 | 24.91 | 0.2089 | 0.8397 |
| 15 | 150007114 | 28 | 12 | 25.03 | 0.2061 | 0.8424 |
| 19 | 9501900004 | 28 | 14 | 24.96 | 0.2060 | 0.8423 |
| 10 | 9501000010 | 28 | 14 | 24.99 | 0.2070 | 0.8421 |

Champion vs the x264 bar (32.73 dB): champion 28.06 dB @ 0.1458 bpp — quality gap 4.7 dB, bits gap 0.1458 vs 0.161 (x264 qp40 point).

## The Pareto front (non-dominated champions ever)

| bot | quality | metric | bpp | enc_ms10 | dec_mops |
|---|---|---|---|---|---|
| 130007008 | 31.6900 | psnr | 0.1817 | 1783.2 | 13.59 |
| 9501400024 | 31.6900 | psnr | 0.1819 | 1782.6 | 13.6 |
| 40006997 | 31.6900 | psnr | 0.1810 | 958.6 | 13.62 |
| 110007001 | 31.6800 | psnr | 0.1816 | 1784.2 | 13.59 |
| 30006954 | 31.6800 | psnr | 0.1820 | 947.2 | 13.63 |
| 90006782 | 31.6800 | psnr | 0.1817 | 1404.9 | 13.59 |
| 7050 | 31.6800 | psnr | 0.1811 | 1011.4 | 13.6 |
| 160007165 | 31.6700 | psnr | 0.1831 | 962.3 | 13.6 |
| 9500400018 | 11.1859 | msssim_db | 0.1950 | 3498.2 | 18.89 |
| 9501100018 | 11.1519 | msssim_db | 0.1899 | 2687.2 | 18.79 |
| 9501900040 | 11.1494 | msssim_db | 0.1863 | 3318.6 | 18.82 |
| 9501200007 | 11.1210 | msssim_db | 0.1890 | 3313.1 | 18.71 |
| 9501000047 | 11.1031 | msssim_db | 0.1706 | 2656.7 | 18.68 |
| 9500600028 | 11.0869 | msssim_db | 0.1708 | 3268.7 | 18.49 |
| 9500000035 | 11.0861 | msssim_db | 0.1681 | 3289.0 | 18.74 |
| 9500100035 | 11.0777 | msssim_db | 0.1863 | 3279.9 | 18.44 |
| 9501600035 | 11.0708 | msssim_db | 0.1458 | 2643.2 | 18.82 |
| 9501300030 | 10.5859 | msssim_db | 0.1379 | 2682.5 | 17.87 |
| 9500900028 | 10.5801 | msssim_db | 0.1410 | 2224.1 | 18.93 |
| 140007066 | 10.4453 | msssim_db | 0.1400 | 2235.2 | 18.57 |
| 70007113 | 9.9068 | msssim_db | 0.1463 | 1714.6 | 16.06 |
| 9501800027 | 9.6378 | msssim_db | 0.1455 | 2144.3 | 16.97 |

A bot on this line is unbeatable on at least one trade-off axis —
the crowning rule uses the scalar fitness, this board honors the
specialists (faster-at-equal-quality, smaller-at-equal-quality).
## Gene credit (which genes selection rewards)

See [GENE_CREDIT.md](GENE_CREDIT.md) — mined from every recorded
generation's selection signals plus the champion lineage drift.
