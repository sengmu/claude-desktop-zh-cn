#!/bin/bash
echo "==========================================="
echo "       一键修复本地大模型网关与模型死锁"
echo "==========================================="

echo "1. 正在强制停止死锁或挂起的本地网关进程..."
pkill -f "Antigravity Tools"
pkill -f "antigravity_tools"

echo "2. 等待 5 秒以确保配置文件在磁盘上完全退出并死透落盘..."
sleep 5

echo "3. 正在重构加固并修复本地网关配置文件 (accounts.json & gui_config.json)..."
python3 -c '
import json
from pathlib import Path

# 1. 修复 accounts.json
acc_path = Path("/Users/mac/.antigravity_tools/accounts.json")
if acc_path.exists():
    with open(acc_path, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    for acc in data.get("accounts", []):
        email = acc.get("email")
        if email == "linguihong321@gmail.com":
            acc["disabled"] = True  # 禁用被谷歌 403 验证锁定的账号
            print("  [x] 已禁用谷歌验证拦截的账号: linguihong321@gmail.com")
        else:
            acc["disabled"] = False  # 正常健康账号全部启用
            acc["protected_models"] = [
                "gemini-3-pro-image",
                "gemini-3-pro-high",
                "gemini-3-flash",
                "claude"
            ]
            
    # 将活跃账号锁定为 linguihong000@gmail.com (拥有 26.7% 最充足 Gemini 额度)
    data["current_account_id"] = "a7b3c061-5b4f-458a-b2fa-90a323e22ec9"
    with open(acc_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("  [+] accounts.json 账户索引与配额支持列表已重构。")

# 2. 修复 gui_config.json
cfg_path = Path("/Users/mac/.antigravity_tools/gui_config.json")
if cfg_path.exists():
    with open(cfg_path, "r", encoding="utf-8") as f:
        cfg_data = json.load(f)
        
    mapping = cfg_data.setdefault("proxy", {}).setdefault("custom_mapping", {})
    
    # 注入重定向别名映射：强行将各种 Claude 请求无缝转换成健康的 Gemini 专线
    mapping["claude-haiku-4"] = "gemini-3-flash"
    mapping["claude-sonnet-4-5"] = "gemini-3-pro-high"
    mapping["claude-opus-4-6"] = "gemini-3-pro-high"
    mapping["claude-4"] = "gemini-3-pro-high"
    mapping["claude-3-5-haiku"] = "gemini-3-flash"
    mapping["claude-3-5-haiku-20241022"] = "gemini-3-flash"
    mapping["claude-3-haiku-20240307"] = "gemini-3-flash"
    mapping["claude-3-5-sonnet-latest"] = "gemini-3-pro-high"
    mapping["claude-3-5-sonnet"] = "gemini-3-pro-high"
    mapping["claude-3-5-sonnet-20241022"] = "gemini-3-pro-high"
    mapping["claude"] = "gemini-3-flash"
    mapping["Claude"] = "gemini-3-flash"
    
    cfg_data["proxy"]["port"] = 8045
    cfg_data["proxy"]["enabled"] = True
    
    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(cfg_data, f, ensure_ascii=False, indent=2)
    print("  [+] gui_config.json 别名透明重路由规则已重置。")
'

echo "4. 正在注入全局网络代理并冷拉起本地大模型反代网关..."
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export all_proxy=socks5://127.0.0.1:7897
export no_proxy="127.0.0.1,localhost"
export NO_PROXY="127.0.0.1,localhost"
export ANTHROPIC_BASE_URL="http://127.0.0.1:8045"
export ANTHROPIC_API_KEY="sk-8af1463d4a9f4297a7d656e5bfedcc9e"

nohup "/Applications/Antigravity Tools.app/Contents/MacOS/antigravity_tools" > /tmp/antigravity_tools.log 2>&1 &

echo "5. 正在等待 8 秒让网关在后台完成首次账户刷新校验..."
sleep 8

echo "==========================================="
echo "🎉 修复成功！配置已刷新，请打开 Claude 发起对话测试！"
echo "==========================================="
