import { compile } from '@mdx-js/mdx'
import { performance } from 'perf_hooks'

// ─── Seeded PRNG (mulberry32) ──────────────────────────────────────────────────

function createRng(seed) {
  let s = seed | 0
  return () => {
    s |= 0
    s = (s + 0x6d2b79f5) | 0
    let t = Math.imul(s ^ (s >>> 15), 1 | s)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function intMax(rng, max) {
  return Math.floor(rng() * max)
}

function intRange(rng, min, max) {
  return intMax(rng, max - min + 1) + min
}

// ─── Content generators ─────────────────────────────────────────────────────────

const WORDS = [
  'lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur',
  'adipiscing', 'elit', 'sed', 'do', 'eiusmod', 'tempor',
  'incididunt', 'ut', 'labore', 'et', 'dolore', 'magna',
  'aliqua', 'enim', 'ad', 'minim', 'veniam', 'quis',
  'nostrud', 'exercitation', 'ullamco', 'laboris', 'nisi',
  'aliquip', 'ex', 'ea', 'commodo', 'consequat', 'duis',
  'aute', 'irure', 'dolor', 'in', 'reprehenderit', 'voluptate',
  'velit', 'esse', 'cillum', 'eu', 'fugiat', 'nulla',
  'pariatur', 'excepteur', 'sint', 'occaecat', 'cupidatat',
  'non', 'proident', 'sunt', 'culpa', 'qui', 'officia',
  'deserunt', 'mollit', 'anim', 'id', 'est', 'laborum',
]

function writeRandomWords(rng, min, max) {
  const count = intRange(rng, min, max)
  const words = []
  for (let i = 0; i < count; i++) {
    words.push(WORDS[intMax(rng, WORDS.length)])
  }
  return words.join(' ')
}

function writeBlock(rng) {
  const roll = intMax(rng, 20)
  switch (roll) {
    case 0: {
      const n = intMax(rng, 6) + 1
      return '#'.repeat(n) + ' ' + writeRandomWords(rng, 2, 6) + '\n\n'
    }
    case 1:
    case 2: {
      if (intMax(rng, 4) === 0) {
        return writeRandomWords(rng, 4, 10) + ' **bold** ' + writeRandomWords(rng, 4, 10) + '\n\n'
      } else {
        return writeRandomWords(rng, 8, 20) + '\n\n'
      }
    }
    case 3: return '- item one\n- item two\n- item three\n\n'
    case 4: return '1. first\n2. second\n3. third\n\n'
    case 5: return '> blockquote content here\n\n'
    case 6: return '```javascript\nfunction hello() {\n  return 42;\n}\n```\n\n'
    case 7: return '<Simple />\n'
    case 8: return '<Component prop={42}>\n  <Inner />\n</Component>\n\n'
    case 9: return '{someExpression}\n\n'
    case 10: return '---\n\n'
    case 11: return 'Paragraph with `inline code` ' + writeRandomWords(rng, 4, 8) + '\n\n'
    case 12: return 'Visit [our docs](https://example.com) ' + writeRandomWords(rng, 3, 6) + '\n\n'
    case 13: return 'Here is an image ![alt](https://example.com/img.png)\n\n'
    case 14: return '{items.map(item => (\n  <div key={item.id}>{item.name}</div>\n))}\n\n'
    case 15:
    case 16: return writeRandomWords(rng, 5, 12) + '\n\n'
    case 17: return '```python\ndef fib(n):\n    return n if n < 2 else fib(n-1) + fib(n-2)\n```\n\n'
    case 18: return '## ' + writeRandomWords(rng, 2, 4) + '\n\n' + writeRandomWords(rng, 5, 10) + '\n\n- bullet a\n- bullet b\n- bullet c\n\n'
    case 19: return 'export const getStaticProps = async () => {\n  const data = await fetch("https://api.example.com/data")\n  const json = await data.json()\n  return { props: { data: json } }\n}\n\n'
    default: return ''
  }
}

function generateMdxFile(rng, sizeKb) {
  const parts = []
  parts.push("import {Component} from './component'\n")
  parts.push("import Another from './another.mdx'\n\n")
  parts.push('export const meta = {\n')
  parts.push("  title: 'Benchmark Page',\n")
  parts.push("  date: '2026-05-08'\n")
  parts.push('}\n\n')

  const target = sizeKb * 1024
  let size = parts.reduce((s, p) => s + p.length, 0)
  while (size < target) {
    const block = writeBlock(rng)
    parts.push(block)
    size += block.length
  }
  return parts.join('')
}

// ─── Benchmark runner ────────────────────────────────────────────────────────────

function nowUs() {
  return performance.now() * 1000
}

async function runBench(label, fileCount, sizeKb) {
  const rng = createRng(42)
  const files = []
  let totalSize = 0
  for (let i = 0; i < fileCount; i++) {
    const f = generateMdxFile(rng, sizeKb)
    files.push(f)
    totalSize += f.length
  }

  const compileOpts = {
    jsx: true,
    jsxRuntime: 'automatic',
    jsxImportSource: 'react',
  }

  // Warmup
  try {
    await compile(files[0], compileOpts)
  } catch {}

  const durations = []
  let totalTime = 0

  for (let i = 0; i < fileCount; i++) {
    const start = nowUs()
    try {
      await compile(files[i], compileOpts)
    } catch {}
    const elapsed = nowUs() - start
    durations.push(elapsed)
    totalTime += elapsed
  }

  durations.sort((a, b) => a - b)

  function percentile(p) {
    const idx = Math.floor((p / 100) * durations.length)
    return durations[Math.min(idx, durations.length - 1)]
  }

  const totalSec = totalTime / 1_000_000
  const mbTotal = totalSize / (1024 * 1024)
  const throughput = mbTotal / totalSec

  console.log(`  Files:       ${fileCount}`)
  console.log(`  Total size:  ${(totalSize / 1024).toFixed(2)} KB (${totalSize} bytes)`)
  console.log(`  Total time:  ${(totalTime / 1000).toFixed(2)} ms`)
  console.log(`  ─────────────────────────────────`)
  console.log(`  Min latency:      ${durations[0].toFixed(2)} µs`)
  console.log(`  Max latency:      ${durations[fileCount - 1].toFixed(2)} µs`)
  console.log(`  Mean latency:     ${(totalTime / fileCount).toFixed(2)} µs`)
  console.log(`  ─────────────────────────────────`)
  console.log(`  P50  (median):    ${percentile(50).toFixed(2)} µs`)
  console.log(`  P90:              ${percentile(90).toFixed(2)} µs`)
  console.log(`  P95:              ${percentile(95).toFixed(2)} µs`)
  console.log(`  P99 (tail):       ${percentile(99).toFixed(2)} µs`)
  console.log(`  ─────────────────────────────────`)
  console.log(`  Throughput:       ${throughput.toFixed(2)} MB/s`)
  console.log(`  Files/sec:        ${(fileCount / totalSec).toFixed(0)}`)
}

// ─── Entry point ──────────────────────────────────────────────────────────────────

console.log('╔══════════════════════════════════════════════════════════╗')
console.log('║    @mdx-js/mdx — MDX Compiler Benchmark Suite           ║')
console.log('╚══════════════════════════════════════════════════════════╝')
console.log()

async function main() {
  // Sanity check
  console.log('Sanity check: compiling a single 1KB file...')
  const rng = createRng(42)
  const testFile = generateMdxFile(rng, 1)
  console.log(`  Generated ${testFile.length} bytes`)
  const result = await compile(testFile, {
    jsx: true,
    jsxRuntime: 'automatic',
    jsxImportSource: 'react',
  })
  console.log(`  Compiled to ${result.toString().length} bytes — OK`)
  console.log()

  console.log('Benchmark methodology (same as mdz):')
  console.log('  - P50 is the median. P99 is the tail (what users actually feel)')
  console.log()

  // 1KB files — varying file count
  console.log('────────────────────────────────────────────────────────────')
  console.log('1KB files — varying file count (scaling)')
  console.log('────────────────────────────────────────────────────────────')
  for (const count of [10, 50, 100]) {
    console.log(`\nCompiling ${count} files at ~1KB each...`)
    await runBench(`${count} files`, count, 1)
    console.log()
  }

  // 50 files — varying file size
  console.log('────────────────────────────────────────────────────────────')
  console.log('50 files — varying file size (content density)')
  console.log('────────────────────────────────────────────────────────────')
  for (const kb of [1, 10, 50]) {
    console.log(`\nCompiling 50 files at ~${kb}KB each...`)
    await runBench(`${kb}KB x 50`, 50, kb)
    console.log()
  }
}

main().catch(console.error)
