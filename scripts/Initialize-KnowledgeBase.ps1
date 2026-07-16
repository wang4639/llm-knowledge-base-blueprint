param(
    [string]$ProjectRoot = '.',
    [string]$ConfigPath = '.\config\knowledge-base.local.json'
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectPath {
    param([string]$Base, [string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $Base $Path))
}

function Write-NewUtf8File {
    param([string]$Path, [string]$Content)
    if (Test-Path -LiteralPath $Path) { return $false }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    return $true
}

$root = [IO.Path]::GetFullPath($ProjectRoot)
$configFull = Resolve-ProjectPath -Base $root -Path $ConfigPath
if (-not (Test-Path -LiteralPath $configFull -PathType Leaf)) {
    throw "本地配置不存在。请复制 config/knowledge-base.example.json 后填写授权资料目录。"
}

$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configFull | ConvertFrom-Json
if ([int]$config.max_batch_size -lt 1 -or [int]$config.max_batch_size -gt 30) {
    throw 'max_batch_size 必须在 1 到 30 之间。'
}

$boards = @($config.boards)
if ($boards.Count -eq 0) { throw 'boards 至少需要一个板块。' }
if ((@($boards | Select-Object -Unique)).Count -ne $boards.Count) { throw 'boards 存在重复值。' }

$roots = @($config.source_roots)
if ($roots.Count -eq 0) { throw 'source_roots 至少需要一个授权资料目录。' }
$rootIds = @($roots | ForEach-Object { [string]$_.id })
if ((@($rootIds | Select-Object -Unique)).Count -ne $rootIds.Count) { throw 'source_roots.id 必须唯一。' }
foreach ($source in $roots) {
    if ([string]::IsNullOrWhiteSpace([string]$source.id)) { throw 'source_roots.id 不能为空。' }
    $sourcePath = Resolve-ProjectPath -Base $root -Path ([string]$source.path)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "授权资料目录不存在：id=$($source.id)"
    }
}

$requiredDirs = @('00-系统','00-系统\模板','10-来源笔记','20-Wiki','30-输出','90-维护报告')
foreach ($relative in $requiredDirs) {
    $full = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        New-Item -ItemType Directory -Path $full | Out-Null
    }
}

$manifest = Join-Path $root '00-系统\资料摄入总清单.md'
$manifestContent = @'
# 资料摄入总清单

| ID | 根目录ID | 原始相对路径 | SHA256 | 字节数 | 板块 | 来源笔记 | 状态 | Wiki | 风险 | 摄入日期 |
|---:|---|---|---|---:|---|---|---|---|---|---|
'@
[void](Write-NewUtf8File -Path $manifest -Content $manifestContent)

foreach ($board in $boards) {
    if ([string]::IsNullOrWhiteSpace([string]$board) -or [string]$board -match '[|\r\n]') {
        throw '板块名不能为空，也不能包含管道符或换行。'
    }
    $boardRoot = Join-Path $root (Join-Path '20-Wiki' ([string]$board))
    foreach ($relative in @('', '问题与假设', '主题', '概念')) {
        $dir = if ($relative) { Join-Path $boardRoot $relative } else { $boardRoot }
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir | Out-Null
        }
    }
    [void](Write-NewUtf8File -Path (Join-Path $boardRoot 'index.md') -Content "# $board`n`n## LLM 问答入口`n`n- [[问答索引]]`n`n## 主题`n")
    [void](Write-NewUtf8File -Path (Join-Path $boardRoot '问答索引.md') -Content "# $board 问答索引`n`n| 用户意图 | 问答卡 | 状态 |`n|---|---|---|`n")
    [void](Write-NewUtf8File -Path (Join-Path $boardRoot 'log.md') -Content "# $board 日志`n")
}

Write-Output "INITIALIZATION_OK boards=$($boards.Count) source_roots=$($roots.Count)"
