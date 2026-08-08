#!/usr/bin/env bash
# Auto Folo Wiki — 命令入口
# 用法：
#   ./scripts/docs.sh convert   （一次性）把 docs/agent_handoff 下的 .md 转换为 .html
#   ./scripts/docs.sh index     重新生成搜索索引（内容变更后运行）
#   ./scripts/docs.sh check     链接/锚点/敏感信息/索引一致性检查
#   ./scripts/docs.sh serve     可选：本地静态预览（python3 http.server，仅开发用）
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  convert)
    node scripts/convert-docs.js --root
    ;;
  index)
    node scripts/docs-index.js
    ;;
  check)
    node scripts/docs-check.js
    ;;
  serve)
    exec python3 -m http.server 8080 -d .
    ;;
  *)
    echo "用法: ./scripts/docs.sh {convert|index|check|serve}"
    exit 1
    ;;
esac
