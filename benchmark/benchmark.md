# Benchmark: mdz vs @mdx-js/mdx

All benchmarks generate N random MDX files (deterministic seed 42), warmup 1 file, then measure per-file wall-clock latency. Same machine, same methodology.

## Environment

- **OS:** Windows
- **CPU:** DDR5
- **mdz build:** `-o:speed -microarch:native -no-bounds-check -disable-assert -lto:thin`
- **@mdx-js/mdx:** v3 via npm, `jsxRuntime: 'automatic'`

## Results

### 1KB files — varying file count

| Config | Library | Min | P50 | P90 | P99 | MB/s |
|--------|---------|----|-----|-----|-----|------|
| 1KB x 10 | **mdz** | 9 µs | **11 µs** | 13 µs | 13 µs | 97.1 |
| 1KB x 10 | @mdx-js/mdx | 6885 µs | **12677 µs** | 21411 µs | 21411 µs | 0.08 |
| 1KB x 50 | **mdz** | 7 µs | **8 µs** | 10 µs | 18 µs | 111.0 |
| 1KB x 50 | @mdx-js/mdx | 4334 µs | **7169 µs** | 12887 µs | 15126 µs | 0.13 |
| 1KB x 100 | **mdz** | 7 µs | **10 µs** | 12 µs | 87 µs | 89.0 |
| 1KB x 100 | @mdx-js/mdx | 3596 µs | **6208 µs** | 9479 µs | 18393 µs | 0.16 |

### 50 files — varying file size

| Config | Library | Min | P50 | P90 | P99 | MB/s |
|--------|---------|----|-----|-----|-----|------|
| 1KB x 50 | **mdz** | 7 µs | **9 µs** | 12 µs | 15 µs | 104.3 |
| 1KB x 50 | @mdx-js/mdx | 3782 µs | **5812 µs** | 8409 µs | 10207 µs | 0.17 |
| 10KB x 50 | **mdz** | 69 µs | **75 µs** | 79 µs | 83 µs | 128.8 |
| 10KB x 50 | @mdx-js/mdx | 41527 µs | **50712 µs** | 57736 µs | 63414 µs | 0.19 |
| 50KB x 50 | **mdz** | 378 µs | **417 µs** | 550 µs | 2418 µs | 93.2 |
| 50KB x 50 | @mdx-js/mdx | 244038 µs | **277285 µs** | 309003 µs | 328185 µs | 0.18 |

## Summary

mdz is **~600–800× faster in P50 latency** and **~600–700× higher throughput** than @mdx-js/mdx across all file sizes.

The gap widens with file size because @mdx-js/mdx builds a full AST (remark-parse → mdast → transforms → codegen), while mdz does a single byte-scanning pass with no intermediate allocations.

### Raw output files

- [mdz_results.txt](mdz_results.txt) — full mdz benchmark output
- [mdx_results.txt](mdx_results.txt) — full @mdx-js/mdx benchmark output
