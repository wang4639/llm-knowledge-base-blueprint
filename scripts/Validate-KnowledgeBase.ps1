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

function Read-Rows {
    param([string]$Path)
    $rows = @()
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $Path) {
        if ($line -notmatch '^\|\s*\d+\s*\|') { continue }
        $c = @($line.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($c.Count -ne 11) { throw '总清单列数不是 11。' }
        $rows += [pscustomobject]@{
            Id=[int]$c[0];RootId=$c[1].Trim('`');Relative=$c[2].Trim('`');Hash=$c[3].Trim('`').ToUpperInvariant()
            Bytes=[int64]$c[4];Board=$c[5];Note=$c[6].Trim('`');Status=$c[7];Wiki=$c[8].Trim('`')
        }
    }
    return $rows
}

$root = [IO.Path]::GetFullPath($ProjectRoot)
$configFull = Resolve-ProjectPath -Base $root -Path $ConfigPath
if (-not (Test-Path -LiteralPath $configFull -PathType Leaf)) { throw '本地配置不存在。' }
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configFull | ConvertFrom-Json

$required = @(
    'index.md','AI-REPRODUCE.md','00-系统\AI Agent 使用指南.md','00-系统\知识库维护规则.md',
    '00-系统\自动增量摄入运行规则.md','00-系统\模板\来源笔记模板.md','00-系统\模板\问答卡模板.md',
    '00-系统\资料摄入总清单.md','10-来源笔记','20-Wiki','30-输出','90-维护报告'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) { throw "缺少必要路径：$relative" }
}

$boards = @($config.boards)
if ($boards.Count -eq 0) { throw 'boards 为空。' }
foreach ($board in $boards) {
    foreach ($file in @('index.md','问答索引.md','log.md')) {
        $relative = Join-Path (Join-Path '20-Wiki' ([string]$board)) $file
        if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) { throw "板块缺少文件：$relative" }
    }
}

$sourceRoots = @{}
foreach ($source in @($config.source_roots)) {
    $id = [string]$source.id
    if ($sourceRoots.ContainsKey($id)) { throw 'source_roots.id 重复。' }
    $sourceRoots[$id] = Resolve-ProjectPath -Base $root -Path ([string]$source.path)
    if (-not (Test-Path -LiteralPath $sourceRoots[$id] -PathType Container)) { throw "授权资料目录不存在：id=$id" }
}

$rows = @(Read-Rows -Path (Join-Path $root '00-系统\资料摄入总清单.md'))
$keys=@{}; $hashes=@{}; $notes=@{}
foreach ($row in $rows) {
    if (-not $sourceRoots.ContainsKey($row.RootId)) { throw "清单根目录 ID 不存在：id=$($row.Id)" }
    $key="$($row.RootId)|$($row.Relative)"
    if ($keys.ContainsKey($key) -or $hashes.ContainsKey($row.Hash) -or $notes.ContainsKey($row.Note)) { throw "清单存在重复键：id=$($row.Id)" }
    $keys[$key]=$true; $hashes[$row.Hash]=$true; $notes[$row.Note]=$true
    if ($row.Hash -notmatch '^[0-9A-F]{64}$') { throw "SHA256 无效：id=$($row.Id)" }
    if ($boards -notcontains $row.Board) { throw "板块不在配置中：id=$($row.Id)" }
    $sourceFile = Join-Path $sourceRoots[$row.RootId] $row.Relative.Replace('/','\')
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "原始资料不存在：id=$($row.Id)" }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile).Hash.ToUpperInvariant()
    if ($actual -ne $row.Hash) { throw "原始资料哈希变化：id=$($row.Id)" }
    if (-not (Test-Path -LiteralPath (Join-Path $root $row.Note.Replace('/','\')) -PathType Leaf)) { throw "来源笔记不存在：id=$($row.Id)" }
    if (-not (Test-Path -LiteralPath (Join-Path $root $row.Wiki.Replace('/','\')) -PathType Leaf)) { throw "Wiki 页面不存在：id=$($row.Id)" }
}

foreach ($card in Get-ChildItem -LiteralPath (Join-Path $root '20-Wiki') -File -Recurse -Filter '*.md' | Where-Object { $_.FullName -match '[\\/]问题与假设[\\/]' }) {
    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $card.FullName
    foreach ($section in @('## 直接回答','## 判断标准','## 例外条件','## 推荐行动','## 依据与回溯')) {
        if (-not $text.Contains($section)) { throw "问答卡缺少固定章节：$($card.Name) / $section" }
    }
}

$scan = & (Join-Path $root 'scripts\Check-Inbox.ps1') -ProjectRoot $root -ConfigPath $configFull -ValidateOnly
if ($scan.NewFiles -ne 0 -or $scan.DuplicateCopies -ne 0 -or $scan.UpdatedFiles -ne 0 -or $scan.MissingFiles -ne 0 -or $scan.SameNameCandidates -ne 0) {
    throw '动态验证失败：资料差异尚未归零。'
}

Write-Output "VALIDATION_PASS manifest_rows=$($rows.Count) source_files=$($scan.CurrentFiles) boards=$($boards.Count)"
