# mdz — blazing-fast MDX → JSX compiler

A single-pass, zero-AST MDX-to-JSX compiler written in [Odin](https://odin-lang.org).  
Uses direct byte-scanning — no AST, no nodes, no tokens.

~**900× faster** than @mdx-js/mdx at P50 latency (8 µs vs 7169 µs for 1 KB files).

## Why mdz is fast: design from first principles

Most compilers build an AST, transform it, then emit code. That's three passes, each requiring allocations, intermediate representations, and memory management. `mdz` does everything in **one pass**: scan the input byte-by-byte and emit JSX directly.

These are the architectural decisions that make mdz ~900× faster than @mdx-js/mdx from the start — before any micro-optimizations:

### 1. Zero AST, zero tokens, zero nodes

@mdx-js/mdx uses remark-parse to build a full mdast (Markdown AST), then walks it to generate JSX. This means:
- Allocating AST nodes for every element (headings, paragraphs, inlines)
- Storing parent-child relationships
- Walking the tree to emit output
- Freeing all allocations

mdz skips this entirely. The input is scanned once, and JSX is emitted directly. There are no nodes to allocate, link, or free.

### 2. JSX and JS passthrough — no parsing of the hard parts

The hardest part of MDX compilation is parsing JavaScript/JSX — balanced braces, arrow functions, template literals, JSX expressions, etc. @mdx-js/mdx uses [micromark](https://github.com/micromark/micromark) for markdown and then hands JSX/JS regions to a full JS parser.

mdz takes a different approach: it detects JSX elements and JS expressions by scanning for balanced delimiters (`< >`, `{ }`, strings, etc.) and copies them through verbatim. **No JS parsing**. This is the single biggest speed advantage — mdz doesn't try to understand JavaScript, it just finds where it ends.

Trade-off: mdz won't catch JS syntax errors inside JSX blocks. If you need that, use a linter separately.

### 3. Single pre-allocated output buffer

@mdx-js/mdx composes output through multiple layers (remark plugins → rehype plugins → string concatenation). Each layer may allocate and free intermediate strings.

mdz writes directly into one pre-sized `[dynamic]byte` buffer. The buffer starts at `input × 2` capacity and grows at most a few times. There is exactly one output buffer allocation per compilation.

### 4. Block classification by first byte

Instead of parsing line-by-line and maintaining parser state, mdz classifies each block by inspecting its first byte:
- `#` → heading
- `>` → blockquote
- `-` or `1-9` → list
- `` ` `` → fence
- `<` → JSX element or HTML
- `{` → JS expression
- `i` or `e` → import/export
- `---` → thematic break

This is O(1) classification — no regex, no line-by-line state machine.

### 5. No remark/rehype plugin architecture

@mdx-js/mdx is built around a plugin system (remark + rehype). This makes it extensible but adds overhead: every plugin wraps the AST, transforms it, and passes it on. Even with zero plugins, the infrastructure still runs.

mdz has no plugin system. There is nothing between input and output except the compiler itself. If you need transformations, apply them before or after compilation.

### 6. Asterisk-only emphasis

mdz only recognizes `*` for emphasis, not `_`. This eliminates ambiguity when scanning — the scanner doesn't need to check if `_` starts emphasis or is part of an identifier. A small sacrifice in convenience, a real saving in scan complexity.

## API

```odin
import mdz "mdz"

// Compile an MDX string to a JSX module string.
// The caller owns the returned string and should delete it.
result, err := mdz.compile(mdx_input)
if err != nil {
    fmt.eprintf("error: %s\n", err.(mdz.Compile_Error).message)
}
defer delete(result)

// Or read from a file:
result, err = mdz.compile_file("input.mdx")
```

## CLI

```
mdz [options] <file.mdx>
```

Options:
- `-o <file>`    Write output to file instead of stdout
- `--bench`      Run benchmarks
- `-h, --help`   Show help

Examples:
```
mdz input.mdx                    # print to stdout
mdz -o output.jsx input.mdx      # write to file
mdz --bench                      # run benchmarks
```

## Build

Prerequisites: [Odin](https://odin-lang.org) nightly + a C compiler (Visual Studio on Windows, GCC/Clang on Linux/macOS).

### All platforms (using make)

```sh
make build       # debug build
make build-fast  # optimized build
make test        # run tests
```

### Windows

```batch
build_fast.bat
```

### Linux / macOS

```sh
./build.sh
```

### Fast build flags

`-o:speed -microarch:native -no-bounds-check -disable-assert -lto:thin`

## Performance

Benchmark methodology (inspired by [Ahmed Ayob's article on P99 latency](https://www.linkedin.com/pulse/how-i-wrote-rust-mdx-compiler-beats-velite-10x-p99-latency-mohamed-ayob/)):  
Generate N random MDX files (deterministic seed 42), warmup 1 file, measure per-file wall-clock latency.  
Report P50 (median) and P99 (tail — what users feel). Throughput in MB/s of input processed.

### mdz vs @mdx-js/mdx

| Config | Library | P50 | P99 | MB/s |
|--------|---------|-----|-----|------|
| **1KB × 50** | **mdz** | **8 µs** | 18 µs | **111.0** |
| 1KB × 50 | @mdx-js/mdx | 7169 µs | 15126 µs | 0.13 |
| **10KB × 50** | **mdz** | **75 µs** | 83 µs | **128.8** |
| 10KB × 50 | @mdx-js/mdx | 50712 µs | 63414 µs | 0.19 |
| **50KB × 50** | **mdz** | **417 µs** | 2418 µs | **93.2** |
| 50KB × 50 | @mdx-js/mdx | 277285 µs | 328185 µs | 0.18 |

**mdz is ~600–900× faster in P50 latency and ~600–700× higher throughput** than @mdx-js/mdx.

Full benchmark details: [benchmark/benchmark.md](benchmark/benchmark.md)

### mdz standalone

| Config | P50 | P99 | Throughput |
|--------|-----|-----|------------|
| **1KB × 50** | **8 µs** | 18 µs | **111 MB/s** |
| **10KB × 50** | **75 µs** | 83 µs | **129 MB/s** |
| **50KB × 50** | **417 µs** | 2418 µs | **93 MB/s** |

## Architecture

```
main.odin          CLI — reads file, calls compile_file, prints output

mdz/
  buffer.odin      Writer — pre-allocated [dynamic]byte wrapper
  types.odin       BlockType enum, Compile_Error
  scanner.odin     Byte helpers, block classification, JS boundary detection
  inline.odin      Inline markdown→JSX (bold, italic, code, links, images, expressions)
  blocks.odin      Block-level processors (headings, lists, fences, blockquotes, etc.)
  mdz.odin         Public API — compile loop + output assembly
```

### Data flow

```
Input MDX
  │
  ▼
classify_block ──► First byte inspection → BlockType
  │
  ▼
process_* ──► Dispatched by BlockType, emits JSX to Writer
  │              (or skips frontmatter)
  ▼
Output assembly ──► module_code + body wrapped in MDXContent()
```

## Supported markdown

| Feature | Example | Output |
|---------|---------|--------|
| Heading | `## Title` | `<h2>Title</h2>` |
| Paragraph | `text` | `<p>text</p>` |
| Bold | `**bold**` | `<strong>bold</strong>` |
| Italic | `*italic*` | `<em>italic</em>` |
| Bold+Italic | `***both***` | `<em><strong>both</strong></em>` |
| Inline code | `` `code` `` | `<code>code</code>` |
| Link | `[text](url)` | `<a href="url">text</a>` |
| Image | `![alt](url)` | `<img src="url" alt="alt"/>` |
| Unordered list | `- item` | `<ul><li>item</li></ul>` |
| Ordered list | `1. item` | `<ol><li>item</li></ol>` |
| Blockquote | `> text` | `<blockquote><p>text</p></blockquote>` |
| Code fence | `` ```lang `` | `<pre><code class="language-lang">...</code></pre>` |
| Thematic break | `---` | `<hr/>` |
| Strikethrough | `~~text~~` | `<del>text</del>` |
| Table | `\| a \| b \|` | `<table><th>a</th><th>b</th>...` |
| JSX element | `<Component />` | passthrough |
| JS expression | `{expr}` | passthrough |
| Import/Export | `import X from 'y'` | passthrough (module-level) |
| HTML entities | `&#1234;` | passthrough; bare `&` → `&amp;` |
| Escaped chars | `\*` | literal `*` |

## C / Rust bindings

mdz can be compiled as a shared library and used from C or Rust.

### Build the shared library

```sh
make ffi                 # all platforms
```
Or manually:
```sh
odin build ffi -build:shared -o:speed -no-bounds-check -disable-assert
```

Produces `mdz.dll` (Windows), `libmdz.so` (Linux), or `libmdz.dylib` (macOS) in the project root.

### C usage

```c
#include "c/mdz.h"

char* output = NULL;
char* error = NULL;
int ret = mdz_compile_file("input.mdx", &output, &error);
if (ret == 0) {
    printf("%s", output);
    mdz_free_string(output);
} else {
    fprintf(stderr, "%s\n", error);
    mdz_free_string(error);
}
```

Build and run:
```sh
make c-example   # or: cd c && make
./c/mdz_c input.mdx
```

### Rust usage

```rust
use mdz_sys;

let output = mdz_sys::compile_file("input.mdx").unwrap();
println!("{}", output);
```

Run the Rust example:
```sh
make rust-example                    # or: cd rust && cargo run --example compile -- ../input.mdx
```

## Benchmarks

Run both mdz and @mdx-js/mdx benchmarks:

```sh
make bench       # mdz only
make bench-mdx   # @mdx-js/mdx only
```

Or use the scripts:
```sh
benchmark/run_benchmarks.sh    # Linux/macOS
benchmark/run_benchmarks.bat   # Windows
```

Results are saved to `benchmark/mdz_results.txt` and `benchmark/mdx_results.txt`.

## How we got here — the optimization journey

The design decisions above made mdz fast from day one (~27 MB/s). Here's how we took it from 27 → 111 MB/s:

### Round 1: Batch-copy plain text in `convert_inline`

**Problem**: `convert_inline` wrote every non-special character one byte at a time through `writer_write_byte`. For a 50 KB file of mostly plain text, that's ~50,000 individual `append` calls, each checking capacity.

**Fix**: Scan for the next trigger character (`*`, `` ` ``, `[`, `!`, `{`, `<`, `~`, `\`, `&`), then copy the entire span in one `writer_write` call. This converts O(n) appends into O(triggers) appends.

**Gain**: ~15% (27→31 MB/s).

### Round 2: Bulk append atomic write + inline paragraphs + `len×2` buffer

**Problem**: `writer_write` iterated byte-by-byte with `#no_bounds_check for i in 0..<len(s) { append(&buf, s[i]) }`. Each iteration called `append` which checked capacity, created a full call frame, and resolved the dynamic array pointer. The loop overhead was massive.

**Fix**: Replace with a single `append(&w.buf, ..transmute([]byte)s)`. This is a single memcpy — the runtime copies all bytes in one shot with no per-byte overhead.

**Problem**: `process_paragraph` called `split_lines(content)` which heap-allocated a `[]string` array, then iterated it.

**Fix**: Scan for `\n` inline and call `convert_inline` per line segment directly. Zero allocation.

**Problem**: Buffer starting size `input + 25%` caused growth reallocations.

**Fix**: Use `input × 2` as starting capacity for the body writer. Fewer reallocations = fewer memcpys of accumulated data.

**Gain**: ~3× (31→100 MB/s). **The single biggest win.**

### Round 3: Batch-copy escape functions + link fast-path + frontmatter cleanup

**Problem**: `write_escaped` and `write_url_escaped` still wrote byte-by-byte in their default case (non-special chars).

**Fix**: Same pattern as Round 1 — find the next character that needs escaping, batch-copy the span.

**Problem**: `handle_link` scanned backward through the entire URL looking for a space before an optional title. For links without titles (the common case), this was wasted scanning.

**Fix**: Check the last character first — if it's not `"` or `'`, there's no title, skip the backward scan entirely.

**Gain**: ~30% (70→115 MB/s for 50 KB files).

### Round 4: Eliminate the final clone

**Problem**: The assembly phase created a `result` Writer, copied module + body + boilerplate into it, then `strings.clone`'d the result to return it. This was two full copies of the output.

**Fix**: Use `strings.concatenate([]string{...})` instead. It pre-computes the total length, allocates one buffer, and copies each piece in one pass. No clone needed.

**Gain**: <5% (saved one memcpy, but processing dominates).

### Round 5: Every-function micro-optimization

A systematic pass through every function:

| File | Change | Why |
|------|--------|-----|
| `scanner.odin` | Frontmatter scan only runs when `pos==0` (file start) | Avoids O(n) scan for closing `---` on every `---` thematic break in mid-file |
| `scanner.odin` | `skip_blank_lines` switch → if-chain | Switch compiled to jump table; if-chain is simpler for 4 cases |
| `scanner.odin` | Removed dead `is_within_fence` | Unused code |
| `inline.odin` | Inlined trigger check in `convert_inline` hot path | Avoids function call/ret overhead per character |
| `inline.odin` | `find_closing` single-char fast path | Skips substring comparison for `*`, `~`, `` ` `` |
| `blocks.odin` | `process_heading` tag emission simplified | Removed intermediate `[3]byte` array |

**Gain**: Small improvements lost in Windows scheduler noise (±5-10%), but real reductions in code path length.

### Key insights

1. **Avoid per-byte operations**. Every byte that goes through a function call, capacity check, or dynamic dispatch adds overhead. Batch everything you can.

2. **Transmute `string` to `[]byte` for bulk append**. `append(&buf, ..s)` doesn't compile (string ≠ []byte), but `append(&buf, ..transmute([]byte)s)` does one memcpy. This was the single biggest win.

3. **Pre-size buffers**. `[dynamic]byte` grows exponentially (2×), but every growth copies existing data. Pre-size with a generous estimate.

4. **Avoid allocations in hot paths**. `split_lines` in `process_paragraph` was trivially replaced with inline scanning, eliminating one heap allocation per paragraph.

5. **P99 matters more than P50**. The median is the cost when nothing is wrong. P99 is the cost when the OS scheduler preempts you, a page fault occurs, or the CPU migrates cores. On Windows, P99 variance can be ±50 µs from scheduler noise alone.

## Project structure

```
main.odin              CLI entry point + benchmarks
mdz/                   Core library
ffi/                   Shared library (C ABI) wrapper
c/                     C header + example
rust/                  Rust crate (mdz-sys)
benchmark/             Benchmarks + comparison results
build.sh               Unix build script
build_fast.bat         Windows build script
Makefile               Cross-platform build
.odin/                 odin package index
test.odin              Unit tests
```

## License

MIT License — see [LICENSE](LICENSE).
