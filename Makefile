.PHONY: build corpus seed eval anchor arena-local clean test

build:
	zig build -Doptimize=ReleaseFast

corpus:
	python3 tools/gen_corpus.py --out corpus/raw

seed:
	python3 tools/gen_seed.py --out pop/seed.txt

eval: build corpus
	./zig-out/bin/arena eval --corpus corpus/raw --pop pop/seed.txt --out results.csv

anchor: build corpus
	python3 tools/anchor.py

arena-local: build corpus seed
	python3 brain/evolve.py --shard 0 --gens 10 --pop 64 --out-dir out/local

test: build
	zig test src/yuv.zig && zig test src/genome.zig

clean:
	rm -rf zig-out .zig-cache corpus/raw out results.csv
