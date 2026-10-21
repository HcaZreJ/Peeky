#!/usr/bin/env bash
# 终端版真终端冒烟：在隐藏的 kitty 窗口里运行 peek-tui，不打扰屏幕。
#
# 用法：scripts/tui-smoke.sh <文件[:行]|目录> [按键文本 | !命令 ...]
#   每个按键参数用 `kitty @ send-text` 发送（支持 \x1b 这类转义），发完读回一次屏幕文字；
#   以 ! 开头的参数改为执行该 shell 命令（例如在树根新建文件），等 1 秒再读屏；
#   最后发送 q，打印退出码，并比较进入前后的 `stty -a` 是否一致（终端设置是否还原）。
# 环境变量：
#   PEEK_TUI_BIN  peek-tui 路径（缺省 .build/out/Products/Debug/peek-tui）
#   COLS / ROWS   窗口格数（缺省 80 × 20）
#   ANSI=1        读屏时带上颜色转义（get-text --ansi）
#   KITTY_ARGS    额外的 kitty 选项，例如 "-o background=#ffffff -o foreground=#000000" 模拟浅色终端
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${PEEK_TUI_BIN:-$ROOT_DIR/.build/out/Products/Debug/peek-tui}"
TARGET="${1:?用法：scripts/tui-smoke.sh <文件[:行]> [按键文本 ...]}"
shift
# kitty 启动的子进程工作目录与这里不同，相对路径先转成绝对路径。
[[ "$TARGET" == /* ]] || TARGET="$PWD/$TARGET"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/peek-smoke.XXXXXX")"
SOCK="$WORK/kitty.sock"
# `!` 命令里可用 `kitty @ --to "$KITTY_SOCKET" …` 操作这个窗口（例如 set-colors 换背景）
export KITTY_SOCKET="unix:$SOCK"
kitty --start-as=hidden --config NONE \
  -o allow_remote_control=yes --listen-on "unix:$SOCK" -o remember_window_size=no ${KITTY_ARGS:-} \
  -o "initial_window_width=${COLS:-80}c" -o "initial_window_height=${ROWS:-20}c" \
  sh -c "stty -a > '$WORK/stty-before'; '$BIN' '$TARGET'; echo \$? > '$WORK/exit-code'; stty -a > '$WORK/stty-after'; sleep 30" \
  > "$WORK/kitty.log" 2>&1 &
KITTY_PID=$!
trap 'kill "$KITTY_PID" 2>/dev/null || true; rm -rf "$WORK"' EXIT

for _ in $(seq 1 50); do
  [[ -S "$SOCK" ]] && break
  sleep 0.1
done
[[ -S "$SOCK" ]] || { echo "kitty 远程控制 socket 没有出现"; cat "$WORK/kitty.log"; exit 1; }
sleep "${FIRST_FRAME_WAIT:-1.5}"

read_screen() {
  if [[ "${ANSI:-0}" == "1" ]]; then
    kitty @ --to "unix:$SOCK" get-text --extent screen --ansi
  else
    kitty @ --to "unix:$SOCK" get-text --extent screen
  fi
}

echo "=== 初始画面"
read_screen
for keys in "$@"; do
  if [[ "$keys" == '!'* ]]; then
    sh -c "${keys:1}"
    sleep 1
    echo "=== 执行 ${keys:1} 之后"
  else
    kitty @ --to "unix:$SOCK" send-text "$keys"
    sleep 0.3
    echo "=== 发送 $keys 之后"
  fi
  read_screen
done

kitty @ --to "unix:$SOCK" send-text q
for _ in $(seq 1 20); do
  [[ -f "$WORK/stty-after" ]] && break
  sleep 0.1
done
echo "=== 退出码：$(cat "$WORK/exit-code" 2>/dev/null || echo 未退出)"
if [[ -f "$WORK/stty-after" ]] && diff -q "$WORK/stty-before" "$WORK/stty-after" > /dev/null; then
  echo "=== 终端设置已还原"
else
  echo "=== 终端设置与进入前不一致"
  diff "$WORK/stty-before" "$WORK/stty-after" || true
fi
