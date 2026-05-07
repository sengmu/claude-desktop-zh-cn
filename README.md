# Claude Desktop 中文补丁（zh-CN）

一个用于 Claude Desktop 的中文界面补丁。macOS 可双击 `install-mac.command`，Windows 可右键管理员运行 `install-windows.bat`，给 Claude Desktop 添加 `中文（中国）` 语言选项，并安装中文界面资源。

本汉化方案仅支持使用 API 的方式。请先参照 https://linux.do/t/topic/2032192 配置

## 功能特点

- 一键安装 Claude Desktop 中文界面资源，支持 macOS 和 Windows。
- 自动给 Claude 前端语言白名单加入 `zh-CN`。
- macOS 自动合并当前 Claude 版本的英文语言文件与随包中文翻译。
- 新版本新增但暂未翻译的字段会保留英文，避免界面缺失文本。
- macOS 和 Windows 自动绕过新版 Claude Desktop 对 3P gateway 模型名的本地 Anthropic 校验，避免 `deepseek-v4-pro` / `kimi-*` 等模型名导致配置整体失效。
- macOS 安装前自动备份原始 `/Applications/Claude.app`。
- 自动写入 Claude 用户配置，将语言设置为 `zh-CN`。

## 适用环境

- macOS 或 Windows
- 已安装 Claude Desktop
- macOS 需要系统自带 Python 3（通常路径为 `/usr/bin/python3`）
- Windows 需要 PowerShell，并建议以管理员权限运行

## 使用方式

### macOS

1. 退出 Claude Desktop。
2. 下载或克隆本项目。
3. 双击 `install-mac.command`。
4. 按提示输入 Mac 登录密码。
5. Claude 会自动重新打开。
6. 如果没有自动切换，打开左下角账号菜单，选择 `Language` -> `中文（中国）`。

也可以在终端运行：

```bash
cd /path/to/claude-desktop-zh-cn
sudo /usr/bin/python3 scripts/patch_claude_zh_cn.py --user-home "$HOME" --launch
```

### Windows

1. 退出 Claude Desktop。
2. 下载或克隆本项目。
3. 右键 `install-windows.bat`，选择以管理员身份运行。
4. 脚本会写入本仓库 `resources` 目录里的中文 JSON，补齐硬编码界面文本，修复 3P gateway 模型名校验，并重启 Claude Desktop。
5. 如果没有自动切换，打开左下角账号菜单，选择 `Language` -> `中文（中国）`。

也可以在 PowerShell 中运行：

```powershell
cd path\to\claude-desktop-zh-cn
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_windows.ps1 install
```

## 从 GitHub 下载

```bash
git clone https://github.com/<your-name>/claude-desktop-zh-cn.git
cd claude-desktop-zh-cn
./install-mac.command
```

如果 `install-mac.command` 无法双击运行，可以先执行：

```bash
chmod +x install-mac.command
./install-mac.command
```

## 文件说明

- `install-mac.command`：macOS 双击运行入口。
- `install-windows.bat`：Windows 双击 / 管理员运行入口。
- `scripts/install_windows.ps1`：Windows 汉化安装和卸载脚本。
- `scripts/patch_claude_zh_cn.py`：真正执行补丁的 Python 脚本。
- `resources/manifest.json`：语言包信息。
- `resources/frontend-zh-CN.json`：Claude 前端界面中文翻译。
- `resources/desktop-zh-CN.json`：Claude 桌面壳层中文翻译。
- `resources/Localizable.strings`：macOS 原生菜单中文资源。
- `resources/statsig-zh-CN.json`：statsig i18n 兜底资源。

## macOS 脚本会做什么

- 备份当前 `/Applications/Claude.app` 到同目录，名字类似：
  `Claude.backup-before-zh-CN-20260424-120000.app`
- 复制 Claude.app 到临时目录并打补丁。
- 给前端语言白名单加入 `zh-CN`。
- 对 `Contents/Resources/app.asar` 做等长补丁，关闭 3P gateway 启动阶段的 `inferenceModels` Anthropic 名称校验。
- 合并当前 Claude 版本的 `en-US.json` 和随包中文翻译：
  当前版本已有中文翻译的 key 会变中文，新版本新增但本包没有的 key 会保留英文，避免应用缺字段。
- 写入 `~/Library/Application Support/Claude/config.json`，设置 `"locale": "zh-CN"`。
- 对修改后的 Claude.app 及其内部 app/framework/原生二进制做一致的本机 ad-hoc 重签名，并清除 `com.apple.quarantine` 隔离属性。
- 重新启动 Claude。

## Windows 脚本会做什么

- 查找 Windows 版 Claude Desktop 安装目录。
- 修改前备份将被改动的前端 JS bundle、`app.asar` 和 `Claude.exe` 到 `resources\.zh-cn-backups`。
- 复制本仓库现有中文资源，不使用其他语言包项目里的 JSON：
  - `resources/frontend-zh-CN.json` -> `ion-dist\i18n\zh-CN.json`
  - `resources/desktop-zh-CN.json` -> `resources\zh-CN.json`
  - `resources/statsig-zh-CN.json` -> `ion-dist\i18n\statsig\zh-CN.json`
- 给前端语言白名单加入 `zh-CN`。
- 汉化前端 bundle 中未走 i18n JSON 的硬编码界面文本，例如侧边栏入口、配置页标签和模型选择项。
- 对 `resources\app.asar` 做等长补丁，关闭 3P gateway 启动阶段的 `inferenceModels` Anthropic 名称校验，并同步更新 asar 内部文件完整性信息和 `Claude.exe` 内嵌的 asar header hash。
- 写入 Windows 用户配置，将语言设置为 `zh-CN`。
- 重启 Claude Desktop。

## 注意

Claude Desktop 更新后可能会覆盖补丁，需要重新运行 `install-mac.command`。

Windows 版更新后也可能被覆盖，需要重新运行 `install-windows.bat`。

3P gateway 模型名校验补丁只解决启动阶段 `inferenceModels` 名称被拒的问题，不保证第三方模型完全兼容 Claude Desktop / Claude Code 的协议与工具调用行为。Claude Desktop 更新后如果内部 bundle 结构变化，脚本会停止并提示补丁失败，而不是猜测修改。

不要手动用十六进制编辑器或简单字符串替换直接修改 `app.asar`。Electron 会校验 asar header 里的文件完整性；macOS 还会校验 `Info.plist` 里的 `ElectronAsarIntegrity`，Windows 还会校验 `Claude.exe` 内嵌的 asar header hash。只改文件内容会导致启动时报 `ASAR Integrity Violation` 或直接崩溃。本脚本会同步更新这些完整性信息。

如果打开后 macOS 提示无法验证开发者或应用损坏，通常是因为 Claude Desktop 更新后，补丁修改资源文件导致原始签名失效。新版脚本会自动执行本机 ad-hoc 重签名、保留原 app 的 entitlements，并确保内部 app/framework 使用一致签名；如果你已经用旧版脚本打过补丁且遇到 `virtualization_entitlement_missing` / `Claude 的安装似乎已损坏`，请先恢复备份或重新安装官方 Claude.app，再重新运行 `install-mac.command`。

不要只手动运行单条 `codesign --deep` 命令修复当前应用。Claude.app 内部还有 Electron Framework、Helper app、`.node` 原生模块和动态库，单条命令容易造成主程序和内部 framework 的 Team ID 不一致，启动时会出现 `mapping process and mapped file ... have different Team IDs`。请重新运行 `install-mac.command`，让脚本按从内到外的顺序重签。

## 卸载 / 恢复

macOS 脚本安装前会在 `/Applications` 下生成备份，名称类似：

```text
Claude.backup-before-zh-CN-20260424-120000.app
```

如需恢复，可退出 Claude Desktop 后，将当前 `/Applications/Claude.app` 移走，再把备份 app 改名为 `Claude.app`。

Windows 脚本安装时会把被修改的前端 JS bundle、`app.asar` 和 `Claude.exe` 备份到 Claude 安装目录下的 `resources\.zh-cn-backups`。运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install_windows.ps1 uninstall
```

会优先恢复最近一次备份，再删除中文资源并把语言配置改回 `en-US`。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=javaht/claude-desktop-zh-cn&type=Date)](https://www.star-history.com/#javaht/claude-desktop-zh-cn&Date)

## 免责声明

本项目为非官方中文补丁，仅修改本机 Claude Desktop 的本地资源文件。Claude Desktop 更新后资源结构可能变化，若补丁失败，请先更新本项目或重新运行安装脚本。
