# Scale: one million → one billion

## What a "bot" is

Every evaluation of one genome against the full corpus = one bot lifecycle.
The lifetime counter counts those. Populations breed, so bots are produced
continuously; the counter is the honest size of the search we've done.

## The default nightly (v0.1)

- 20 shards × 20 gens × 256 pop = **102,400 evals/run** (plus elites re-eval).
- Per-shard wall time ≈ 20 min on a 2-core hosted runner (256 × 20 × ~0.26s
  ≈ 22 min of oracle time, parallel with everything else).
- **1,000,000 lifetime evals ≈ 10 nightly runs ≈ 10 days.** The first
  milestone lands inside two weeks of launch.

## Dials (cheapest first)

| dial | effect | cost |
|---|---|---|
| pop 256→512 | evals/run ×2 | shard wall time ×2 (~40 min, still free) |
| gens 20→40 | deeper convergence, ×2 | same ×2 |
| shards 20 (plan cap) | parallelism | free plan caps at 20 concurrent jobs |
| corpus frames 24→16 | eval ×0.67 | less temporal diversity |
| resolution 320×192→640×384 | realism ×4 compute | needs self-hosted |

## Paths to 1e9

1. **Hosted nightly × bigger pops** (free): 512 × 40 × 20 = 409,600/run →
   ~7 months to 1e9. Slow but zero dollars.
2. **Spore swarm (community)**: anyone runs a shard on their own metal and
   PRs artifacts. 100 spore-runners ≈ 100× throughput → ~2 weeks. The spore
   protocol (pop/README.md) makes results mergeable and identity attributable.
3. **Self-hosted runners**: 20 × 8-core boxes ≈ 80× hosted throughput.
4. **The honest ceiling**: 1e9 evals of a 16-gene space (16-dim continuous)
   is overkill for the gene count — the point at ~1e7 is that *fitness
   landscape structure* becomes the interesting object (publish the
   accumulation curves, the gene interaction map). Billions are a
   community-scale statement, not a search requirement. Say this plainly
   when the milestone nears.

## Cost accounting (the asymmetric bet, in numbers)

- Hosted path: $0. Duration bounded by our patience.
- Time cost: ~1h/week of maintenance once nightly is green.
- Expected value: every 2% saving found = one upstream PR + one paper section
  + one hiring receipt. Any one of the three repays the whole project.
