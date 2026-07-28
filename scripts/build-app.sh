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
  # --install 装的是「dev 版」:独立 bundle ID / app name / URL scheme,
  # 与 Homebrew Cask 装的正式版(/Applications/Peeky.app)完全隔离,LaunchServices 各走各的。
  INSTALL_DIR="$HOME/Applications/Peeky Dev.app"
  mkdir -p "$HOME/Applications"

  # 清理旧版 --install 遗留(旧脚本装的是 Peeky.app,新脚本改装 Peeky Dev.app)。
  if [[ -d "$HOME/Applications/Peeky.app" ]]; then
    echo "note: removing legacy $HOME/Applications/Peeky.app (--install now creates Peeky Dev.app)"
    rm -rf "$HOME/Applications/Peeky.app"
  fi

  rm -rf "$INSTALL_DIR"
  cp -R "$APP_DIR" "$INSTALL_DIR"

  # 转换成 dev 身份。改完 Info.plist 会让原签名失效,需要重新 ad-hoc 签。
  PLIST="$INSTALL_DIR/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleIdentifier -string "local.peeky.dev" "$PLIST"
  /usr/bin/plutil -replace CFBundleName -string "Peeky Dev" "$PLIST"
  /usr/bin/plutil -replace CFBundleDisplayName -string "Peeky Dev" "$PLIST"
  # 用 -json 整体替换 schemes 数组;-replace 对数组元素是 insert 而非替换,会残留原 scheme。
  /usr/bin/plutil -replace 'CFBundleURLTypes.0.CFBundleURLSchemes' -json '["peeky-dev"]' "$PLIST"
  codesign --force --sign - "$INSTALL_DIR"

  echo "$INSTALL_DIR"

  # symlink 指 dev bundle 里的 peek;peek 脚本内部会按 --dev flag / 位置探测决定用哪个 app。
  mkdir -p "$HOME/.local/bin"
  ln -sf "$INSTALL_DIR/Contents/Resources/peek" "$HOME/.local/bin/peek"
  echo "$HOME/.local/bin/peek"

  RESOLVED_PEEK="$(command -v peek || true)"
  if [[ -n "$RESOLVED_PEEK" && "$RESOLVED_PEEK" != "$HOME/.local/bin/peek" ]]; then
    echo "note: PATH resolves 'peek' to $RESOLVED_PEEK, not ~/.local/bin/peek"
  fi
fi
