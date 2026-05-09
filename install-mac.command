#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="/usr/bin/python3"
PATCHER="$DIR/scripts/patch_claude_zh_cn.py"

if [ ! -x "$PYTHON" ]; then
  PYTHON="$(command -v python3)"
fi

echo "Claude Desktop 中文补丁"
echo "目录: $DIR"
echo

# Language selection
if [ -z "${CLAUDE_LANG:-}" ]; then
  echo "请选择要安装的语言："
  echo "  [1] 简体中文"
  echo "  [2] 繁体中文（台湾）"
  echo "  [3] 繁体中文（香港）"
  echo
  read -rp "请输入选项 [1/2/3，默认 1]: " choice
  case "${choice:-1}" in
    2) LANG_CODE="zh-TW" ;;
    3) LANG_CODE="zh-HK" ;;
    *) LANG_CODE="zh-CN" ;;
  esac
  echo
else
  LANG_CODE="$CLAUDE_LANG"
fi

echo "选择的语言: $LANG_CODE"
echo

if [ "$(id -u)" -ne 0 ]; then
  echo "需要管理员权限来替换 /Applications/Claude.app。"
  echo "请按提示输入这台 Mac 的登录密码。"
  echo
  sudo "$PYTHON" "$PATCHER" --user-home "$HOME" --lang "$LANG_CODE" --launch "$@"
  STATUS=$?
  echo
  echo "按回车退出。"
  read -r _
  exit "$STATUS"
fi

USER_HOME="$HOME"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  USER_HOME="/Users/$SUDO_USER"
fi

"$PYTHON" "$PATCHER" --user-home "$USER_HOME" --lang "$LANG_CODE" --launch "$@"

echo
echo "完成。按回车退出。"
read -r _
