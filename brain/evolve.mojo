# evolve.mojo — the Mojo brain of Codec Arena (v0 kernel).
#
# Status: v0 proves the toolchain + the genetics core. It runs the SAME
# algorithm as the Python brain's genetics (tournament -> uniform crossover ->
# annealed gaussian mutation -> rare jumps) against a stand-in fitness
# landscape that mirrors the arena's shape (quality minus bits, with a
# deadzone-drift penalty term). v1 wires this kernel to the arena's CSV
# oracle; the Python brain remains the reference oracle until then.
#
# Deterministic: xorshift64 seeded from a constant. Same seed, same
# evolution, every machine — that is what makes the differential test with
# Python meaningful.

from sys import argv
import math

alias NG = 16
alias POP = 96
alias GENS = 50

struct Xorshift:
    var s: UInt64

    fn __init__(inout self, seed: UInt64):
        self.s = seed if seed != 0 else 0x9E3779B97F4A7C15

    fn next(inout self) -> UInt64:
        var x = self.s
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        self.s = x
        return x

    fn unit(inout self) -> Float64:
        return Float64(self.next() >> 11) * (1.0 / 9007199254740992.0)

fn gauss_of(inout rng: Xorshift) -> Float64:
    # Box-Muller
    var u1 = rng.unit()
    var u2 = rng.unit()
    if u1 <= 1e-12:
        u1 = 1e-12
    var r = math.sqrt(-2.0 * math.log(u1))
    return r * math.cos(6.28318530718 * u2)

fn clamp01(x: Float64) -> Float64:
    if x < 0.0:
        return 0.0
    if x > 1.0:
        return 1.0
    return x

# The stand-in landscape: a toy codec model with the same tradeoffs.
fn landscape(g: InlineArray[Float64, NG]) -> Float64:
    var baseq = g[3]
    var pqm = g[9]
    var psnr = 16.0 + 22.0 * baseq - 3.0 * g[6] * baseq
    var bpp = 0.04 + 2.4 * baseq * baseq * (1.0 - 0.35 * pqm)
    var drift = 2.5 * g[7] * (1.0 - g[13])
    var complexity = 0.02 * g[2]
    return psnr - 14.0 * bpp - drift - complexity

fn pick_tournament(inout rng: Xorshift, fits: InlineArray[Float64, POP]) -> Int:
    var best_i = Int(rng.next() % POP)
    for _ in range(3):
        var c = Int(rng.next() % POP)
        if fits[c] > fits[best_i]:
            best_i = c
    return best_i

fn main() raises:
    _ = argv()
    var rng = Xorshift(0x4A2E1A)
    var pop = InlineArray[InlineArray[Float64, NG], POP](
        lambda _: InlineArray[Float64, NG](lambda _: rng.unit()))
    var fits = InlineArray[Float64, POP](lambda _: 0.0)

    var best_overall: Float64 = -1e9
    var best_genome = InlineArray[Float64, NG](lambda _: 0.5)

    for gen in range(GENS):
        var sigma = 0.22 * math.pow(0.93, Float64(gen))
        for i in range(POP):
            fits[i] = landscape(pop[i])
        var newpop = InlineArray[InlineArray[Float64, NG], POP](
            lambda _: InlineArray[Float64, NG](lambda _: 0.5))
        for c in range(POP):
            var pa_i = pick_tournament(rng, fits)
            var pb_i = pick_tournament(rng, fits)
            var child = InlineArray[Float64, NG](lambda _: 0.0)
            for k in range(NG):
                child[k] = pop[pa_i][k] if rng.unit() < 0.5 else pop[pb_i][k]
            if rng.unit() < 0.02:
                child[Int(rng.next() % NG)] = rng.unit()
            else:
                var gi = Int(rng.next() % NG)
                child[gi] = clamp01(child[gi] + gauss_of(rng) * sigma)
            newpop[c] = child
        pop = newpop
        for i in range(POP):
            var f = landscape(pop[i])
            if f > best_overall:
                best_overall = f
                best_genome = pop[i]

    print("mojo brain v0 — deterministic genetics kernel")
    print("generations: ", GENS, " population: ", POP)
    print("best fitness: ", best_overall)
    print("best genome:  ", end="")
    for k in range(NG):
        print(best_genome[k], end=" ")
    print()
