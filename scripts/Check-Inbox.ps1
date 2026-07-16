param(
    [string]$ProjectRoot = '.',
    [string]$ConfigPath = '.\config\knowledge-base.local.json',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectPath {
    param([string]$Base, [string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $Base $Path))
}

function Read-ManifestRows {
    param([string]$Path)
    $rows = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw '资料摄入总清单不存在。' }
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $Path) {
        if ($line -notmatch '^\|\s*\d+\s*\|') { continue }
        $cells = @($line.Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -ne 11) { throw "总清单列数不是 11：$line" }
        $row = [pscustomobject]@{
            Id = [int]$cells[0]; RootId = $cells[1].Trim('`'); Relative = $cells[2].Trim('`')
            Hash = $cells[3].Trim('`').ToUpperInvariant(); Bytes = [int64]$cells[4]
            Board = $cells[5]; Note = $cells[6].Trim('`'); Status = $cells[7]
            Wiki = $cells[8].Trim('`'); Risk = $cells[9]; Ingested = $cells[10]
        }
        if ($row.Hash -notmatch '^[0-9A-F]{64}$') { throw "清单 SHA256 无效：id=$($row.Id)" }
        $rows.Add($row)
    }
    return $rows
}

function Add-RelativeList {
    param([System.Collections.Generic.List[string]]$Lines, [object[]]$Items)
    if ($Items.Count -eq 0) { $Lines.Add('无。'); return }
    foreach ($item in $Items) { $Lines.Add("- ``$($item.RootId):$($item.Relative)``") }
}

$root = [IO.Path]::GetFullPath($ProjectRoot)
$configFull = Resolve-ProjectPath -Base $root -Path $ConfigPath
if (-not (Test-Path -LiteralPath $configFull -PathType Leaf)) { throw '本地配置不存在。' }
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configFull | ConvertFrom-Json
$extensions = @($config.allowed_extensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
if ($extensions.Count -eq 0) { throw 'allowed_extensions 不能为空。' }

$sourceRoots = @{}
foreach ($source in @($config.source_roots)) {
    $id = [string]$source.id
    if ([string]::IsNullOrWhiteSpace($id) -or $sourceRoots.ContainsKey($id)) { throw 'source_roots.id 为空或重复。' }
    $full = Resolve-ProjectPath -Base $root -Path ([string]$source.path)
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "授权资料目录不存在：id=$id" }
    $sourceRoots[$id] = $full
}

$manifestPath = Join-Path $root '00-系统\资料摄入总清单.md'
$reportPath = Join-Path $root '00-系统\待录入资料检查.md'
$rows = @(Read-ManifestRows -Path $manifestPath)
$byKey = @{}; $byHash = @{}; $byName = @{}; $notePaths = @{}
foreach ($row in $rows) {
    $key = "$($row.RootId)|$($row.Relative)"
    if ($byKey.ContainsKey($key)) { throw "总清单存在重复原始路径：id=$($row.Id)" }
    if ($notePaths.ContainsKey($row.Note)) { throw "总清单存在重复来源笔记：id=$($row.Id)" }
    $byKey[$key] = $row; $notePaths[$row.Note] = $true
    if (-not $byHash.ContainsKey($row.Hash)) { $byHash[$row.Hash] = [System.Collections.Generic.List[object]]::new() }
    $byHash[$row.Hash].Add($row)
    $name = [IO.Path]::GetFileName($row.Relative).ToLowerInvariant()
    if (-not $byName.ContainsKey($name)) { $byName[$name] = [System.Collections.Generic.List[object]]::new() }
    $byName[$name].Add($row)
}

$current = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $sourceRoots.GetEnumerator() | Sort-Object Key) {
    $prefix = $entry.Value.TrimEnd('\').Length + 1
    foreach ($file in Get-ChildItem -LiteralPath $entry.Value -File -Recurse | Sort-Object FullName) {
        if ($extensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
        $relative = $file.FullName.Substring($prefix).Replace('\','/')
        $current.Add([pscustomobject]@{
            RootId = $entry.Key; Relative = $relative; Name = $file.Name
            FullName = $file.FullName; Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToUpperInvariant()
            Bytes = $file.Length
        })
    }
}

$enrolled = [System.Collections.Generic.List[object]]::new()
$updated = [System.Collections.Generic.List[object]]::new()
$duplicates = [System.Collections.Generic.List[object]]::new()
$newCandidates = [System.Collections.Generic.List[object]]::new()
$currentKeys = @{}
foreach ($file in $current) {
    $key = "$($file.RootId)|$($file.Relative)"; $currentKeys[$key] = $true
    if ($byKey.ContainsKey($key)) {
        if ($byKey[$key].Hash -eq $file.Hash) { $enrolled.Add($file) }
        else { $updated.Add([pscustomobject]@{RootId=$file.RootId;Relative=$file.Relative;Hash=$file.Hash;PreviousHash=$byKey[$key].Hash}) }
    }
    elseif ($byHash.ContainsKey($file.Hash)) {
        $duplicates.Add([pscustomobject]@{RootId=$file.RootId;Relative=$file.Relative;Hash=$file.Hash;Matches=@($byHash[$file.Hash])})
    }
    else { $newCandidates.Add($file) }
}

$newFiles = [System.Collections.Generic.List[object]]::new()
foreach ($group in $newCandidates | Group-Object Hash) {
    $ordered = @($group.Group | Sort-Object RootId,Relative)
    $newFiles.Add($ordered[0])
    foreach ($copy in @($ordered | Select-Object -Skip 1)) {
        $duplicates.Add([pscustomobject]@{RootId=$copy.RootId;Relative=$copy.Relative;Hash=$copy.Hash;Matches=@($ordered[0])})
    }
}

$missing = [System.Collections.Generic.List[object]]::new()
foreach ($row in $rows) {
    if (-not $currentKeys.ContainsKey("$($row.RootId)|$($row.Relative)")) {
        $missing.Add([pscustomobject]@{RootId=$row.RootId;Relative=$row.Relative;Hash=$row.Hash})
    }
}

$sameNames = [System.Collections.Generic.List[object]]::new()
foreach ($file in $newFiles) {
    $name = $file.Name.ToLowerInvariant()
    if ($byName.ContainsKey($name)) {
        foreach ($old in $byName[$name]) {
            if ($old.Hash -ne $file.Hash) {
                $sameNames.Add([pscustomobject]@{RootId=$file.RootId;Relative=$file.Relative;ExistingRootId=$old.RootId;ExistingRelative=$old.Relative})
            }
        }
    }
}

$result = [pscustomobject]@{
    CurrentFiles = $current.Count; ManifestRows = $rows.Count; Enrolled = $enrolled.Count
    NewFiles = $newFiles.Count; DuplicateCopies = $duplicates.Count; UpdatedFiles = $updated.Count
    MissingFiles = $missing.Count; SameNameCandidates = $sameNames.Count
    NewFileItems = @($newFiles); DuplicateItems = @($duplicates); UpdatedItems = @($updated)
    MissingItems = @($missing); SameNameItems = @($sameNames)
}
if ($ValidateOnly) { return $result }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# 待录入资料检查'); $lines.Add('')
$lines.Add('> 本报告只显示根目录 ID 和相对路径，不输出本机绝对路径。检查过程只读原始资料。'); $lines.Add('')
$lines.Add("扫描时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"); $lines.Add('')
$lines.Add('## 分类统计'); $lines.Add('')
$lines.Add("- 当前资料：**$($current.Count)**"); $lines.Add("- 总清单记录：**$($rows.Count)**")
$lines.Add("- 已录入：**$($enrolled.Count)**"); $lines.Add("- 新资料：**$($newFiles.Count)**")
$lines.Add("- 重复副本：**$($duplicates.Count)**"); $lines.Add("- 已更新资料：**$($updated.Count)**")
$lines.Add("- 缺失资料：**$($missing.Count)**"); $lines.Add("- 同名候选：**$($sameNames.Count)**")
foreach ($section in @(
    @{Name='新资料';Items=@($newFiles)}, @{Name='重复副本';Items=@($duplicates)},
    @{Name='已更新资料';Items=@($updated)}, @{Name='缺失资料';Items=@($missing)},
    @{Name='同名候选';Items=@($sameNames)}
)) {
    $lines.Add(''); $lines.Add("## $($section.Name)"); $lines.Add('')
    Add-RelativeList -Lines $lines -Items $section.Items
}
$lines.Add(''); $lines.Add('## 下一步动作'); $lines.Add('')
$lines.Add('- 维护任务：任一差异不为 0 时只报告。')
$lines.Add('- 摄入任务：仅新资料为 1–30 且其他四项为 0 时继续。')
$lines.Add('- 重复、更新、缺失、同名和冲突都不自动修复或删除。')
[IO.File]::WriteAllLines($reportPath, $lines, [Text.UTF8Encoding]::new($false))
return $result
