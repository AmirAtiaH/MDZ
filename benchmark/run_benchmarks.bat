@echo off
cd /d "%~dp0.."

echo ╔══════════════════════════════════════════════════════════╗
echo ║         MDX Compiler Benchmark Suite                    ║
echo ║         mdz + @mdx-js/mdx                               ║
echo ╚══════════════════════════════════════════════════════════╝
echo.

echo ^> Running mdz benchmark...
mdz --bench > "benchmark\mdz_results.txt" 2>&1
type "benchmark\mdz_results.txt"
echo.

echo ^> Running @mdx-js/mdx benchmark...
node "benchmark\mdx_bench.mjs" > "benchmark\mdx_results.txt" 2>&1
type "benchmark\mdx_results.txt"
echo.

echo Done. Results saved to:
echo   benchmark\mdz_results.txt
echo   benchmark\mdx_results.txt
