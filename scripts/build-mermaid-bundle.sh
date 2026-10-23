#!/usr/bin/env bash
# 重新生成 Sources/PeekyCore/Resources/mermaid.min.js（Markdown 里的 Mermaid 图用它画）。
#
# 从 npm 仓库下载固定版本的 mermaid 发布包，按 npm 记录的 sha512 校验，只取出单文件构建
# dist/mermaid.min.js（自带全部依赖，加载后是 globalThis.mermaid）。幂等，不需要 Node。
# 升级：改下面两行（integrity 取自 `npm view mermaid@<版本> dist.integrity`），再运行本脚本。
set -euo pipefail

MERMAID_VERSION="11.17.2"
MERMAID_INTEGRITY="sha512-V6K3C8EBdEsPFZXSKMJe6ppQOENxuHARr9GvHX4hh47lAbhMRD9qf4oEK7LoaRQxULMa80/qt5gHO73aCleBBg=="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT_DIR/Sources/PeekyCore/Resources/mermaid.min.js"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL="$WORK_DIR/mermaid.tgz"
curl --fail --silent --show-error --location \
  "https://registry.npmjs.org/mermaid/-/mermaid-$MERMAID_VERSION.tgz" -o "$TARBALL"

actual="sha512-$(openssl dgst -sha512 -binary "$TARBALL" | base64)"
if [[ "$actual" != "$MERMAID_INTEGRITY" ]]; then
  echo "mermaid-$MERMAID_VERSION.tgz 校验不符：期望 $MERMAID_INTEGRITY，实际 $actual" >&2
  exit 1
fi

tar -xzf "$TARBALL" -C "$WORK_DIR" package/dist/mermaid.min.js
cp "$WORK_DIR/package/dist/mermaid.min.js" "$OUTPUT"
echo "$OUTPUT ($(wc -c < "$OUTPUT" | tr -d ' ') bytes, mermaid $MERMAID_VERSION)"
