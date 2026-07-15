import { readFileSync } from 'node:fs'
import { parse as parseJsonc } from 'jsonc-parser'

// VS Code theme include chain: dark_modern -> dark_plus -> dark_vs.
// Each file is loaded base-first (dark_vs), then overlaid by its includer
// (dark_plus, then dark_modern), matching VS Code's own theme merge order:
// `colors` are shallow-merged with the includer winning; `tokenColors` are
// concatenated with the includer's rules appended after the base rules so
// they win ties in TextMate scope specificity.
const CHAIN = ['dark_vs.json', 'dark_plus.json', 'dark_modern.json']

function loadJsonc(path) {
  return parseJsonc(readFileSync(path, 'utf8'))
}

export function flattenDarkModernTheme(vendorDir) {
  const colors = {}
  const tokenColors = []

  for (const file of CHAIN) {
    const raw = loadJsonc(`${vendorDir}/${file}`)
    Object.assign(colors, raw.colors ?? {})
    if (Array.isArray(raw.tokenColors)) {
      tokenColors.push(...raw.tokenColors)
    }
  }

  return {
    name: 'dark-modern',
    type: 'dark',
    colors,
    tokenColors,
  }
}
