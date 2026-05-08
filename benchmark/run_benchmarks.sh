#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Running mdz benchmark..."
./mdz --bench > benchmark/mdz_results.txt 2>&1
cat benchmark/mdz_results.txt
echo ""

echo "==> Running @mdx-js/mdx benchmark..."
node benchmark/mdx_bench.mjs > benchmark/mdx_results.txt 2>&1
cat benchmark/mdx_results.txt
echo ""

echo "Done. Results saved to benchmark/mdz_results.txt and benchmark/mdx_results.txt"
