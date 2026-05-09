package main

import "core:fmt"
import "core:math/rand"
import "core:sort"
import "core:strings"
import "core:time"
import mdz "mdz"

// ─── Content generators ──────────────────────────────────────────────────────

WORDS := []string{
    "lorem", "ipsum", "dolor", "sit", "amet", "consectetur",
    "adipiscing", "elit", "sed", "do", "eiusmod", "tempor",
    "incididunt", "ut", "labore", "et", "dolore", "magna",
    "aliqua", "enim", "ad", "minim", "veniam", "quis",
    "nostrud", "exercitation", "ullamco", "laboris", "nisi",
    "aliquip", "ex", "ea", "commodo", "consequat", "duis",
    "aute", "irure", "dolor", "in", "reprehenderit", "voluptate",
    "velit", "esse", "cillum", "eu", "fugiat", "nulla",
    "pariatur", "excepteur", "sint", "occaecat", "cupidatat",
    "non", "proident", "sunt", "culpa", "qui", "officia",
    "deserunt", "mollit", "anim", "id", "est", "laborum",
}

// write_random_words writes min..max random space-separated words to buf
write_random_words :: proc(buf: ^strings.Builder, min, max: int) {
    count := rand.int_max(max - min + 1) + min
    for i in 0 ..< count {
        if i > 0 {
            strings.write_byte(buf, ' ')
        }
        idx := rand.int_max(len(WORDS))
        strings.write_string(buf, WORDS[idx])
    }
}

// write_block appends one random MDX block to buf
write_block :: proc(buf: ^strings.Builder) {
    roll := rand.int_max(20)
    switch roll {
    case 0:
        n := rand.int_max(6) + 1
        strings.write_byte(buf, '#')
        for j := 1; j < n; j += 1 {
            strings.write_byte(buf, '#')
        }
        strings.write_byte(buf, ' ')
        write_random_words(buf, 2, 6)
        strings.write_string(buf, "\n\n")
    case 1, 2:
        if rand.int_max(4) == 0 {
            write_random_words(buf, 4, 10)
            strings.write_string(buf, " **bold** ")
            write_random_words(buf, 4, 10)
            strings.write_string(buf, "\n\n")
        } else {
            write_random_words(buf, 8, 20)
            strings.write_string(buf, "\n\n")
        }
    case 3:
        strings.write_string(buf, "- item one\n- item two\n- item three\n\n")
    case 4:
        strings.write_string(buf, "1. first\n2. second\n3. third\n\n")
    case 5:
        strings.write_string(buf, "> blockquote content here\n\n")
    case 6:
        strings.write_string(buf, "```javascript\nfunction hello() {\n  return 42;\n}\n```\n\n")
    case 7:
        strings.write_string(buf, "<Simple />\n")
    case 8:
        strings.write_string(buf, "<Component prop={42}>\n  <Inner />\n</Component>\n\n")
    case 9:
        strings.write_string(buf, "{someExpression}\n\n")
    case 10:
        strings.write_string(buf, "---\n\n")
    case 11:
        strings.write_string(buf, "Paragraph with `inline code` ")
        write_random_words(buf, 4, 8)
        strings.write_string(buf, "\n\n")
    case 12:
        strings.write_string(buf, "Visit [our docs](https://example.com) ")
        write_random_words(buf, 3, 6)
        strings.write_string(buf, "\n\n")
    case 13:
        strings.write_string(buf, "Here is an image ![alt](https://example.com/img.png)\n\n")
    case 14:
        strings.write_string(buf, "{items.map(item => (\n  <div key={item.id}>{item.name}</div>\n))}\n\n")
    case 15, 16:
        write_random_words(buf, 5, 12)
        strings.write_string(buf, "\n\n")
    case 17:
        strings.write_string(buf, "```python\ndef fib(n):\n    return n if n < 2 else fib(n-1) + fib(n-2)\n```\n\n")
    case 18:
        strings.write_string(buf, "## ")
        write_random_words(buf, 2, 4)
        strings.write_string(buf, "\n\n")
        write_random_words(buf, 5, 10)
        strings.write_string(buf, "\n\n- bullet a\n- bullet b\n- bullet c\n\n")
    case 19:
        strings.write_string(buf, "export const getStaticProps = async () => {\n  const data = await fetch('https://api.example.com/data')\n  const json = await data.json()\n  return { props: { data: json } }\n}\n\n")
    }
}

generate_mdx_file :: proc(size_kb: int) -> string {
    b := strings.builder_make(context.allocator)

    strings.write_string(&b, "import {Component} from './component'\n")
    strings.write_string(&b, "import Another from './another.mdx'\n\n")
    strings.write_string(&b, "export const meta = {\n")
    strings.write_string(&b, "  title: 'Benchmark Page',\n")
    strings.write_string(&b, "  date: '2026-05-08'\n")
    strings.write_string(&b, "}\n\n")

    target := size_kb * 1024
    for strings.builder_len(b) < target {
        write_block(&b)
    }
    return strings.to_string(b)
}

// ─── Benchmark runner ─────────────────────────────────────────────────────────

BenchResult :: struct {
    label:       string,
    file_count:  int,
    total_size:  int,
    total_time:  time.Duration,
    min_lat:     time.Duration,
    max_lat:     time.Duration,
    mean_lat:    time.Duration,
    p50_lat:     time.Duration,
    p90_lat:     time.Duration,
    p95_lat:     time.Duration,
    p99_lat:     time.Duration,
}

run_bench :: proc(label: string, file_count: int, size_kb: int) -> BenchResult {
    rand.reset(42)

    files := make([]string, file_count)
    defer {
        for f in files {
            delete(f)
        }
        delete(files)
    }

    total_size := 0
    for i in 0 ..< file_count {
        files[i] = generate_mdx_file(size_kb)
        total_size += len(files[i])
    }

    durations := make([]time.Duration, file_count)
    defer delete(durations)

    total_time: time.Duration

    // Warmup
    result, err := mdz.compile(files[0])
    if err == nil {
        delete(result)
    }

    for i in 0 ..< file_count {
        start := time.now()
        result, err := mdz.compile(files[i])
        durations[i] = time.diff(start, time.now())
        if err == nil {
            delete(result)
        }
        total_time += durations[i]
    }

    // Sort durations for percentiles
    sort.quick_sort(durations)

    min_lat := durations[0]
    max_lat := durations[file_count - 1]
    mean_lat := total_time / auto_cast file_count

    return BenchResult{
        label      = label,
        file_count = file_count,
        total_size = total_size,
        total_time = total_time,
        min_lat    = min_lat,
        max_lat    = max_lat,
        mean_lat   = mean_lat,
        p50_lat    = durations[(50 * file_count) / 100],
        p90_lat    = durations[(90 * file_count) / 100],
        p95_lat    = durations[(95 * file_count) / 100],
        p99_lat    = durations[(99 * file_count) / 100],
    }
}

// ─── Results printer ─────────────────────────────────────────────────────────

print_separator :: proc(title: string) {
    fmt.println("\n────────────────────────────────────────────────────────────")
    fmt.println(title)
    fmt.println("────────────────────────────────────────────────────────────")
}

to_us :: proc(d: time.Duration) -> f64 {
    return f64(d) / 1000.0
}

print_results :: proc(r: BenchResult) {
    total_sec := f64(r.total_time) / 1_000_000_000.0
    mb_total := f64(r.total_size) / (1024.0 * 1024.0)
    throughput_mbps := mb_total / total_sec

    fmt.printfln("  Files:       %d", r.file_count)
    fmt.printfln("  Total size:  %.2f KB (%d bytes)", f64(r.total_size)/1024.0, r.total_size)
    fmt.printfln("  Total time:  %.2f ms", to_us(r.total_time) / 1000.0)
    fmt.printfln("  ─────────────────────────────────")
    fmt.printfln("  Min latency:      %8d µs", int(to_us(r.min_lat)))
    fmt.printfln("  Max latency:      %8d µs", int(to_us(r.max_lat)))
    fmt.printfln("  Mean latency:     %8d µs", int(to_us(r.mean_lat)))
    fmt.printfln("  ─────────────────────────────────")
    fmt.printfln("  P50  (median):    %8d µs", int(to_us(r.p50_lat)))
    fmt.printfln("  P90:              %8d µs", int(to_us(r.p90_lat)))
    fmt.printfln("  P95:              %8d µs", int(to_us(r.p95_lat)))
    fmt.printfln("  P99 (tail):       %8d µs", int(to_us(r.p99_lat)))
    fmt.printfln("  ─────────────────────────────────")
    fmt.printfln("  Throughput:       %.2f MB/s", throughput_mbps)
    fmt.printfln("  Files/sec:        %.0f", f64(r.file_count) / total_sec)
}

print_summary :: proc(results: []BenchResult) {
    fmt.println("\n──────────────────────────────────────────────────────────────────────────────")
    fmt.println("Summary: mdz compilation latency (all values in µs)")
    fmt.println("──────────────────────────────────────────────────────────────────────────────")
    fmt.printfln("%-25s %8s %8s %8s %8s %10s", "Config", "Min", "P50", "P90", "P99", "MB/s")
    fmt.println("──────────────────────────────────────────────────────────────────────────────")
    for i in 0 ..< len(results) {
        r := results[i]
        total_sec := f64(r.total_time) / 1_000_000_000.0
        mb_total := f64(r.total_size) / (1024.0 * 1024.0)
        tput := mb_total / total_sec
        fmt.printfln("%-25s %8d %8d %8d %8d %10.1f",
            r.label,
            int(to_us(r.min_lat)),
            int(to_us(r.p50_lat)),
            int(to_us(r.p90_lat)),
            int(to_us(r.p99_lat)),
            tput,
        )
    }
    fmt.println("──────────────────────────────────────────────────────────────────────────────")
}

// ─── Entry point ──────────────────────────────────────────────────────────────

run_benchmarks :: proc() {
    fmt.println("╔══════════════════════════════════════════════════════════╗")
    fmt.println("║         mdz — MDX Compiler Benchmark Suite              ║")
    fmt.println("╚══════════════════════════════════════════════════════════╝")
    fmt.println()

    // Quick sanity test first
    fmt.println("Sanity check: compiling a single 1KB file...")
    rand.reset(42)
    test_file := generate_mdx_file(1)
    defer delete(test_file)
    fmt.printfln("  Generated %d bytes", len(test_file))
    result, err := mdz.compile(test_file)
    if err != nil {
        fmt.eprintfln("FAIL: compile error: %s", err.(mdz.Compile_Error).message)
        return
    }
    defer delete(result)
    fmt.printfln("  Compiled to %d bytes — OK", len(result))
    fmt.println()

    fmt.println("Benchmark methodology (inspired by Ahmed Ayob):")
    fmt.println("  - P50 is the median. P99 is the tail (what users actually feel)")
    fmt.println()

    results := make([dynamic]BenchResult)
    defer {
        for r in results {
            delete(r.label)
        }
        delete(results)
    }

    // Benchmark: varying file count at fixed 1KB size
    print_separator("1KB files — varying file count (scaling)")
    {
        counts := []int{10, 50, 100}
        for count in counts {
            fmt.printfln("Compiling %d files at ~1KB each...", count)
            label := strings.clone(fmt.tprintf("1KB x %d", count))
            r := run_bench(label, count, 1)
            append(&results, r)
            print_results(r)
            fmt.println()
        }
    }

    // Benchmark: varying file size at fixed 50 files
    print_separator("50 files — varying file size (content density)")
    {
        sizes := []int{1, 10, 50}
        for kb in sizes {
            fmt.printfln("Compiling 50 files at ~%dKB each...", kb)
            label := strings.clone(fmt.tprintf("%dKB x 50", kb))
            r := run_bench(label, 50, kb)
            append(&results, r)
            print_results(r)
            fmt.println()
        }
    }

    // Summary table
    print_summary(results[:])

    fmt.println("\nKey insight (quote from Ahmed Ayob's article):")
    fmt.println("  'The median is the cost when nothing is wrong.")
    fmt.println("   P99 is the cost when something predictable is wrong.")
    fmt.println("   That's what your users feel every day.'")
    fmt.println()
	fmt.println("Build config: -o:aggressive -lto:thin -microarch:native -no-bounds-check -disable-assert")
    fmt.println()
}
