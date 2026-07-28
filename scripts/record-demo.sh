#!/usr/bin/env bash
# Record Peeky demo assets: hero video (mp4 + gif) and three still screenshots.
# Usage:
#   bash scripts/record-demo.sh              # all: stills then video
#   bash scripts/record-demo.sh --stills     # only PNG stills
#   bash scripts/record-demo.sh --video      # only mp4 + gif
#   bash scripts/record-demo.sh --screen 3   # override avfoundation screen index
set -euo pipefail

MODE="all"
SCREEN_INDEX="1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stills) MODE="stills"; shift ;;
    --video)  MODE="video";  shift ;;
    --all)    MODE="all";    shift ;;
    --screen) SCREEN_INDEX="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$REPO_ROOT/assets"
SAMPLES="$ASSETS/demo-samples"
APP_PATH="$HOME/Applications/Peeky.app"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "record-demo: missing '$1' — $2" >&2; exit 1; }
}
require ffmpeg "brew install ffmpeg"
require osascript "should ship with macOS"
require swift "install Xcode Command Line Tools: xcode-select --install"
[[ -d "$APP_PATH" ]] || { echo "record-demo: $APP_PATH not found — run: bash scripts/build-app.sh --install" >&2; exit 1; }
[[ -d "$SAMPLES" ]] || { echo "record-demo: samples dir missing at $SAMPLES" >&2; exit 1; }
[[ -f "$REPO_ROOT/scripts/peeky-window-id.swift" ]] || { echo "record-demo: missing scripts/peeky-window-id.swift" >&2; exit 1; }

mkdir -p "$ASSETS"

kill_peeky() {
  osascript -e 'tell application "Peeky" to quit' >/dev/null 2>&1 || true
  pkill -x Peeky >/dev/null 2>&1 || true
  sleep 0.4
}

peeky_window_id() {
  swift "$REPO_ROOT/scripts/peeky-window-id.swift" 2>/dev/null || true
}

peek_open() {
  local target="$1"; local suffix="${2:-}"
  local url_target="$target"
  [[ -n "$suffix" ]] && url_target="${target}${suffix}"
  "$REPO_ROOT/bin/peek" "$url_target" >/dev/null
}

# ---------------- stills ----------------
capture_stills() {
  echo "[stills] capturing PNGs into $ASSETS ..."
  local pairs=(
    "showcase.md::demo-markdown.png"
    "sample.json::demo-json.png"
    "formatter.py::demo-code.png"
  )
  for pair in "${pairs[@]}"; do
    IFS=":" read -r file suffix out <<< "$pair"
    kill_peeky
    peek_open "$SAMPLES/$file" "$suffix"
    local wid=""
    for _ in $(seq 1 40); do
      wid="$(peeky_window_id | tr -d '[:space:]')"
      [[ -n "$wid" ]] && break
      sleep 0.15
    done
    if [[ -z "$wid" ]]; then
      echo "  [warn] no Peeky window found for $file (grant Terminal.app Screen Recording permission in System Settings → Privacy)" >&2
      continue
    fi
    sleep 0.7
    screencapture -x -o -l "$wid" "$ASSETS/$out"
    echo "  wrote $ASSETS/$out (window=$wid)"
  done
  kill_peeky
}

# ---------------- video ----------------
record_video() {
  echo "[video] recording $ASSETS/demo.mp4 ..."
  kill_peeky

  local raw="$ASSETS/demo.raw.mp4"
  local final="$ASSETS/demo.mp4"
  local gif="$ASSETS/demo.gif"
  local palette; palette="$(mktemp -t peeky-demo-palette).png"
  rm -f "$raw" "$final" "$gif"

  # Fixed 24 s ceiling; ffmpeg exits on its own.
  ffmpeg -hide_banner -loglevel error -y \
    -f avfoundation -framerate 30 -capture_cursor 1 \
    -i "${SCREEN_INDEX}:none" \
    -t 24 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
    -movflags +faststart "$raw" &
  local ffpid=$!

  # Give ffmpeg time to warm up before user-visible action starts.
  sleep 1.2

  # Drive Terminal.app to run three `peek` calls with pauses in between.
  local script_body
  script_body=$(cat <<APPLESCRIPT
tell application "Terminal"
  activate
  set W to do script "cd '$REPO_ROOT' && clear"
  delay 0.4
  try
    set bounds of front window to {80, 80, 1080, 420}
  end try
  delay 1.6
  do script "./bin/peek assets/demo-samples/showcase.md" in W
  delay 5.5
  do script "./bin/peek assets/demo-samples/sample.json:8" in W
  delay 5.5
  do script "./bin/peek assets/demo-samples/formatter.py:22:5" in W
  delay 5.5
end tell
APPLESCRIPT
)
  osascript -e "$script_body" >/dev/null || true

  wait "$ffpid" || true

  # Re-encode a color-optimized gif for README embedding.
  ffmpeg -hide_banner -loglevel error -y -i "$raw" \
    -vf "fps=15,scale=1200:-1:flags=lanczos,palettegen=max_colors=192" "$palette"
  ffmpeg -hide_banner -loglevel error -y -i "$raw" -i "$palette" \
    -filter_complex "fps=15,scale=1200:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=4" "$gif"

  mv "$raw" "$final"
  rm -f "$palette"
  kill_peeky

  echo "  wrote $final"
  echo "  wrote $gif"
}

case "$MODE" in
  stills) capture_stills ;;
  video)  record_video ;;
  all)    capture_stills; record_video ;;
esac

echo "done."
