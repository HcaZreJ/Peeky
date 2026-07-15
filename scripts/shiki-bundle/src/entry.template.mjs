import { createHighlighterCore } from 'shiki/core'
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript'

/*__LANG_IMPORTS__*/
import darkModernTheme from '../vendor/dark-modern-theme.json'

// Bare JavaScriptCore (no WKWebView) does not provide TextEncoder/TextDecoder.
// oniguruma-to-es only reaches them on the rare Oniguruma raw-multibyte-escape
// path (`\x89`.."\xFF" runs), which none of our 9 grammars trigger, but we
// self-provide a minimal UTF-8-only implementation so the bundle never
// depends on a host global for it.
if (typeof globalThis.TextEncoder === 'undefined') {
  globalThis.TextEncoder = class TextEncoder {
    encode(input) {
      const bytes = []
      for (const ch of String(input)) {
        const cp = ch.codePointAt(0)
        if (cp < 0x80) {
          bytes.push(cp)
        } else if (cp < 0x800) {
          bytes.push(0xc0 | (cp >> 6), 0x80 | (cp & 0x3f))
        } else if (cp < 0x10000) {
          bytes.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f))
        } else {
          bytes.push(
            0xf0 | (cp >> 18),
            0x80 | ((cp >> 12) & 0x3f),
            0x80 | ((cp >> 6) & 0x3f),
            0x80 | (cp & 0x3f),
          )
        }
      }
      return Uint8Array.from(bytes)
    }
  }
}

if (typeof globalThis.TextDecoder === 'undefined') {
  globalThis.TextDecoder = class TextDecoder {
    constructor(_label, _options) {}
    decode(input) {
      const bytes = input instanceof Uint8Array ? input : new Uint8Array(input)
      let out = ''
      let i = 0
      while (i < bytes.length) {
        const b0 = bytes[i]
        if (b0 < 0x80) {
          out += String.fromCharCode(b0)
          i += 1
        } else if ((b0 & 0xe0) === 0xc0) {
          out += String.fromCodePoint(((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f))
          i += 2
        } else if ((b0 & 0xf0) === 0xe0) {
          out += String.fromCodePoint(
            ((b0 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f),
          )
          i += 3
        } else if ((b0 & 0xf8) === 0xf0) {
          out += String.fromCodePoint(
            ((b0 & 0x07) << 18) |
              ((bytes[i + 1] & 0x3f) << 12) |
              ((bytes[i + 2] & 0x3f) << 6) |
              (bytes[i + 3] & 0x3f),
          )
          i += 4
        } else {
          throw new Error('invalid utf-8 byte sequence')
        }
      }
      return out
    }
  }
}

// Bare JavaScriptCore does not provide `console` either; a couple of
// defensive/rare-path branches inside shiki's dependencies call
// console.warn/console.log, so self-provide a no-op sink rather than
// depend on a host global that may not exist.
if (typeof globalThis.console === 'undefined') {
  const noop = () => {}
  globalThis.console = { log: noop, warn: noop, error: noop, info: noop, debug: noop }
}

const THEME_NAME = 'dark-modern'
// Lines longer than this are emitted as a single plain token instead of
// being run through the grammar, to bound worst-case tokenize latency.
const TOKENIZE_MAX_LINE_LENGTH = 10000

const LANGS = [
/*__LANG_ARRAY__*/
]

let highlighterPromise = null
let defaultForegroundColor = '#d4d4d4'

const grammarStates = new Map()
let nextStateId = 1

function normalizeColor(color) {
  if (!color) return defaultForegroundColor
  let hex = color.toLowerCase()
  if (hex.length === 9) hex = hex.slice(0, 7)
  return hex
}

function tokensToLines(tokens) {
  return tokens.map((line) =>
    line.map((token) => ({
      t: token.content,
      c: normalizeColor(token.color),
    })),
  )
}

function getHighlighter() {
  if (!highlighterPromise) {
    highlighterPromise = createHighlighterCore({
      themes: [darkModernTheme],
      langs: LANGS,
      engine: createJavaScriptRegexEngine({ forgiving: true }),
      warnings: false,
    }).then((highlighter) => {
      defaultForegroundColor = normalizeColor(
        highlighter.getTheme(THEME_NAME).fg,
      )
      return highlighter
    })
  }
  return highlighterPromise
}

function peekyInit() {
  return getHighlighter().then(() => undefined)
}

function tokenizeWith(highlighter, text, lang, grammarState) {
  return highlighter.codeToTokensBase(text, {
    lang,
    theme: THEME_NAME,
    grammarState,
    tokenizeMaxLineLength: TOKENIZE_MAX_LINE_LENGTH,
  })
}

function peekyTokenize(text, lang) {
  return getHighlighter().then((highlighter) => ({
    lines: tokensToLines(tokenizeWith(highlighter, text, lang)),
  }))
}

function peekyTokenizeChunk(text, lang, stateId) {
  return getHighlighter().then((highlighter) => {
    const prevState =
      stateId === null || stateId === undefined
        ? undefined
        : grammarStates.get(stateId)
    const tokens = tokenizeWith(highlighter, text, lang, prevState)
    const nextState = highlighter.getLastGrammarState(tokens)
    const id = nextStateId++
    grammarStates.set(id, nextState)
    return {
      lines: tokensToLines(tokens),
      stateId: id,
    }
  })
}

globalThis.peekyInit = peekyInit
globalThis.peekyTokenize = peekyTokenize
globalThis.peekyTokenizeChunk = peekyTokenizeChunk
