# Codec Arena

**A million bots fight over bits. The bits are real, the scoreboard is real,
and the bar is set by real codecs (x264, x265, SVT-AV1, libaom) on the same
corpus with the same instrument.**

This is an evolutionary codec lab: every bot is a 16-gene genome controlling a
real hybrid video codec (8×8 DCT → deadzone quantization → zigzag → integer
motion estimation → intra refresh → adaptive Q → two entropy modes), written
in **Zig**. Every generation, bots are evaluated by *encoding and decoding*
three deterministic clips and scored on one number:

```
score = PSNR − λ·bpp − complexity penalties        (λ = 14 dB per bit/pixel)
```

λ is the exchange rate between quality and bits — **this arena is literally a
market where genomes trade distortion for storage**. Evolution is the market
maker. Complexity penalties are the margin call: no genome wins by being
heavy.

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
src/*.zig         the codec + evaluator (Zig 0.17)
brain/evolve.py   reference brain: genetics, fitness, RD sweeps, lessons
brain/evolve.mojo Mojo brain (v0 kernel; python stays canonical)
tools/anchor.py   real-codec bar: x264/x265/SVT-AV1/libaom via ffmpeg
tools/merge_results.py   nightly merge → leaderboard, lessons, milestones
.github/workflows/arena.yml   20 parallel shards, nightly, self-reporting
```

## How a run works

1. `plan` computes the shard list (default **20 shards**).
2. Each shard: builds Zig in ReleaseFast, regenerates the corpus
   (deterministic — same bytes everywhere, sha-checked), evolves `--gens`
   generations of `--pop` bots against the zig oracle.
3. In parallel, the `anchor` job re-measures the real-codec bar with ffmpeg.
4. `merge` downloads every artifact, crowns a global champion, appends
   lessons, updates the lifetime-evaluation counter, commits state, and on
   schedule posts an issue report.

Nothing is ever hidden: every evaluation lands in `results_all.csv`, every
shard's lessons land in `LESSONS.md`, every milestone is logged in
`state/lifetime_evals.json`.

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

- **v0.1 (now)** — arena live, 20-shard CI, real-codec anchor table.
- **v0.2 (7d)** — champion beats the gen-0 seed pool by ≥10% fitness; Mojo
  differential green.
- **v0.3 (30d)** — champion ≥ x264 *ultrafast* at equal PSNR on this corpus.
- **v1.0 (90d)** — 1,000,000 lifetime evaluations, published RD curves, first
  transferable finding filed upstream (SVT-AV1 / x264 issue or PR).

Full plan in [`docs/PLAYBOOK.md`](docs/PLAYBOOK.md); scale math to a billion
evaluations in [`docs/SCALE.md`](docs/SCALE.md).

## Join the swarm (spore protocol)

Anyone can run a shard: `python3 brain/evolve.py --shard N --out-dir out`,
then PR the artifact directory. The merge validates format and folds your
island into the leaderboard. Your evals count toward the lifetime counter.
See `pop/README.md`.

## Receipts

- Encoder→bitstream→decoder are independent paths; PSNR is measured on
  **decoded** output only.
- The corpus is regenerated from code with fixed seeds — no benchmark drift,
  no dataset wrangling, sha-printed on every run.
- The anchor uses the same PSNR instrument for real codecs and for bots.

License: MIT.
