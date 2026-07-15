// Evaluates Resources/shiki-bundle.js in a bare vm context (no require,
// no process, no Node/browser globals injected) to approximate the bare
// JavaScriptCore JSContext it will actually run in, then exercises the
// peekyInit/peekyTokenize globals it is expected to expose.
import vm from 'node:vm'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const BUNDLE_PATH = join(SCRIPT_DIR, '..', '..', 'Sources', 'PeekyKit', 'Resources', 'shiki-bundle.js')

// Known Dark Modern / Dark+ colors: comments and keywords.
const KNOWN_COLORS = new Set(['#6a9955', '#569cd6', '#c586c0', '#4ec9b0', '#ce9178', '#b5cea8'])

const SAMPLES = {
  python: [
    '# comment',
    'def add(a, b):',
    '    return a + b',
    '',
  ].join('\n'),
  typescript: [
    '// comment',
    'interface Point {',
    '  x: number',
    '  y: number',
    '}',
    'const origin: Point = { x: 0, y: 0 }',
  ].join('\n'),
  json: [
    '{',
    '  "name": "peeky",',
    '  "count": 3,',
    '  "enabled": true',
    '}',
  ].join('\n'),
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(`assertion failed: ${message}`)
  }
}

async function main() {
  const bundleSource = readFileSync(BUNDLE_PATH, 'utf8')
  const context = vm.createContext({})

  assert(typeof context.require === 'undefined', 'sandbox must not expose require')
  assert(typeof context.process === 'undefined', 'sandbox must not expose process')
  // Node's vm module leaks its own `console` into every context (a known
  // vm limitation), so it is not asserted absent here; the bundle still
  // self-polyfills it defensively for the real bare-JSContext target,
  // which has no console at all.
  for (const name of ['fetch', 'document', 'window', 'TextEncoder', 'TextDecoder']) {
    assert(
      vm.runInContext(`typeof ${name}`, context) === 'undefined',
      `sandbox must not pre-expose ${name} (bundle should self-provide what it needs)`,
    )
  }

  vm.runInContext(bundleSource, context, { filename: 'shiki-bundle.js' })

  const peekyInit = vm.runInContext('peekyInit', context)
  const peekyTokenize = vm.runInContext('peekyTokenize', context)
  const peekyTokenizeChunk = vm.runInContext('peekyTokenizeChunk', context)

  assert(typeof peekyInit === 'function', 'peekyInit must be a function')
  assert(typeof peekyTokenize === 'function', 'peekyTokenize must be a function')
  assert(typeof peekyTokenizeChunk === 'function', 'peekyTokenizeChunk must be a function')

  await peekyInit()
  // idempotency: calling init again must not throw or hang.
  await peekyInit()

  for (const [lang, text] of Object.entries(SAMPLES)) {
    const expectedLines = text.split('\n').length
    const result = await peekyTokenize(text, lang)

    assert(Array.isArray(result.lines), `${lang}: result.lines must be an array`)
    assert(
      result.lines.length === expectedLines,
      `${lang}: expected ${expectedLines} lines, got ${result.lines.length}`,
    )

    let tokenCount = 0
    let sawKnownColor = false
    const colorsSeen = new Set()
    for (const line of result.lines) {
      for (const token of line) {
        tokenCount += 1
        assert(typeof token.t === 'string', `${lang}: token.t must be a string`)
        assert(/^#[0-9a-f]{6}$/.test(token.c), `${lang}: token.c must be lowercase #rrggbb, got ${token.c}`)
        colorsSeen.add(token.c)
        if (KNOWN_COLORS.has(token.c)) sawKnownColor = true
      }
    }

    assert(tokenCount > 0, `${lang}: expected at least one non-empty token`)
    assert(sawKnownColor, `${lang}: expected at least one known dark-modern/dark-plus color, saw ${[...colorsSeen].join(', ')}`)

    console.log(`${lang}: lines=${result.lines.length} tokens=${tokenCount} colors=${[...colorsSeen].join(',')}`)
  }

  // Chunked/continuation tokenize: split the typescript sample into two
  // chunks and confirm the stateId handle threads state across calls.
  const tsLines = SAMPLES.typescript.split('\n')
  const chunkA = tsLines.slice(0, 3).join('\n')
  const chunkB = tsLines.slice(3).join('\n')

  const first = await peekyTokenizeChunk(chunkA, 'typescript', null)
  assert(Array.isArray(first.lines), 'chunk A: lines must be an array')
  assert(first.stateId !== null && first.stateId !== undefined, 'chunk A: stateId must be returned')

  const second = await peekyTokenizeChunk(chunkB, 'typescript', first.stateId)
  assert(Array.isArray(second.lines), 'chunk B: lines must be an array')
  assert(second.lines.length === tsLines.slice(3).length, 'chunk B: line count must match its own text')

  console.log(`typescript chunked: chunkA.stateId=${first.stateId} chunkB.stateId=${second.stateId}`)
  console.log('smoke OK')
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
