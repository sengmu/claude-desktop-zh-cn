param(
    [Parameter(Position = 0)]
    [ValidateSet("install", "uninstall")]
    [string]$Action = "install",

    [Parameter(Position = 1)]
    [ValidateSet("zh-CN", "zh-TW", "zh-HK")]
    [string]$Language = "zh-CN"
)

$ErrorActionPreference = "Stop"
$LanguageCode = $Language
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$LanguageListPattern = '\["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID"\]'
$LanguageListReplacement = '["en-US","de-DE","fr-FR","ko-KR","ja-JP","es-419","es-ES","it-IT","hi-IN","pt-BR","id-ID","zh-CN","zh-TW","zh-HK"]'
$AsarPatchTarget = ".vite/build/index.js"
$AsarIntegrityBlockSize = 4 * 1024 * 1024
$script:CurrentBackupSetPath = $null

function Get-LanguageLabel {
    param([string]$Code)
    switch ($Code) {
        "zh-CN" { return "简体中文" }
        "zh-TW" { return "繁体中文（台湾）" }
        "zh-HK" { return "繁体中文（香港）" }
        default { return $Code }
    }
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
}

function Find-ClaudePath {
    $packages = @(Get-AppxPackage -Name "Claude" -ErrorAction SilentlyContinue)
    foreach ($package in $packages) {
        if ($package.InstallLocation -and (Test-Path $package.InstallLocation)) {
            return $package.InstallLocation
        }
    }

    $fallback = Get-ChildItem "C:\Program Files\WindowsApps\Claude_*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($fallback) {
        return $fallback.FullName
    }

    return $null
}

function Get-ClaudeResourcesPath {
    $claudePath = Find-ClaudePath
    if (-not $claudePath) {
        throw "未找到 Claude Desktop 安装。"
    }

    $resourcesPath = Join-Path $claudePath "app\resources"
    if (-not (Test-Path $resourcesPath)) {
        throw "未找到 Claude resources 目录: $resourcesPath"
    }

    return @{
        App = $claudePath
        Resources = $resourcesPath
    }
}

function Grant-WriteAccess {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return
    }

    try {
        $acl = Get-Acl $Path
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $identity,
            "FullControl",
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl $Path $acl -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  [警告] 无法更新权限: $Path" -ForegroundColor DarkYellow
    }
}

function Require-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "缺少必要文件: $Path"
    }
}

function Get-BackupRoot {
    param([string]$ResourcesPath)
    return Join-Path $ResourcesPath ".zh-cn-backups"
}

function Get-ClaudeAppPathFromResources {
    param([string]$ResourcesPath)
    return Split-Path -Parent $ResourcesPath
}

function New-BackupSet {
    param([string]$ResourcesPath)

    if ($script:CurrentBackupSetPath -and (Test-Path $script:CurrentBackupSetPath)) {
        return $script:CurrentBackupSetPath
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $root = Get-BackupRoot $ResourcesPath
    $path = Join-Path $root $stamp
    $suffix = 0
    while (Test-Path $path) {
        $suffix += 1
        $path = Join-Path $root "$stamp-$suffix"
    }

    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $script:CurrentBackupSetPath = $path
    Write-Host "  backup set: $path" -ForegroundColor DarkGray
    return $path
}

function Get-RelativeResourcePath {
    param(
        [string]$ResourcesPath,
        [string]$FilePath
    )

    $root = [System.IO.Path]::GetFullPath($ResourcesPath).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($FilePath)
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "备份目标不在 Claude resources 目录内: $FilePath"
    }

    return $full.Substring($root.Length).TrimStart('\', '/')
}

function Backup-ModifiedFile {
    param(
        [string]$ResourcesPath,
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        return
    }

    $backupSet = New-BackupSet $ResourcesPath
    $relative = Get-RelativeResourcePath $ResourcesPath $FilePath
    $target = Join-Path $backupSet $relative
    if (Test-Path $target) {
        return
    }

    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item $FilePath $target -Force
    Write-Host "  backed up: $relative" -ForegroundColor DarkGray
}

function Backup-AppFile {
    param(
        [string]$ResourcesPath,
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        return
    }

    $appPath = Get-ClaudeAppPathFromResources $ResourcesPath
    $appRoot = [System.IO.Path]::GetFullPath($appPath).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($FilePath)
    if (-not $full.StartsWith($appRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "备份目标不在 Claude app 目录内: $FilePath"
    }

    $backupSet = New-BackupSet $ResourcesPath
    $relative = $full.Substring($appRoot.Length).TrimStart('\', '/')
    $target = Join-Path $backupSet (Join-Path "_app" $relative)
    if (Test-Path $target) {
        return
    }

    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item $FilePath $target -Force
    Write-Host "  backed up: app\$relative" -ForegroundColor DarkGray
}

function Restore-LatestBackup {
    param([string]$ResourcesPath)

    $root = Get-BackupRoot $ResourcesPath
    if (-not (Test-Path $root)) {
        Write-Host "  no zh-CN backup found; skipping bundle restore" -ForegroundColor DarkYellow
        return
    }

    $backup = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $backup) {
        Write-Host "  no zh-CN backup found; skipping bundle restore" -ForegroundColor DarkYellow
        return
    }

    $backupRoot = $backup.FullName.TrimEnd('\', '/')
    $files = @(Get-ChildItem $backup.FullName -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($backupRoot.Length).TrimStart('\', '/')
        if ($relative.StartsWith("_app\", [System.StringComparison]::OrdinalIgnoreCase)) {
            $appPath = Get-ClaudeAppPathFromResources $ResourcesPath
            $target = Join-Path $appPath $relative.Substring(5)
        }
        else {
            $target = Join-Path $ResourcesPath $relative
        }
        $parent = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Copy-Item $file.FullName $target -Force
        Write-Host "  restored: $relative" -ForegroundColor Green
    }
}

function Get-LanguageResources {
    param([string]$Lang)

    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $projectDir = Split-Path -Parent $scriptDir
    $resourcesDir = Join-Path $projectDir "resources"
    $resources = @{
        Frontend = Join-Path $resourcesDir "frontend-$Lang.json"
        Desktop = Join-Path $resourcesDir "desktop-$Lang.json"
        Statsig = Join-Path $resourcesDir "statsig-$Lang.json"
    }

    foreach ($path in $resources.Values) {
        Require-File $path
    }

    return $resources
}

function Enable-WriteAccess {
    param([string]$ResourcesPath)

    $paths = @(
        (Get-ClaudeAppPathFromResources $ResourcesPath),
        $ResourcesPath,
        (Join-Path $ResourcesPath "ion-dist"),
        (Join-Path $ResourcesPath "ion-dist\i18n"),
        (Join-Path $ResourcesPath "ion-dist\i18n\statsig"),
        (Join-Path $ResourcesPath "ion-dist\assets"),
        (Join-Path $ResourcesPath "ion-dist\assets\v1")
    )

    foreach ($path in $paths) {
        Grant-WriteAccess $path
    }
}

function Install-LanguageFiles {
    param(
        [string]$ResourcesPath,
        [hashtable]$Pack,
        [string]$Lang
    )

    $i18nDir = Join-Path $ResourcesPath "ion-dist\i18n"
    $statsigDir = Join-Path $i18nDir "statsig"
    New-Item -ItemType Directory -Path $i18nDir -Force | Out-Null
    New-Item -ItemType Directory -Path $statsigDir -Force | Out-Null

    Copy-Item $Pack["Frontend"] (Join-Path $i18nDir "$Lang.json") -Force
    Write-Host "  installed ion-dist/i18n/$Lang.json" -ForegroundColor Green

    Copy-Item $Pack["Desktop"] (Join-Path $ResourcesPath "$Lang.json") -Force
    Write-Host "  installed resources/$Lang.json" -ForegroundColor Green

    Copy-Item $Pack["Statsig"] (Join-Path $statsigDir "$Lang.json") -Force
    Write-Host "  installed ion-dist/i18n/statsig/$Lang.json" -ForegroundColor Green
}

function Align-4 {
    param([int]$Value)
    return $Value + ((4 - ($Value % 4)) % 4)
}

function Get-UInt32LE {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )
    return [System.BitConverter]::ToUInt32($Bytes, $Offset)
}

function Get-Int32LE {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )
    return [System.BitConverter]::ToInt32($Bytes, $Offset)
}

function Read-AsarHeader {
    param(
        [byte[]]$Data,
        [string]$Path
    )

    if ($Data.Length -lt 16) {
        throw "Unsupported app.asar header in $Path"
    }

    $sizePicklePayload = Get-UInt32LE $Data 0
    $headerSize = Get-UInt32LE $Data 4
    if (($sizePicklePayload -ne 4) -or ($headerSize -le 0) -or ($Data.Length -lt (8 + $headerSize))) {
        throw "Unsupported app.asar size pickle in $Path"
    }

    $headerPickle = [byte[]]::new($headerSize)
    [System.Array]::Copy($Data, 8, $headerPickle, 0, $headerSize)
    $headerPayloadSize = Get-UInt32LE $headerPickle 0
    $headerStringSize = Get-Int32LE $headerPickle 4
    $expectedPayloadSize = Align-4 (4 + $headerStringSize)
    if (($headerPayloadSize -ne $expectedPayloadSize) -or ($headerSize -ne (4 + $headerPayloadSize))) {
        throw "Unsupported app.asar header pickle in $Path"
    }

    $headerBytes = [byte[]]::new($headerStringSize)
    [System.Array]::Copy($headerPickle, 8, $headerBytes, 0, $headerStringSize)
    $headerString = [System.Text.Encoding]::UTF8.GetString($headerBytes)
    $header = $headerString | ConvertFrom-Json
    return @{
        HeaderSize = [int]$headerSize
        HeaderString = $headerString
        Header = $header
    }
}

function Encode-AsarHeader {
    param(
        [string]$HeaderString,
        [int]$ExpectedHeaderSize
    )

    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($HeaderString)
    $headerPayloadSize = Align-4 (4 + $headerBytes.Length)
    if ((4 + $headerPayloadSize) -ne $ExpectedHeaderSize) {
        throw "app.asar header length changed; refusing to write an unsafe patch."
    }

    $headerPickle = [byte[]]::new($ExpectedHeaderSize)
    [System.Array]::Copy([System.BitConverter]::GetBytes([uint32]$headerPayloadSize), 0, $headerPickle, 0, 4)
    [System.Array]::Copy([System.BitConverter]::GetBytes([int32]$headerBytes.Length), 0, $headerPickle, 4, 4)
    [System.Array]::Copy($headerBytes, 0, $headerPickle, 8, $headerBytes.Length)

    $encoded = [byte[]]::new(8 + $ExpectedHeaderSize)
    [System.Array]::Copy([System.BitConverter]::GetBytes([uint32]4), 0, $encoded, 0, 4)
    [System.Array]::Copy([System.BitConverter]::GetBytes([uint32]$ExpectedHeaderSize), 0, $encoded, 4, 4)
    [System.Array]::Copy($headerPickle, 0, $encoded, 8, $ExpectedHeaderSize)
    return $encoded
}

function Get-AsarFileEntry {
    param(
        [object]$Header,
        [string]$FilePath
    )

    $node = $Header
    foreach ($part in $FilePath.Split('/')) {
        $filesProperty = $node.PSObject.Properties["files"]
        if (-not $filesProperty) {
            throw "Could not find $FilePath in app.asar header."
        }

        $childProperty = $filesProperty.Value.PSObject.Properties[$part]
        if (-not $childProperty) {
            throw "Could not find $FilePath in app.asar header."
        }

        $node = $childProperty.Value
    }

    foreach ($key in @("size", "offset", "integrity")) {
        if (-not $node.PSObject.Properties[$key]) {
            throw "Missing $key for $FilePath in app.asar header."
        }
    }

    return $node
}

function Find-BytePattern {
    param(
        [byte[]]$Data,
        [byte[]]$Pattern
    )

    $matches = New-Object System.Collections.Generic.List[int]
    if (($Pattern.Length -eq 0) -or ($Data.Length -lt $Pattern.Length)) {
        return $matches
    }

    for ($i = 0; $i -le ($Data.Length - $Pattern.Length); $i++) {
        $found = $true
        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($Data[$i + $j] -ne $Pattern[$j]) {
                $found = $false
                break
            }
        }
        if ($found) {
            $matches.Add($i)
        }
    }

    return $matches
}

function Find-Custom3PValidationToggle {
    param(
        [byte[]]$Content,
        [string]$ExprText
    )

    $contentText = [System.Text.Encoding]::ASCII.GetString($Content)
    $pattern = 'const ([A-Za-z_$][A-Za-z0-9_$]*)=' + [regex]::Escape($ExprText) + '\|\|!1,([A-Za-z_$][A-Za-z0-9_$]*)='
    $validMatches = New-Object System.Collections.Generic.List[object]

    foreach ($match in [regex]::Matches($contentText, $pattern)) {
        $flagName = $match.Groups[1].Value
        $windowLength = [Math]::Min(2500, $contentText.Length - $match.Index)
        $validationWindow = $contentText.Substring($match.Index, $windowLength)
        if (
            $validationWindow.Contains(('if(!' + $flagName + ')return{ok:!0}')) -and
            $validationWindow.Contains('expected a gateway model route referencing an Anthropic model') -and
            $validationWindow.Contains('Bedrock model')
        ) {
            $validMatches.Add($match)
        }
    }

    if ($validMatches.Count -gt 1) {
        throw "Could not patch custom 3P model validation: multiple matching toggles found."
    }
    if ($validMatches.Count -eq 1) {
        return $validMatches[0]
    }
    return $null
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256HexRange {
    param(
        [byte[]]$Bytes,
        [int]$Offset,
        [int]$Count
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes, $Offset, $Count)
        return ([System.BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-AsarFileIntegrity {
    param([byte[]]$Data)

    $blocks = New-Object System.Collections.Generic.List[string]
    if ($Data.Length -eq 0) {
        $blocks.Add((Get-Sha256Hex $Data))
    }
    else {
        for ($offset = 0; $offset -lt $Data.Length; $offset += $AsarIntegrityBlockSize) {
            $count = [Math]::Min($AsarIntegrityBlockSize, $Data.Length - $offset)
            $blocks.Add((Get-Sha256HexRange $Data $offset $count))
        }
    }

    return [pscustomobject][ordered]@{
        algorithm = "SHA256"
        hash = Get-Sha256Hex $Data
        blockSize = $AsarIntegrityBlockSize
        blocks = $blocks.ToArray()
    }
}

function Get-AsarHeaderHash {
    param([string]$AsarPath)

    Require-File $AsarPath
    $data = [System.IO.File]::ReadAllBytes($AsarPath)
    $parsed = Read-AsarHeader $data $AsarPath
    return Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($parsed["HeaderString"]))
}

function Sync-ClaudeExeAsarIntegrity {
    param([string]$ResourcesPath)

    $appPath = Get-ClaudeAppPathFromResources $ResourcesPath
    $exePath = Join-Path $appPath "Claude.exe"
    if (-not (Test-Path $exePath)) {
        $exePath = Join-Path $appPath "claude.exe"
    }
    Require-File $exePath

    $asarPath = Join-Path $ResourcesPath "app.asar"
    $headerHash = Get-AsarHeaderHash $asarPath
    $marker = [System.Text.Encoding]::ASCII.GetBytes('resources\\app.asar","alg":"SHA256","value":"')
    $exeBytes = [System.IO.File]::ReadAllBytes($exePath)
    $matches = Find-BytePattern $exeBytes $marker
    if ($matches.Count -ne 1) {
        throw "Could not find Claude.exe app.asar integrity marker. Claude bundle format may have changed."
    }

    $hashOffset = $matches[0] + $marker.Length
    if (($hashOffset + 64) -gt $exeBytes.Length) {
        throw "Claude.exe app.asar integrity marker has invalid bounds."
    }

    $currentHash = [System.Text.Encoding]::ASCII.GetString($exeBytes, $hashOffset, 64)
    if ($currentHash -eq $headerHash) {
        Write-Host "  Claude.exe app.asar integrity already matches" -ForegroundColor Green
        return
    }
    if ($currentHash -notmatch '^[0-9a-fA-F]{64}$') {
        throw "Claude.exe app.asar integrity value is not a SHA256 hex string."
    }

    Backup-AppFile $ResourcesPath $exePath
    $newHashBytes = [System.Text.Encoding]::ASCII.GetBytes($headerHash)
    [System.Array]::Copy($newHashBytes, 0, $exeBytes, $hashOffset, $newHashBytes.Length)
    [System.IO.File]::WriteAllBytes($exePath, $exeBytes)
    Write-Host "  updated Claude.exe app.asar integrity: $currentHash -> $headerHash" -ForegroundColor Green
}

function Register-Language {
    param([string]$ResourcesPath)

    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    $jsFiles = @(Get-ChildItem (Join-Path $assetsDir "index-*.js") -ErrorAction SilentlyContinue)
    if ($jsFiles.Count -eq 0) {
        throw "未找到前端 index-*.js: $assetsDir"
    }

    $regex = [System.Text.RegularExpressions.Regex]::new($LanguageListPattern)
    $changed = 0
    $already = 0
    foreach ($file in $jsFiles) {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        if ($text.Contains('"zh-CN"') -and $text.Contains('"zh-TW"') -and $text.Contains('"zh-HK"')) {
            Write-Host "  all Chinese variants already registered: $($file.Name)" -ForegroundColor Green
            $already += 1
            continue
        }

        if ($regex.IsMatch($text)) {
            $updated = $regex.Replace($text, $LanguageListReplacement, 1)
            Backup-ModifiedFile $ResourcesPath $file.FullName
            [System.IO.File]::WriteAllText($file.FullName, $updated, $Utf8NoBom)
            Write-Host "  patched language whitelist: $($file.Name)" -ForegroundColor Green
            $changed += 1
        }
    }

    if (($changed + $already) -eq 0) {
        throw "未能注册中文语言，Claude 前端 bundle 格式可能已经变化。"
    }
}

function Unregister-Language {
    param([string]$ResourcesPath)

    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    $jsFiles = @(Get-ChildItem (Join-Path $assetsDir "index-*.js") -ErrorAction SilentlyContinue)
    foreach ($file in $jsFiles) {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $updated = $text
        $changed = $false
        foreach ($lang in @(',"zh-CN"', ',"zh-TW"', ',"zh-HK"')) {
            if ($updated.Contains($lang)) {
                $updated = $updated.Replace($lang, '')
                $changed = $true
            }
        }
        if ($changed) {
            [System.IO.File]::WriteAllText($file.FullName, $updated, $Utf8NoBom)
            Write-Host "  removed language whitelist entries: $($file.Name)" -ForegroundColor Green
        }
    }
}

function Patch-HardcodedFrontendStrings {
    param([string]$ResourcesPath)

    $assetsDir = Join-Path $ResourcesPath "ion-dist\assets\v1"
    $jsFiles = @(Get-ChildItem (Join-Path $assetsDir "*.js") -ErrorAction SilentlyContinue)
    if ($jsFiles.Count -eq 0) {
        throw "未找到前端 JS bundle: $assetsDir"
    }

    $replacements = @(
        @('"New task"', '"新建任务"'),
        @('"New session"', '"新会话"'),
        @('"New chat"', '"新建聊天"'),
        @('"Pinned"', '"已固定"'),
        @('"Recents"', '"最近使用"'),
        @('"View all"', '"查看全部"'),
        @('"Search"', '"搜索"'),
        @('"代码"', '"Code"'),
        @('"Legacy Model"', '"旧版模型"'),
        @('"Drag to pin"', '"拖到此处固定"'),
        @('"Drop here"', '"拖到此处"'),
        @('"Let go"', '"松开"'),
        @('label:"Projects"', 'label:"项目"'),
        @('label:"Scheduled"', 'label:"计划任务"'),
        @('label:"Customize"', 'label:"自定义"'),
        @('title:"Connection"', 'title:"连接"'),
        @('description:"Choose where Claude Desktop sends inference requests."', 'description:"选择 Claude Desktop 发送推理请求的位置。"'),
        @('title:"Sandbox & workspace"', 'title:"沙盒与工作区"'),
        @('title:"Connectors & extensions"', 'title:"连接器与扩展"'),
        @('title:"Telemetry & updates"', 'title:"遥测与更新"'),
        @('title:"Usage limits"', 'title:"使用限制"'),
        @('title:"Plugins & skills"', 'title:"插件与技能"'),
        @('title:"Egress Requirements"', 'title:"出站要求"'),
        @('label:"macOS configuration profile"', 'label:"macOS 配置描述文件"'),
        @('label:"Windows registry file"', 'label:"Windows 注册表文件"'),
        @('label:"Plain JSON"', 'label:"纯 JSON"'),
        @('label:"Firewall allowlist (.txt)"', 'label:"防火墙允许列表（.txt）"'),
        @('label:"Copy to clipboard (redacted)"', 'label:"复制到剪贴板（已脱敏）"'),
        @('title:"Source"', 'title:"来源"'),
        @('group:"Identity & models"', 'group:"身份与模型"'),
        @('label:"Model ID"', 'label:"模型 ID"'),
        @('label:"Offer 1M-context variant"', 'label:"提供 1M 上下文变体"'),
        @('title:"Skip login-mode chooser"', 'title:"启动时跳过登录方式选择"'),
        @('title:"Gateway base URL"', 'title:"网关基础 URL"'),
        @('description:"Full URL of the inference gateway endpoint."', 'description:"推理网关端点的完整地址。"'),
        @('title:"Gateway API key"', 'title:"网关 API 密钥"'),
        @('title:"Gateway auth scheme"', 'title:"网关认证方案"'),
        @('title:"Gateway extra headers"', 'title:"网关额外请求头"'),
        @('description:"Extra HTTP headers sent on every inference request. JSON array of ''Name: Value'' strings."', 'description:"每次推理请求都会附带的额外 HTTP 请求头。格式为“名称: 值”字符串组成的 JSON 数组。"'),
        @('title:"Inference provider"', 'title:"推理提供商"'),
        @('description:"Selects the inference backend. Setting this key activates third-party mode."', 'description:"选择推理后端。设置此项会启用第三方模式。"'),
        @('title:"GCP project ID"', 'title:"GCP 项目 ID"'),
        @('title:"GCP region"', 'title:"GCP 区域"'),
        @('title:"GCP credentials file path"', 'title:"GCP 凭据文件路径"'),
        @('title:"Vertex OAuth client ID"', 'title:"Vertex OAuth 客户端 ID"'),
        @('title:"Vertex OAuth client secret"', 'title:"Vertex OAuth 客户端密钥"'),
        @('title:"Vertex OAuth scopes"', 'title:"Vertex OAuth 范围"'),
        @('title:"Vertex AI base URL"', 'title:"Vertex AI 基础 URL"'),
        @('title:"AWS region"', 'title:"AWS 区域"'),
        @('title:"AWS bearer token"', 'title:"AWS Bearer 令牌"'),
        @('title:"Bedrock base URL"', 'title:"Bedrock 基础 URL"'),
        @('title:"AWS profile name"', 'title:"AWS 配置文件名称"'),
        @('title:"AWS config directory"', 'title:"AWS 配置目录"'),
        @('title:"Bedrock service tier"', 'title:"Bedrock 服务层级"'),
        @('title:"Azure AI Foundry resource name"', 'title:"Azure AI Foundry 资源名称"'),
        @('title:"Azure AI Foundry API key"', 'title:"Azure AI Foundry API 密钥"'),
        @('title:"Model list"', 'title:"模型列表"'),
        @('title:"Managed MCP servers"', 'title:"托管的 MCP 服务器"'),
        @('title:"Organization UUID"', 'title:"组织 UUID"'),
        @('title:"Credential helper script"', 'title:"凭据辅助脚本"'),
        @('description:"Absolute path to an executable that prints the inference credential to stdout. When set, the static inferenceGatewayApiKey / inferenceFoundryApiKey is optional."', 'description:"可执行文件的绝对路径，该文件会将推理凭据输出到标准输出。设置后，可不填写静态 inferenceGatewayApiKey / inferenceFoundryApiKey。"'),
        @('hint:"Absolute path to an executable that prints the credential."', 'hint:"输出凭据的可执行文件绝对路径。"'),
        @('title:"Credential helper TTL"', 'title:"凭据辅助脚本 TTL"'),
        @('description:"Helper output is cached for this many seconds. Default 3600. Re-runs at the next session start after expiry."', 'description:"辅助脚本输出缓存的秒数。默认 3600。过期后会在下一次会话开始时重新运行。"'),
        @('title:"Allow desktop extensions"', 'title:"允许桌面扩展"'),
        @('description:"Permit users to install local desktop extensions (.dxt/.mcpb)."', 'description:"允许用户安装本地桌面扩展（.dxt/.mcpb）。"'),
        @('group:"Extensions"', 'group:"扩展"'),
        @('group:"MCP servers"', 'group:"MCP 服务器"'),
        @('group:"Anthropic telemetry"', 'group:"Anthropic 遥测"'),
        @('label:"Name"', 'label:"名称"'),
        @('label:"Transport"', 'label:"传输方式"'),
        @('label:"Headers"', 'label:"请求头"'),
        @('label:"Headers helper script"', 'label:"请求头辅助脚本"'),
        @('label:"Helper cache TTL (sec)"', 'label:"辅助缓存 TTL（秒）"'),
        @('placeholder:"Absolute path"', 'placeholder:"绝对路径"')
    )

    $patchedFiles = 0
    $patchedStrings = 0
    foreach ($file in $jsFiles) {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $patched = $text
        $count = 0
        foreach ($pair in $replacements) {
            $source = $pair[0]
            $target = $pair[1]
            if ($patched.Contains($source)) {
                $patched = $patched.Replace($source, $target)
                $count += 1
            }
        }

        if ($patched -ne $text) {
            Backup-ModifiedFile $ResourcesPath $file.FullName
            [System.IO.File]::WriteAllText($file.FullName, $patched, $Utf8NoBom)
            $patchedFiles += 1
            $patchedStrings += $count
        }
    }

    Write-Host "  patched hardcoded frontend strings: $patchedStrings replacements in $patchedFiles files" -ForegroundColor Green
}

function Patch-Custom3PModelValidation {
    param([string]$ResourcesPath)

    $asarPath = Join-Path $ResourcesPath "app.asar"
    Require-File $asarPath

    $oldExpr = [System.Text.Encoding]::ASCII.GetBytes('process.env.NODE_ENV!=="production"')
    $newExprText = "false".PadRight($oldExpr.Length, " ")

    $data = [System.IO.File]::ReadAllBytes($asarPath)
    $parsed = Read-AsarHeader $data $asarPath
    $headerSize = $parsed["HeaderSize"]
    $header = $parsed["Header"]
    $entry = Get-AsarFileEntry $header $AsarPatchTarget

    $contentOffset = [int64](8 + $headerSize + [int64]$entry.offset)
    $contentSize = [int64]$entry.size
    $contentEnd = $contentOffset + $contentSize
    if (($contentOffset -lt 0) -or ($contentEnd -gt $data.Length)) {
        throw "Unsupported app.asar file bounds for $AsarPatchTarget."
    }

    $content = [byte[]]::new([int]$contentSize)
    [System.Array]::Copy($data, [int]$contentOffset, $content, 0, [int]$contentSize)
    $match = Find-Custom3PValidationToggle $content 'process.env.NODE_ENV!=="production"'
    if ($null -eq $match) {
        $patchedMatch = Find-Custom3PValidationToggle $content $newExprText
        if ($null -ne $patchedMatch) {
            Write-Host "  custom 3P model-name validation already patched" -ForegroundColor Green
            Sync-ClaudeExeAsarIntegrity $ResourcesPath
            return
        }
        throw "Could not patch custom 3P model validation. Claude bundle format may have changed."
    }

    Backup-ModifiedFile $ResourcesPath $asarPath
    $anchorText = $match.Value
    $patchedAnchorText = 'const ' + $match.Groups[1].Value + '=' + $newExprText + '||!1,' + $match.Groups[2].Value + '='
    $anchor = [System.Text.Encoding]::ASCII.GetBytes($anchorText)
    $patchedAnchor = [System.Text.Encoding]::ASCII.GetBytes($patchedAnchorText)
    if ($anchor.Length -ne $patchedAnchor.Length) {
        throw "Internal patch error: custom 3P validation replacement changed length."
    }

    $matchOffset = $match.Index
    [System.Array]::Copy($patchedAnchor, 0, $content, $matchOffset, $patchedAnchor.Length)
    [System.Array]::Copy($content, 0, $data, [int]$contentOffset, $content.Length)

    $entry.integrity = Get-AsarFileIntegrity $content
    $updatedHeaderString = $header | ConvertTo-Json -Compress -Depth 100
    $updatedHeader = Encode-AsarHeader $updatedHeaderString $headerSize
    [System.Array]::Copy($updatedHeader, 0, $data, 0, $updatedHeader.Length)

    [System.IO.File]::WriteAllBytes($asarPath, $data)
    Sync-ClaudeExeAsarIntegrity $ResourcesPath
    Write-Host "  patched custom 3P model-name validation in app.asar" -ForegroundColor Green
}

function Set-ClaudeLocale {
    param([string]$Locale)

    if (-not $env:LOCALAPPDATA) {
        Write-Host "  [警告] LOCALAPPDATA 未设置，跳过用户配置。" -ForegroundColor DarkYellow
        return
    }

    $configPaths = @(
        (Join-Path $env:LOCALAPPDATA "Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\config.json"),
        (Join-Path $env:LOCALAPPDATA "Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude-3p\config.json")
    )

    foreach ($configPath in $configPaths) {
        $parent = Split-Path -Parent $configPath
        New-Item -ItemType Directory -Path $parent -Force | Out-Null

        $config = [pscustomobject]@{}
        if (Test-Path $configPath) {
            try {
                $loaded = Get-Content $configPath -Raw | ConvertFrom-Json
                if ($loaded) {
                    $config = $loaded
                }
            }
            catch {
                $backup = "$configPath.bak-invalid"
                Copy-Item $configPath $backup -Force
                Write-Host "  invalid JSON backed up: $backup" -ForegroundColor DarkYellow
            }
        }

        $config | Add-Member -NotePropertyName "locale" -NotePropertyValue $Locale -Force
        $config | ConvertTo-Json -Depth 20 | Set-Content $configPath -Encoding UTF8
        Write-Host "  locale=${Locale}: $configPath" -ForegroundColor Green
    }
}

function Remove-LanguageFiles {
    param([string]$ResourcesPath)

    $targets = @(
        (Join-Path $ResourcesPath "ion-dist\i18n\zh-CN.json"),
        (Join-Path $ResourcesPath "zh-CN.json"),
        (Join-Path $ResourcesPath "ion-dist\i18n\statsig\zh-CN.json"),
        (Join-Path $ResourcesPath "ion-dist\i18n\zh-TW.json"),
        (Join-Path $ResourcesPath "zh-TW.json"),
        (Join-Path $ResourcesPath "ion-dist\i18n\statsig\zh-TW.json"),
        (Join-Path $ResourcesPath "ion-dist\i18n\zh-HK.json"),
        (Join-Path $ResourcesPath "zh-HK.json"),
        (Join-Path $ResourcesPath "ion-dist\i18n\statsig\zh-HK.json")
    )

    foreach ($target in $targets) {
        Remove-Item $target -Force -ErrorAction SilentlyContinue
        if (Test-Path $target) {
            Write-Host "  removed: $target" -ForegroundColor Green
        }
    }
}

function Stop-ClaudeProcesses {
    Stop-Process -Name "Claude" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "claude" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "  stopped Claude Desktop if it was running" -ForegroundColor Green
}

function Restart-Claude {
    param([string]$ClaudePath)

    Stop-ClaudeProcesses

    $exeCandidates = @(
        (Join-Path $ClaudePath "app\Claude.exe"),
        (Join-Path $ClaudePath "app\claude.exe")
    )
    foreach ($exe in $exeCandidates) {
        if (Test-Path $exe) {
            Start-Process $exe
            Write-Host "  restarted Claude Desktop" -ForegroundColor Green
            return
        }
    }

    Write-Host "  [警告] 未找到 Claude.exe，请手动启动 Claude Desktop。" -ForegroundColor DarkYellow
}

function Install-WindowsLanguagePack {
    $label = Get-LanguageLabel $LanguageCode
    Write-Host "=== Claude Desktop Windows $label 补丁 ===" -ForegroundColor Cyan

    Write-Step "[1/8] 检查语言资源"
    $pack = Get-LanguageResources $LanguageCode

    Write-Step "[2/8] 查找 Claude Desktop"
    $paths = Get-ClaudeResourcesPath
    $claudePath = $paths["App"]
    $resourcesPath = $paths["Resources"]
    Write-Host "  app: $claudePath" -ForegroundColor Green
    Write-Host "  resources: $resourcesPath" -ForegroundColor Green

    Write-Step "关闭 Claude Desktop"
    Stop-ClaudeProcesses

    Write-Step "[3/8] 准备写入权限"
    Enable-WriteAccess $resourcesPath

    Write-Step "[4/8] 写入 $label 资源"
    Install-LanguageFiles $resourcesPath $pack $LanguageCode

    Write-Step "[5/8] 注册中文语言"
    Register-Language $resourcesPath

    Write-Step "[6/8] 汉化硬编码界面文本"
    Patch-HardcodedFrontendStrings $resourcesPath

    Write-Step "[7/8] 修复第三方模型名校验"
    Patch-Custom3PModelValidation $resourcesPath

    Write-Step "[8/8] 写入用户语言配置"
    Set-ClaudeLocale $LanguageCode

    Write-Step "重启 Claude Desktop"
    Restart-Claude $claudePath

    Write-Host ""
    Write-Host "安装完成。如果界面未立即切换，请在 Language 中选择 $label。" -ForegroundColor Green
}

function Uninstall-WindowsLanguagePack {
    Write-Host "=== Claude Desktop Windows 中文补丁卸载 ===" -ForegroundColor Cyan

    $paths = Get-ClaudeResourcesPath
    $claudePath = $paths["App"]
    $resourcesPath = $paths["Resources"]

    Write-Step "关闭 Claude Desktop"
    Stop-ClaudeProcesses

    Write-Step "[1/4] 恢复前端 bundle 和 app.asar"
    Restore-LatestBackup $resourcesPath
    Sync-ClaudeExeAsarIntegrity $resourcesPath

    Write-Step "[2/4] 删除中文资源"
    Remove-LanguageFiles $resourcesPath

    Write-Step "[3/4] 移除 zh-CN 语言注册"
    Unregister-Language $resourcesPath

    Write-Step "[4/4] 恢复用户语言配置"
    Set-ClaudeLocale "en-US"

    Write-Host ""
    Write-Host "卸载完成。请重启 Claude Desktop 使更改生效。" -ForegroundColor Green
}

switch ($Action) {
    "install" { Install-WindowsLanguagePack }
    "uninstall" { Uninstall-WindowsLanguagePack }
}
