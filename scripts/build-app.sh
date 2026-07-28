#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

APP_DIR="$ROOT_DIR/.build/Peeky.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/.build/release/Peeky" "$APP_DIR/Contents/MacOS/Peeky"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/Peeky.icns" "$APP_DIR/Contents/Resources/Peeky.icns"
chmod +x "$APP_DIR/Contents/MacOS/Peeky"

# peek CLI 打进 bundle,Homebrew Cask 用 binary stanza 直接 symlink 到 PATH。
cp "$ROOT_DIR/bin/peek" "$APP_DIR/Contents/Resources/peek"
chmod +x "$APP_DIR/Contents/Resources/peek"

# PEEKY_VERSION 由 CI 从 git tag 注入(去掉 v 前缀);本地构建不设置则沿用 Info.plist 里的现值。
if [[ -n "${PEEKY_VERSION:-}" ]]; then
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$PEEKY_VERSION" "$APP_DIR/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$PEEKY_VERSION" "$APP_DIR/Contents/Info.plist"
fi

# SwiftPM copies PeekyKit's declared resources (shiki-bundle.js) into a
# `Peeky_PeekyKit.bundle` next to the release binary. HighlightService's
# loadBundleSource() looks for it under Bundle.main.resourceURL first
# (standard .app layout: Contents/Resources), so it ships there — keeping
# the .app root clean for codesign (no "unsealed contents" warning).
for resource_bundle in "$ROOT_DIR"/.build/release/*.bundle; do
  [[ -e "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$APP_DIR/Contents/Resources/"
done

codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_DIR="$HOME/Applications/Peeky.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$INSTALL_DIR"
  cp -R "$APP_DIR" "$INSTALL_DIR"
  echo "$INSTALL_DIR"

  # symlink 指 bundle 里的 peek,让"本地 --install"和"brew install --cask"对齐同一份 peek 源。
  mkdir -p "$HOME/.local/bin"
  ln -sf "$INSTALL_DIR/Contents/Resources/peek" "$HOME/.local/bin/peek"
  echo "$HOME/.local/bin/peek"

  RESOLVED_PEEK="$(command -v peek || true)"
  if [[ -n "$RESOLVED_PEEK" && "$RESOLVED_PEEK" != "$HOME/.local/bin/peek" ]]; then
    echo "note: PATH resolves 'peek' to $RESOLVED_PEEK, not ~/.local/bin/peek"
  fi
fi
