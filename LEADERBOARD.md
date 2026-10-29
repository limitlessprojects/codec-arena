# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **5,946,280**
Candidate evaluations, all instruments (screens + oracle): **53,636,005,946,280**
Merge runs: 40.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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
| 8 | 80007015 | 28 | 12 | 25.02 | 0.2053 | 0.8424 |
| 2 | 9500200027 | 28 | 12 | 24.84 | 0.2052 | 0.8383 |
| 19 | 190007015 | 28 | 12 | 24.98 | 0.2093 | 0.8428 |
| 3 | 9500300040 | 28 | 12 | 24.88 | 0.2061 | 0.8389 |
| 13 | 130006456 | 28 | 12 | 24.98 | 0.2065 | 0.8419 |
| 10 | 9501000049 | 28 | 13 | 24.74 | 0.2049 | 0.8341 |
| 4 | 9500400041 | 28 | 12 | 24.91 | 0.2052 | 0.8394 |
| 18 | 9501800024 | 28 | 12 | 24.76 | 0.2037 | 0.8341 |
| 15 | 9501500049 | 28 | 12 | 24.71 | 0.2020 | 0.8336 |
| 6 | 9500600038 | 28 | 13 | 24.89 | 0.2029 | 0.8390 |
| 11 | 9501100044 | 28 | 12 | 24.86 | 0.2081 | 0.8388 |
| 17 | 9501700025 | 28 | 12 | 24.85 | 0.2089 | 0.8386 |
| 1 | 9500100037 | 28 | 12 | 24.85 | 0.2064 | 0.8384 |
| 16 | 9501600031 | 28 | 13 | 24.77 | 0.2050 | 0.8383 |
| 0 | 7004 | 28 | 12 | 24.86 | 0.2054 | 0.8384 |
| 14 | 9501400020 | 28 | 12 | 24.83 | 0.2050 | 0.8392 |
| 9 | 9500900007 | 28 | 12 | 24.84 | 0.2023 | 0.8389 |
| 5 | 9500500015 | 28 | 12 | 24.87 | 0.2072 | 0.8387 |
| 12 | 9501200043 | 28 | 12 | 24.96 | 0.2067 | 0.8424 |
| 7 | 9500700040 | 28 | 14 | 24.82 | 0.2020 | 0.8390 |

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
