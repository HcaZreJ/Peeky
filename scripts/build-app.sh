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

# SwiftPM copies PeekyKit's declared resources (shiki-bundle.js) into a
# `Peeky_PeekyKit.bundle` next to the release binary. The generated
# Bundle.module accessor resolves it via
# `Bundle.main.bundleURL.appendingPathComponent("Peeky_PeekyKit.bundle")`,
# and for a launched .app, Bundle.main.bundleURL is the .app's own root
# directory (NOT Contents/Resources) — verified empirically with a
# minimal .app-structured test binary. The resource bundle must therefore
# sit at the top level of the .app, as a sibling of Contents/.
for resource_bundle in "$ROOT_DIR"/.build/release/*.bundle; do
  [[ -e "$resource_bundle" ]] || continue
  cp -R "$resource_bundle" "$APP_DIR/"
done

codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_DIR="$HOME/Applications/Peeky.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$INSTALL_DIR"
  cp -R "$APP_DIR" "$INSTALL_DIR"
  echo "$INSTALL_DIR"

  mkdir -p "$HOME/.local/bin"
  ln -sf "$ROOT_DIR/bin/peek" "$HOME/.local/bin/peek"
  echo "$HOME/.local/bin/peek"

  RESOLVED_PEEK="$(command -v peek || true)"
  if [[ -n "$RESOLVED_PEEK" && "$RESOLVED_PEEK" != "$HOME/.local/bin/peek" ]]; then
    echo "note: PATH resolves 'peek' to $RESOLVED_PEEK, not ~/.local/bin/peek"
  fi
fi
