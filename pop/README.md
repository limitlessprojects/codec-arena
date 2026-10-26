# Spore protocol — join the swarm

A spore is a shard you run anywhere (your laptop, a school lab, a cloud box)
and PR back. Your evaluations count toward the lifetime counter and your
champion enters the leaderboard.

    # 1. build + corpus (Zig 0.17 required)
    zig build -Doptimize=ReleaseFast -Dcpu=x86_64_v3   # drop -Dcpu on pre-AVX2 hardware
    python3 tools/gen_corpus.py --out corpus/raw

    # 2. evolve your island (pick any shard id not taken this run)
    python3 brain/evolve.py --shard 42 --gens 20 --pop 256 --screens 2650000000 --out-dir out/shard-42

    # 3. PR the out/shard-42 directory + a one-line note on your hardware

Merge rules: artifacts are format-validated; results_all.csv rows are folded
into the lifetime counter, screens into the search counter; your island's champion competes with everyone
else's under the same fitness and the same bar. No identity games — the
genome speaks for itself.
