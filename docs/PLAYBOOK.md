# The Overseer Playbook

This document is the standing order for whoever (or whatever) runs the arena.
It exists so the project survives context loss, maintainer rotation, and
success — because success attracts contributors, and contributors need to
know the rules of the game.

## Mandate

Spread the bets. The org runs a science wing (ClockBench) and now an
engineering wing (Codec Arena). Both share one doctrine: **claim the
measurement, stay neutral, publish the gap.**

## The 20-point discipline (condensed to what binds daily work)

1. **Wedge**: the arena IS the wedge — measurement infrastructure first,
   product later. Measurement infra earns citations; citations earn the room.
2. **Metric of record**: `score = PSNR − 14·bpp − complexity`. Change it only
   with a written rationale in a PR that also re-runs the last 5 merges.
3. **The bar is external**: every leaderboard must show the real-codec table
   above our own numbers. No exceptions, no crops.
4. **Determinism**: corpus, seeds, and oracle must be reproducible byte-for-byte.
   A benchmark that drifts is a rumor.
5. **Honesty artifacts**: results_all.csv (every eval), LESSONS.md (every
   merge), lifetime counter (cumulative). If a number isn't in a file, it
   doesn't exist.
6. **Asymmetry check**: any new compute must be justified by expected
   information gain per CI-minute. The downside stays bounded; that's the bet.
7. **Graduation criteria** (when findings leave the arena):
   - a stable ≥2% bitrate saving at equal PSNR on ≥2 corpus classes, AND
   - an explanation (mechanism, not just a winner genome), AND
   - a reproduction on an independent shard seed.
   Then: file upstream (SVT-AV1/x264) with the RD table attached.

## Milestones and kill criteria

| When | Target | Kill / pivot if |
|---|---|---|
| 7d | champion ≥ +10% fitness over gen-0 pool; Mojo differential green | if fitness plateaus < +3%, widen genome (add genes) before adding compute |
| 30d | champion ≥ x264-ultrafast at equal PSNR on ≥1 clip class | if < 30% of the gap to ultrafast closes, pivot corpus toward harder content (where naive codecs have more headroom) |
| 90d | 1M lifetime evals; 1 transferable finding filed upstream | if no transferable finding, the arena pivots to benchmark-infrastructure-only (still valuable, cite-able) |

## Non-negotiables

- The bar stays external and visible.
- Closes and merges are never silent (borrowed from the hyb doctrine).
- No compute escalation without a written expected-yield note.
- Every run leaves artifacts; every artifact is committed or attached.

## Standing next-actions

1. Nightly arena (scheduled) — watch for red, fix within 24h.
2. Weekly: re-read LESSONS.md, prune gene space if a gene is flatlined.
3. Moontide rule: when a milestone is crossed, write the Ship Log entry the
   same day. Momentum is a story told in public.
