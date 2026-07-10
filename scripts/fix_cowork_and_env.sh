#!/bin/bash
# ==========================================
# 一键修复 Claude 与 Cowork 网络/签名协同补丁
# 支持 macOS, 解决安装损坏及大模型直连网关代理
# ==========================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 错误: 此脚本必须使用 sudo 管理员权限运行！"
  echo "请运行: sudo bash \"$0\""
  exit 1
fi

REAL_USER="${SUDO_USER:-mac}"
echo "=== 正在启动 Claude 与 Cowork 一键修复进程 ==="
echo "执行用户: $REAL_USER"

pkill -f Claude || true
sleep 1

BACKUP_APP=$(find /Applications -maxdepth 1 -name "Claude.backup-before-zh-CN-*.app" | head -n 1)

if [ -z "$BACKUP_APP" ]; then
  echo "❌ 错误: 未能在 /Applications 目录下找到 Claude.backup-before-zh-CN-*.app 官方原版备份包！"
  echo "请确保您之前成功运行过汉化包，并且该备份存在。"
  exit 1
fi
echo "✓ 找到官方原装备份: $BACKUP_APP"

echo "正在重置官方原版 Claude.app..."
rm -rf "/Applications/Claude.app"
cp -R "$BACKUP_APP" "/Applications/Claude.app"

ENT_PATH="/tmp/claude_cowork_entitlements.plist"
cat <<EOF > "$ENT_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	<key>com.apple.security.virtualization</key>
	<true/>
</dict>
</plist>
EOF

echo "正在为官方版注入本地 8045 网关代理环境变量..."
# Do NOT inject system http_proxy into Claude: it can break local 8045 health probes
# when Clash/mixed-port is down, causing false "provider rejected" toasts.
plutil -replace LSEnvironment -json '{"MallocNanoZone":"0","no_proxy":"127.0.0.1,localhost","NO_PROXY":"127.0.0.1,localhost","ANTHROPIC_BASE_URL":"http://127.0.0.1:8045","ANTHROPIC_API_KEY":"sk-8af1463d4a9f4297a7d656e5bfedcc9e"}' "/Applications/Claude.app/Contents/Info.plist"

echo "正在为官方版进行安全沙箱与虚拟化重签名..."
codesign --force --deep --sign - --options runtime --entitlements "$ENT_PATH" "/Applications/Claude.app"

ZH_PROJECT="/Users/mac/.claude-desktop-zh-cn"
if [ -d "$ZH_PROJECT" ]; then
  echo "发现本地汉化项目，正在编译独立中文版 Claude-CN.app..."
  rm -rf "/Applications/Claude-CN.app"
  cp -R "$BACKUP_APP" "/Applications/Claude-CN.app"
  python3 "$ZH_PROJECT/scripts/patch_claude_zh_cn.py" --app "/Applications/Claude-CN.app" --lang zh-CN --user-home "/Users/$REAL_USER"
  
  plutil -replace LSEnvironment -json '{"MallocNanoZone":"0","no_proxy":"127.0.0.1,localhost","NO_PROXY":"127.0.0.1,localhost","ANTHROPIC_BASE_URL":"http://127.0.0.1:8045","ANTHROPIC_API_KEY":"sk-8af1463d4a9f4297a7d656e5bfedcc9e"}' "/Applications/Claude-CN.app/Contents/Info.plist"
  codesign --force --deep --sign - --options runtime --entitlements "$ENT_PATH" "/Applications/Claude-CN.app"
else
  echo "⚠️ 提示: 未能找到汉化项目路径 $ZH_PROJECT，跳过中文版重编译。"
fi

echo "清理系统 Gatekeeper 缓存并修正所有权..."
xattr -cr "/Applications/Claude.app" || true
chown -R "$REAL_USER" "/Applications/Claude.app"

if [ -d "/Applications/Claude-CN.app" ]; then
  xattr -cr "/Applications/Claude-CN.app" || true
  chown -R "$REAL_USER" "/Applications/Claude-CN.app"
fi

rm -f "$ENT_PATH"

echo "==========================================="
echo "🎉 一键修复完成！所有应用均已恢复正常运行！"
echo "1. 原版 Claude.app -> 已激活 Cowork 沙箱，支持与 IDE 协同。"
echo "2. 中文版 Claude-CN.app -> 完美汉化，支持桌面端日常使用。"
echo "3. 网关连接 -> 均已完美注入直连 http://127.0.0.1:8045 网关代理。"
echo "==========================================="
