# Leaderboard

Every bot that ever lived in the arena is measured against the same
corpus, the same decoder, the same exchange rate. Champions graduate
to the Hall of Fame; the rest feed the lessons ledger.

Oracle evaluations (real encode+decode): **5,646,720**
Candidate evaluations, all instruments (screens + oracle): **50,668,005,646,720**
Merge runs: 38.  Oracle milestones: {"1e5": "run 2", "1e6": "run 7"}
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

| shard | bot | gen | tribe | psnr | bpp | ms-ssim |
|---|---|---|---|---|---|---|
| 16 | 9501600035 | 28 | 14 | 28.06 | 0.1458 | 0.8795 |
| 15 | 9501500035 | 28 | 16 | 28.33 | 0.1461 | 0.8793 |
| 10 | 9501000047 | 28 | 17 | 28.30 | 0.1706 | 0.8805 |
| 11 | 9501100018 | 28 | 14 | 28.44 | 0.1899 | 0.8815 |
| 17 | 9501700016 | 28 | 17 | 28.19 | 0.1471 | 0.8782 |
| 9 | 9500900028 | 28 | 13 | 27.81 | 0.1410 | 0.8705 |
| 5 | 50007148 | 28 | 12 | 28.27 | 0.1841 | 0.8806 |
| 6 | 9500600028 | 28 | 15 | 28.23 | 0.1708 | 0.8811 |
| 0 | 9500000035 | 28 | 17 | 28.25 | 0.1681 | 0.8799 |
| 14 | 140007066 | 28 | 13 | 27.43 | 0.1400 | 0.8698 |
| 19 | 9501900040 | 28 | 16 | 28.44 | 0.1863 | 0.8817 |
| 2 | 9500200036 | 28 | 15 | 28.23 | 0.1729 | 0.8807 |
| 12 | 9501200007 | 28 | 12 | 28.43 | 0.1890 | 0.8813 |
| 1 | 9500100035 | 28 | 12 | 28.46 | 0.1863 | 0.8810 |
| 13 | 9501300030 | 28 | 16 | 27.67 | 0.1379 | 0.8707 |
| 4 | 9500400018 | 28 | 12 | 28.52 | 0.1950 | 0.8817 |
| 8 | 9500800051 | 28 | 12 | 28.46 | 0.1866 | 0.8807 |
| 3 | 9500300014 | 28 | 17 | 27.63 | 0.1443 | 0.8700 |
| 7 | 70007113 | 28 | 15 | 26.99 | 0.1463 | 0.8564 |
| 18 | 9501800027 | 28 | 12 | 26.94 | 0.1455 | 0.8436 |

Champion vs the x264 bar (33.48 dB): champion 28.06 dB @ 0.1458 bpp — quality gap 5.4 dB, bits gap 0.1458 vs 0.161 (x264 qp40 point).

## The Pareto front (non-dominated champions ever)

| bot | quality | metric | bpp | enc_ms10 | dec_mops |
|---|---|---|---|---|---|
| 130007008 | 31.6900 | psnr | 0.1817 | 1783.2 | 13.59 |
| 9501400024 | 31.6900 | psnr | 0.1819 | 1782.6 | 13.6 |
| 9501500022 | 31.6900 | psnr | 0.1820 | 1402.4 | 13.59 |
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
