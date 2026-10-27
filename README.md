# Codec Arena

**A trillion candidate bots attack the problem. The bits are real, the
scoreboard is real, and the bar is set by real codecs (x264, x265, SVT-AV1,
libaom) on the same corpus with the same instrument.**

This is an evolutionary codec lab: every bot is a 27-gene genome controlling a
real hybrid video codec (8×8 DCT → deadzone quantization → zigzag → integer
motion estimation → intra refresh → adaptive Q → adaptive binary arithmetic
entropy coder → intra prediction incl. chroma-from-luma → in-loop deblocking +
CDEF-lite deringing), written in **Zig** and evolved against the AV1 lineup's
structural playbook. Every generation, bots are evaluated by *encoding and decoding*
three deterministic clips and scored on one number:

```
score = PSNR − λ·bpp − complexity penalties        (λ = 14 dB per bit/pixel)
```

λ is the exchange rate between quality and bits — **this arena is literally a
market where genomes trade distortion for storage**. Evolution is the market
maker. Complexity penalties are the margin call: no genome wins by being
heavy.

## The two instruments (the trillion protocol)

The oracle is honest and slow: a real encode+decode is ~0.26s, so a single
run can measure ~10^5 bots. Mass search at that rate would take centuries to
reach a trillion candidates — so the arena grew a second instrument:

- **oracle** (the referee): real encode→bitstream→decode→PSNR on the corpus.
  Slow. Unfakeable. Every oracle evaluation lands in `results_all.csv`.
- **screen** (the funnel): a quadratic response surface over the 16 genes,
  *fit on the oracle's own measurements* (356,377 of them so far — every
  evaluation the arena ever made, replayed and joined by deterministic
  genetics), scored in the Zig SIMD kernel at ~60ns per candidate.

Each generation, ~2.65 **billion** candidate genomes are synthesized per shard
(crossover of elites + annealed mutation + rare jumps + 1% random immigrants),
ranked by the surrogate, and only the top survivors are promoted into the
population — where they still have to earn their place from the **real
oracle**. The surrogate proposes; the oracle disposes.

Two counters, printed side by side, never borrowing from each other:

- `lifetime_evals` — oracle measurements (the scoreboard's currency)
- `search_evals` — every candidate any instrument ever scored (the search's
  true size — this is the million → billion → **trillion** number)

20 shards × 28 generations × 2.65e9 screens ≈ **1.5 × 10^12 candidates per
run, six runs a day** (cron every 4h, plus an hourly heartbeat that
re-dispatches if GitHub drops one) ≈ **8.9 × 10^12/day**, for zero dollars,
with every promoted bot verified by real pixels. A surrogate judgment is
cheap; a leaderboard seat is not.

## The bet (why this is asymmetric)

| | |
|---|---|
| **Downside, bounded** | CI minutes on a free public repo. Zero dollars, zero hardware, no GPU. |
| **Upside, open** | Even a **1% bitrate saving at equal PSNR** from an evolved genome is a publishable micro-result and a reusable finding. The arena itself — corpus, harness, anchor table, leaderboard — is durable infrastructure. |

We are not trying to beat VVC. We are trying to *measure* what a
systematically explored space of codec strategies can and cannot do, in
public, for the cost of electricity someone else already paid for. The
plateau is documented (see `docs/RESEARCH.md`): CLIC 2025 showed no
significant year-over-year gain; neural codecs carry 50–100× decode
complexity. The cheap, boring, honest frontier is exactly here.

## Architecture

```
corpus/           deterministic synthetic clips (pure python, checksummed)
src/*.zig         the codec + evaluator + SIMD screen kernel (Zig 0.17)
brain/evolve.py   reference brain: genetics, fitness, cascade, RD sweeps
brain/evolve.mojo Mojo brain (v0 kernel; python stays canonical)
state/surrogate.txt  the response surface, fit on every oracle eval ever made
state/surrogate_meta.json  training receipt (n, alpha, spearman, replay log)
tools/anchor.py   real-codec bar: x264/x265/SVT-AV1/libaom via ffmpeg
tools/merge_results.py   merge → leaderboard, lessons, milestones (race-safe push)
.github/workflows/arena.yml   20 parallel shards, 6×/day, self-reporting
.github/workflows/heartbeat.yml   hourly catch-up net: re-dispatches a dropped cron
```

## How a run works

1. `plan` computes the shard list (default **20 shards**) and the screen
   budget (default **2.65e9 screens per generation**).
2. Each shard: builds Zig in ReleaseFast (v3 SIMD), runs unit tests,
   regenerates the corpus (deterministic — same bytes everywhere,
   sha-checked), then evolves `--gens` generations of `--pop` bots: the
   oracle measures every bot; the screen kernel screens `--screens`
   candidates per generation and promotes the survivors; a numpy ridge
   refit adapts the surrogate to the island every 4 generations.
3. In parallel, the `anchor` job re-measures the real-codec bar with ffmpeg.
4. `merge` downloads every artifact, crowns a global champion, appends
   lessons, updates both counters, commits state, and on schedule posts an
   issue report.

Nothing is ever hidden: every oracle evaluation lands in `results_all.csv`,
every screen count lands in `screens_count.txt`, every shard's lessons land
in `LESSONS.md`, every milestone is logged in `state/lifetime_evals.json`.

## Honest box

- Our seed bots score **~18 dB at ~2 bpp**. The x264 bar on this corpus is
  **35.4 dB at 0.161 bpp**. That is the mountain. We publish the gap because
  that is the whole point of an arena: a scoreboard nobody trusts is worth
  nothing.
- Known codec realism: at integer quantization levels, float DCT coefficients
  round — so even "identity" quantization drifts across P-frames. Real codecs
  fight the same physics with in-loop filters and RD-optimized decisions. Our
  genomes must learn their own defenses (keyint, refresh, deadzone
  discipline). That fight *is* the experiment.
- The Mojo brain is v0 (toolchain + genetics kernel). The Python brain is the
  oracle of record until the differential test is green.

## The ladder

- **v0.1** — arena live, 20-shard CI, real-codec anchor table. ✓ (533K oracle evals)
- **v0.2 (now)** — the trillion protocol: surrogate screen cascade,
  1.5e12 candidate evaluations per run at a 6×/day cadence (~8.9e12/day),
  per-island refits, Mojo toolchain status receipt. ✓
- **v0.3 (7d)** — champion beats the gen-0 seed pool by ≥25% fitness;
  surrogate ablation (screens on/off) published as a lesson.
- **v0.4 (30d)** — champion ≥ x264 *ultrafast* at equal PSNR on this corpus.
- **v0.5 (shipped)** — the AV1-lineup rung: adaptive arithmetic entropy coder
  (g18), chroma-from-luma (g19), CDEF-lite (g20), SMOOTH/PAETH modes. Local
  measurement at the champion operating point: fit 19.17 → 24.10
  (docs/ROADMAP_V05.md).
- **v1.0 (90d)** — 10^7 oracle evaluations, published RD curves + landscape
  maps (fitness vs genes, from a trillion-candidate search), first
  transferable finding filed upstream (SVT-AV1 / x264 issue or PR).

Full plan in [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md); the scale math —
measured, not promised — lives in [`docs/SCALE.md`](docs/SCALE.md).

## Join the swarm (spore protocol)

Anyone can run a shard:

    python3 brain/evolve.py --shard 42 --gens 20 --pop 256 --screens 2650000000 --out-dir out/shard-42

(on older hardware drop `--screens` for the classic GA path, and build
without `-Dcpu=x86_64_v3`), then PR the artifact directory. The merge
validates format and folds your island into the leaderboard. Your oracle
evals count toward the lifetime counter, your screens toward the search
counter. See `pop/README.md`.

## Receipts

- Encoder→bitstream→decoder are independent paths; PSNR is measured on
  **decoded** output only.
- The corpus is regenerated from code with fixed seeds — no benchmark drift,
  no dataset wrangling, sha-printed on every run.
- The anchor uses the same PSNR instrument for real codecs and for bots.

License: MIT.
