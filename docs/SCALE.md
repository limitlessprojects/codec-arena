# Scale: one million → one trillion

## What a "bot" is

Every evaluation of one genome against the full corpus = one bot lifecycle.
The lifetime counter counts those. Populations breed, so bots are produced
continuously; the counter is the honest size of the search we've done.

Since v0.2 there are two instruments and two counters:

- **oracle** — real encode+decode, ~0.26s/bot. Feeds `lifetime_evals`.
- **screen** — the surrogate funnel (quadratic response surface over the 16
  genes, fit on the oracle's own history), ~60ns/candidate in the Zig SIMD
  kernel. Feeds `search_evals` together with the oracle.

`search_evals` is the "how many bots have attacked the problem" number.
Neither counter borrows from the other, and only the oracle can put a bot on
the leaderboard.

## The measured engine (v0.2)

Calibrated on real hardware, not promised:

| quantity | measured |
|---|---|
| screen rate, sandbox, 4 threads | 17.2M candidates/s (58ns each) |
| screen rate, 4-vCPU hosted runner (est.) | 35–70M/s |
| screens per generation per shard | 2.65e9 (workflow default) |
| screens per shard per run (20 gens) | 5.3e10 |
| screens per run (20 shards) | **1.06e12** |
| screen wall time per shard | ~15–25 min |
| oracle wall time per shard (20×256 + rd) | ~20–25 min |
| total shard job | ~45–60 min (limit: 6h) |

The surrogate prior: 356,377 oracle-labeled genomes (the arena's entire life,
recovered by deterministic genetics replay — run 40113226256 pop 512 gens 40,
run 40136759247 pop 256 gens 20), quadratic ridge α=10,
Spearman ρ=0.70, R²=0.95 on held-out data. Per-island ridge refits toward the
prior every 4 generations adapt it to each shard's corner of the landscape.

## The nightly (v0.2)

- 20 shards × 20 gens × 256 pop oracle evals = **102,400 oracle evals/run**.
- 20 shards × 20 gens × 2.65e9 screens = **1.06e12 candidate evals/run**.
- So: **+1 trillion search evals every single night**, ~100K of them
  promoted-and-oracle-verified, for $0.

## Paths beyond 1e12

1. **More screens** (free): the screen dial is the multiplier. 1e13/night =
   2.65e10 screens/gen ≈ 3–5 min more per generation. Memory stays flat
   (streaming top-K). The wall is job time, not dollars.
2. **Spore swarm (community)**: anyone runs a shard on their own metal and
   PRs artifacts. 100 spore-runners ≈ 100× throughput → 1e14/night. The
   spore protocol (pop/README.md) makes results mergeable.
3. **Self-hosted runners**: 20 × 8-core boxes ≈ 80× hosted throughput.
4. **The honest ceiling**: the gene space is 16-dimensional continuous.
   Past ~1e9 *oracle* evals the binding constraint is not search volume but
   oracle realism (corpus size, resolution, codec fidelity). Past ~1e15
   screens the surrogate's 153-parameter shape becomes the bottleneck — the
   next upgrade is a bigger response surface (feature crosses with corpus
   statistics) or a tiny learned model. Say both plainly when the numbers
   approach.

## Cost accounting (the asymmetric bet, in numbers)

- Hosted path: $0. Duration bounded by our patience.
- Time cost: ~1h/week of maintenance once nightly is green.
- Expected value: every 2% saving found = one upstream PR + one paper section
  + one hiring receipt. Any one of the three repays the whole project.
