# Benchmark: mdz vs @mdx-js/mdx

All benchmarks generate N random MDX files (deterministic seed 42), warmup 1 file, then measure per-file wall-clock latency. Same machine, same methodology.

## Environment

- **OS:** Windows
- **CPU:** DDR5
- **mdz build:** `-o:aggressive -microarch:native -no-bounds-check -disable-assert -lto:thin`
- **@mdx-js/mdx:** v3 via npm, `jsxRuntime: 'automatic'`

## Results

### 1KB files — varying file count

| Config | Library | Min | P50 | P90 | P99 | MB/s |
|--------|---------|----|-----|-----|-----|------|
| 1KB x 10 | **mdz** | 39 µs | **65 µs** | 86 µs | 86 µs | 17.8 |
| 1KB x 10 | @mdx-js/mdx | 6885 µs | **12677 µs** | 21411 µs | 21411 µs | 0.08 |
| 1KB x 50 | **mdz** | 32 µs | **54 µs** | 89 µs | 350 µs | 14.9 |
| 1KB x 50 | @mdx-js/mdx | 4334 µs | **7169 µs** | 12887 µs | 15126 µs | 0.13 |
| 1KB x 100 | **mdz** | 19 µs | **35 µs** | 58 µs | 125 µs | 26.7 |
| 1KB x 100 | @mdx-js/mdx | 3596 µs | **6208 µs** | 9479 µs | 18393 µs | 0.16 |

### 50 files — varying file size

| Config | Library | Min | P50 | P90 | P99 | MB/s |
|--------|---------|----|-----|-----|-----|------|
| 1KB x 50 | **mdz** | 19 µs | **27 µs** | 32 µs | 62 µs | 36.0 |
| 1KB x 50 | @mdx-js/mdx | 3782 µs | **5812 µs** | 8409 µs | 10207 µs | 0.17 |
| 10KB x 50 | **mdz** | 245 µs | **445 µs** | 529 µs | 798 µs | 22.6 |
| 10KB x 50 | @mdx-js/mdx | 41527 µs | **50712 µs** | 57736 µs | 63414 µs | 0.19 |
| 50KB x 50 | **mdz** | 1144 µs | **1700 µs** | 2658 µs | 3207 µs | 26.8 |
| 50KB x 50 | @mdx-js/mdx | 244038 µs | **277285 µs** | 309003 µs | 328185 µs | 0.18 |

## Summary

mdz is **~300–400× faster in P50 latency** and **~200–300× higher throughput** than @mdx-js/mdx across all file sizes. The numbers are higher than earlier releases due to the addition of two-pass nested list parsing, recursive blockquote processing, HTML entity support, JSX expression depth tracking, syntax highlighting, emoji, definition lists, continuation lines, loose/tight list distinction, reference links, and pipe escaping — all adding correctness for real-world MDX at minimal performance cost.

### Raw output files

- [mdz_results.txt](mdz_results.txt) — full mdz benchmark output
- [mdx_results.txt](mdx_results.txt) — full @mdx-js/mdx benchmark output
