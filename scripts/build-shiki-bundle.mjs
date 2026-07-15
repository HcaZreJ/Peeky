#!/usr/bin/env node
// Builds Resources/shiki-bundle.js: a single-file, non-ESM script that
// vendors shiki's fine-grained core + JS regex engine + a fixed language
// set + a flattened VS Code "Dark Modern" theme, for evaluation inside a
// bare JavaScriptCore context (no Node/browser host APIs at runtime).
//
// Idempotent: rerunning regenerates the flattened theme and the bundle
// from the vendored VS Code theme sources and the pinned npm deps.

import { writeFileSync, statSync, readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { createRequire } from 'node:module'

import { flattenDarkModernTheme } from './shiki-bundle/src/flatten-theme.mjs'

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const BUNDLE_DIR = join(SCRIPT_DIR, 'shiki-bundle')
const REPO_ROOT = dirname(SCRIPT_DIR)
const OUT_FILE = join(REPO_ROOT, 'Sources', 'PeekyKit', 'Resources', 'shiki-bundle.js')

// esbuild is a devDependency of scripts/shiki-bundle, not of this script's
// own directory; resolve it relative to that package explicitly.
const esbuild = createRequire(join(BUNDLE_DIR, 'package.json'))('esbuild')
const MAX_BYTES = 1024 * 1024

// Keep priority when trimming to fit the size budget: typescript and
// python are never dropped; the remaining languages are dropped in this
// order (least-important-first) until the bundle fits.
const DROP_ORDER = ['ini', 'swift', 'bash', 'toml', 'yaml', 'json', 'javascript']

// Bare identifier/substring matching is unreliable here: TextMate grammar
// JSON embedded in the bundle legitimately contains scope-name strings like
// "entity.other.document.begin.yaml", and TextEncoder/TextDecoder are
// intentionally self-polyfilled in src/entry.template.mjs (see there for
// why). These patterns instead target actual DOM/Node/browser API *calls*
// that would indicate a real host dependency slipped in.
const FORBIDDEN_PATTERNS = [
  { name: 'fetch(', re: /\bfetch\s*\(/ },
  { name: 'XMLHttpRequest', re: /\bXMLHttpRequest\b/ },
  { name: 'document.<dom-api>', re: /\bdocument\.(getElementById|createElement|querySelector|body|documentElement)\b/ },
  { name: 'window.<browser-api>', re: /\bwindow\.(location|fetch|document)\b/ },
  { name: 'require(', re: /\brequire\s*\(/ },
]

function flattenTheme() {
  const theme = flattenDarkModernTheme(join(BUNDLE_DIR, 'vendor', 'vscode-theme-src'))
  writeFileSync(
    join(BUNDLE_DIR, 'vendor', 'dark-modern-theme.json'),
    JSON.stringify(theme, null, 2) + '\n',
  )
  return theme
}

function langImportLine(lang) {
  return `import lang_${lang} from '@shikijs/langs/${lang}'\n`
}

function buildEntrySource(activeLangs) {
  const template = readFileSync(join(BUNDLE_DIR, 'src', 'entry.template.mjs'), 'utf8')
  const imports = activeLangs.map(langImportLine).join('')
  const arrayBody = activeLangs.map((lang) => `  lang_${lang},\n`).join('')
  return template
    .replace('/*__LANG_IMPORTS__*/', imports)
    .replace('/*__LANG_ARRAY__*/', arrayBody)
}

async function bundle(activeLangs) {
  const entrySource = buildEntrySource(activeLangs)
  const entryPath = join(BUNDLE_DIR, 'src', 'entry.generated.mjs')
  writeFileSync(entryPath, entrySource)

  const result = await esbuild.build({
    entryPoints: [entryPath],
    bundle: true,
    format: 'iife',
    platform: 'neutral',
    target: 'es2022',
    minify: true,
    legalComments: 'none',
    write: false,
    absWorkingDir: BUNDLE_DIR,
  })

  return result.outputFiles[0].contents
}

function checkForbiddenGlobals(source) {
  const hits = FORBIDDEN_PATTERNS.filter(({ re }) => re.test(source)).map(({ name }) => name)
  if (hits.length > 0) {
    throw new Error(`bundle references forbidden host APIs: ${hits.join(', ')}`)
  }
}

async function main() {
  flattenTheme()

  const allLangs = [
    'typescript',
    'python',
    'javascript',
    'json',
    'yaml',
    'toml',
    'bash',
    'swift',
    'ini',
  ]

  let activeLangs = [...allLangs]
  let contents = await bundle(activeLangs)
  const dropped = []

  for (const candidate of DROP_ORDER) {
    if (contents.byteLength <= MAX_BYTES) break
    if (!activeLangs.includes(candidate)) continue
    activeLangs = activeLangs.filter((lang) => lang !== candidate)
    dropped.push(candidate)
    contents = await bundle(activeLangs)
  }

  const text = Buffer.from(contents).toString('utf8')
  checkForbiddenGlobals(text)

  writeFileSync(OUT_FILE, text)
  const { size } = statSync(OUT_FILE)

  console.log(`langs: ${activeLangs.join(', ')}`)
  if (dropped.length > 0) {
    console.log(`dropped to fit size budget: ${dropped.join(', ')}`)
  }
  console.log(`bundle size: ${size} bytes (${(size / 1024).toFixed(1)} KiB)`)
  if (size > MAX_BYTES) {
    throw new Error(`bundle exceeds ${MAX_BYTES} bytes even after dropping all optional langs`)
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
