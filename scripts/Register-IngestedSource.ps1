param(
    [string]$ProjectRoot = '.',
    [string]$ConfigPath = '.\config\knowledge-base.local.json',
    [Parameter(Mandatory=$true)][string]$SourceRootId,
    [Parameter(Mandatory=$true)][string]$RelativePath,
    [Parameter(Mandatory=$true)][string]$Board,
    [Parameter(Mandatory=$true)][string]$SourceNote,
    [Parameter(Mandatory=$true)][string]$Wiki,
    [string]$Risk = '低'
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
        $rows += [pscustomobject]@{Id=[int]$c[0];RootId=$c[1].Trim('`');Relative=$c[2].Trim('`');Hash=$c[3].Trim('`');Note=$c[6].Trim('`')}
    }
    return $rows
}

foreach ($value in @($SourceRootId,$RelativePath,$Board,$SourceNote,$Wiki,$Risk)) {
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[|\r\n]') { throw '注册参数不能为空，也不能包含管道符或换行。' }
}

$root = [IO.Path]::GetFullPath($ProjectRoot)
$configFull = Resolve-ProjectPath -Base $root -Path $ConfigPath
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configFull | ConvertFrom-Json
if (@($config.boards) -notcontains $Board) { throw 'Board 不在本地配置允许列表中。' }
$source = @($config.source_roots | Where-Object { [string]$_.id -eq $SourceRootId })
if ($source.Count -ne 1) { throw 'SourceRootId 不存在或不唯一。' }
$sourceRoot = Resolve-ProjectPath -Base $root -Path ([string]$source[0].path)
$normalized = $RelativePath.Replace('\','/').TrimStart('/')
if ($normalized.Contains('../') -or $normalized -eq '..') { throw 'RelativePath 不得跳出资料根目录。' }
$sourceFile = [IO.Path]::GetFullPath((Join-Path $sourceRoot $normalized.Replace('/','\')))
$prefix = $sourceRoot.TrimEnd('\') + '\'
if (-not $sourceFile.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'RelativePath 跳出资料根目录。' }
if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw '原始资料不存在。' }

$noteFull = [IO.Path]::GetFullPath((Join-Path $root $SourceNote.Replace('/','\')))
$wikiFull = [IO.Path]::GetFullPath((Join-Path $root $Wiki.Replace('/','\')))
if (-not $noteFull.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'SourceNote 跳出项目根目录。' }
if (-not $wikiFull.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Wiki 跳出项目根目录。' }
if (-not (Test-Path -LiteralPath $noteFull -PathType Leaf)) { throw '来源笔记尚不存在。' }
if (-not (Test-Path -LiteralPath $wikiFull -PathType Leaf)) { throw 'Wiki 页面尚不存在。' }

$scan = & (Join-Path $root 'scripts\Check-Inbox.ps1') -ProjectRoot $root -ConfigPath $configFull -ValidateOnly
if ($scan.NewFiles -lt 1 -or $scan.NewFiles -gt [int]$config.max_batch_size) { throw '当前新资料数量不满足摄入门禁。' }
if ($scan.DuplicateCopies -ne 0 -or $scan.UpdatedFiles -ne 0 -or $scan.MissingFiles -ne 0 -or $scan.SameNameCandidates -ne 0) {
    throw '当前存在重复、更新、缺失或同名候选，禁止注册。'
}
if (@($scan.NewFileItems | Where-Object { $_.RootId -eq $SourceRootId -and $_.Relative -eq $normalized }).Count -ne 1) {
    throw '指定原始资料不是当前唯一可注册的新资料。'
}

$hashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile).Hash.ToUpperInvariant()
$bytes = (Get-Item -LiteralPath $sourceFile).Length
$manifest = Join-Path $root '00-系统\资料摄入总清单.md'
$rows = @(Read-Rows -Path $manifest)
if (@($rows | Where-Object { $_.RootId -eq $SourceRootId -and $_.Relative -eq $normalized }).Count -gt 0) { throw '原始路径已登记。' }
if (@($rows | Where-Object { $_.Hash -eq $hashBefore }).Count -gt 0) { throw '原始哈希已登记。' }
if (@($rows | Where-Object { $_.Note -eq $SourceNote.Replace('\','/') }).Count -gt 0) { throw '来源笔记已登记。' }
$hashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile).Hash.ToUpperInvariant()
if ($hashBefore -ne $hashAfter) { throw '处理期间原始资料哈希发生变化。' }

$id = if ($rows.Count -eq 0) { 1 } else { [int](($rows | Measure-Object Id -Maximum).Maximum) + 1 }
$noteRel = $SourceNote.Replace('\','/'); $wikiRel = $Wiki.Replace('\','/')
$line = "| $id | ``$SourceRootId`` | ``$normalized`` | ``$hashBefore`` | $bytes | $Board | ``$noteRel`` | 已编译 | ``$wikiRel`` | $Risk | $(Get-Date -Format 'yyyy-MM-dd') |"
[IO.File]::AppendAllText($manifest, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output "REGISTERED id=$id root=$SourceRootId path=$normalized hash12=$($hashBefore.Substring(0,12))"
