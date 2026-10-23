#!/usr/bin/env bash
# searxng-forge 一句话安装：把 skill 装进 zcode 的 skills 目录
# 远程: curl -fsSL https://raw.githubusercontent.com/<REPO>/main/install.sh | bash
# 本地: ./install.sh
set -eu

REPO="${SEARXNG_FORGE_REPO:-https://github.com/clickist/searxng-forge}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 目标目录：优先已存在的 agent 目录，否则 ~/.zcode/skills
if [ -d "$HOME/.zcode/skills" ]; then
  DEST="$HOME/.zcode/skills/searxng-forge"
elif [ -d "$HOME/.agents/skills" ]; then
  DEST="$HOME/.agents/skills/searxng-forge"
else
  DEST="$HOME/.zcode/skills/searxng-forge"
fi

if [ -f "$(dirname "$0")/skill/SKILL.md" ]; then
  # 本地模式
  SRC="$(cd "$(dirname "$0")" && pwd)"
  mkdir -p "$(dirname "$DEST")"
  cp -R "$SRC/skill" "$DEST"
else
  # 远程模式
  command -v git >/dev/null 2>&1 || { echo "需要 git，请先安装"; exit 1; }
  git clone --depth 1 "$REPO" "$TMP/repo"
  mkdir -p "$(dirname "$DEST")"
  cp -R "$TMP/repo/skill" "$DEST"
fi

echo "✓ searxng-forge 已安装到 $DEST"
echo
echo "开始使用：在你的 agent（zcode 等）里说——"
echo "  「帮我用 searxng-forge 在这台机器上部署并调优 SearXNG」"
