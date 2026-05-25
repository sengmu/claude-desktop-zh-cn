# Claude Desktop 中文补丁

一个用于 Claude Desktop 的中文界面汉化补丁，支持简体中文、繁体中文（中国台湾）和繁体中文（中国香港）。

macOS 可双击 `install-mac.command`，Windows 可右键管理员运行 `install-windows.bat`，给 Claude Desktop 添加中文语言选项，并安装中文界面资源。

本汉化方案仅支持使用 API 的方式。请先参照 https://linux.do/t/topic/2032192 配置。
如果脚本检测到第三方 API 配置目录为空，会在安装前询问是否继续配置。

## 界面截图

![Claude Desktop 中文界面截图](docs/images/claude-desktop-zh-cn-home.png) ![Claude Desktop 中文设置界面截图](docs/images/claude-desktop-zh-cn-settings.png)

<div align="center">

**遇到问题请及时反馈，欢迎扫码加入 claude desktop 交流。**

<img src="docs/images/wechat-groups.jpg" alt="claude desktop 交流群二维码" width="360">

</div>

## 功能特点

- 一键安装 Claude Desktop 中文界面资源，支持 macOS 和 Windows。
- 支持三种中文变体：`zh-CN`（简体中文）、`zh-TW`（繁体中文（中国台湾））、`zh-HK`（繁体中文（中国香港））。
- 自动给 Claude 前端语言白名单加入当前选择的中文变体。
- macOS 自动合并当前 Claude 版本的英文语言文件与随包中文翻译。
- 新版本新增但暂未翻译的字段会保留英文，避免界面缺失文本。
- macOS 和 Windows 自动绕过新版 Claude Desktop 对 3P gateway 模型名的本地 Anthropic 校验，避免 `deepseek-v4-pro` / `kimi-*` 等模型名导致配置整体失效。
- macOS 安装前自动备份原始 `/Applications/Claude.app`。
- 自动写入 Claude 用户配置，将语言设置为所选中文变体。

## 适用环境

- macOS 或 Windows
- 已安装 Claude Desktop
- macOS 需要系统自带 Python 3（通常路径为 `/usr/bin/python3`）
- Windows 需要 PowerShell，并建议以管理员权限运行

## 使用方式

### macOS

1. 退出 Claude Desktop。
2. 下载或克隆本项目。
3. 双击 `install-mac.command`，选择安装中文补丁、安全模式安装或恢复原样 / 卸载补丁。
4. 安装时选择要安装的语言（1=简体中文，2=繁体中文（中国台湾），3=繁体中文（中国香港））。安全模式同样支持三种中文，并跳过 `app.asar` 补丁。
5. 按提示输入 Mac 登录密码。
6. Claude 会自动重新打开。
7. 如果没有自动切换，打开左下角账号菜单，选择 `Language` -> 对应的中文选项。

### Windows

1. 退出 Claude Desktop。
2. 下载或克隆本项目。
3. 右键 `install-windows.bat`，选择以管理员身份运行。
4. 先选择安装模式：
   - `1` 安装中文补丁
   - `2` 安装中文补丁（安全模式，跳过 `app.asar` 补丁）
   - `3` 卸载补丁
5. 安装时再选择语言：
   - `1` 简体中文
   - `2` 繁体中文（中国台湾）
   - `3` 繁体中文（中国香港）
6. 脚本会写入本仓库 `resources` 目录里的中文 JSON，补齐硬编码界面文本；非安全模式会修复 3P gateway 模型名校验，并重启 Claude Desktop。
7. 如果没有自动切换，打开左下角账号菜单，选择 `Language` -> 对应的中文选项。


## 文件说明

- `install-mac.command`：macOS 双击运行入口。
- `install-windows.bat`：Windows 安装 / 恢复菜单入口。
- `scripts/install_windows.ps1`：Windows 汉化安装和卸载脚本。
- `scripts/patch_claude_zh_cn.py`：真正执行补丁的 Python 脚本。
- `resources/manifest.json` / `manifest-zh-TW.json` / `manifest-zh-HK.json`：语言包信息。
- `resources/frontend-zh-CN.json` / `frontend-zh-TW.json` / `frontend-zh-HK.json`：Claude 前端界面中文翻译。
- `resources/desktop-zh-CN.json` / `desktop-zh-TW.json` / `desktop-zh-HK.json`：Claude 桌面壳层中文翻译。
- `resources/Localizable.strings` / `Localizable-zh-TW.strings` / `Localizable-zh-HK.strings`：macOS 原生菜单中文资源。
- `resources/statsig-zh-CN.json` / `statsig-zh-TW.json` / `statsig-zh-HK.json`：statsig i18n 兜底资源。

## 卸载 / 恢复 

执行脚本，选择恢复即可。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=javaht/claude-desktop-zh-cn&type=Date)](https://www.star-history.com/#javaht/claude-desktop-zh-cn&Date)

## 免责声明

本项目为非官方中文补丁，仅修改本机 Claude Desktop 的本地资源文件。Claude Desktop 更新后资源结构可能变化，若补丁失败，请先更新本项目或重新运行安装脚本。
