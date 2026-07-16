param([string]$ProjectRoot = '.')

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION_FAILED: $Message" }
}

$root = [IO.Path]::GetFullPath($ProjectRoot)
$required = @(
    'README.md','AI-REPRODUCE.md','index.md','LICENSE','NOTICE','CITATION.cff','.github\CODEOWNERS',
    '00-系统\AI Agent 使用指南.md','00-系统\知识库维护规则.md','00-系统\自动增量摄入运行规则.md',
    '00-系统\模板\来源笔记模板.md','00-系统\模板\问答卡模板.md','00-系统\资料摄入总清单.md',
    'scripts\Initialize-KnowledgeBase.ps1','scripts\Check-Inbox.ps1','scripts\Register-IngestedSource.ps1',
    'scripts\Validate-KnowledgeBase.ps1','automations\weekly-maintenance.prompt.md','automations\weekly-ingestion.prompt.md'
)
foreach ($relative in $required) {
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $root $relative)) -Message "missing $relative"
}

foreach ($script in Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.ps1') {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
    Assert-True -Condition ($errors.Count -eq 0) -Message "PowerShell syntax $($script.Name): $($errors -join '; ')"
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("llmkb-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
foreach ($dir in @('00-系统','10-来源笔记','20-Wiki','30-输出','90-维护报告','automations','config')) {
    Copy-Item -LiteralPath (Join-Path $root $dir) -Destination (Join-Path $sandbox $dir) -Recurse
}
New-Item -ItemType Directory -Path (Join-Path $sandbox 'scripts') | Out-Null
foreach ($name in @('Initialize-KnowledgeBase.ps1','Check-Inbox.ps1','Register-IngestedSource.ps1','Validate-KnowledgeBase.ps1')) {
    Copy-Item -LiteralPath (Join-Path $root "scripts\$name") -Destination (Join-Path $sandbox "scripts\$name")
}
foreach ($name in @('README.md','AI-REPRODUCE.md','index.md','LICENSE','NOTICE','CITATION.cff')) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $sandbox $name)
}

$rawRoot = Join-Path $sandbox 'authorized-inbox'
New-Item -ItemType Directory -Path $rawRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'examples\示例原始资料\可验证知识库.md') -Destination (Join-Path $rawRoot '可验证知识库.md')

$config = [ordered]@{
    schema_version = 1
    max_batch_size = 30
    allowed_extensions = @('.md')
    source_roots = @([ordered]@{id='inbox';path=$rawRoot})
    boards = @('示例板块')
    source_note_prefix = '10-来源笔记'
} | ConvertTo-Json -Depth 5
$configPath = Join-Path $sandbox 'config\knowledge-base.local.json'
[IO.File]::WriteAllText($configPath,$config,[Text.UTF8Encoding]::new($false))

$init = & (Join-Path $sandbox 'scripts\Initialize-KnowledgeBase.ps1') -ProjectRoot $sandbox -ConfigPath $configPath
Assert-True -Condition ($init -match 'INITIALIZATION_OK') -Message 'initializer signature'

$first = & (Join-Path $sandbox 'scripts\Check-Inbox.ps1') -ProjectRoot $sandbox -ConfigPath $configPath -ValidateOnly
Assert-True -Condition ($first.NewFiles -eq 1) -Message 'first scan NewFiles=1'
Assert-True -Condition ($first.DuplicateCopies -eq 0 -and $first.UpdatedFiles -eq 0 -and $first.MissingFiles -eq 0 -and $first.SameNameCandidates -eq 0) -Message 'first scan other gates zero'

$registered = & (Join-Path $sandbox 'scripts\Register-IngestedSource.ps1') `
    -ProjectRoot $sandbox -ConfigPath $configPath -SourceRootId 'inbox' -RelativePath '可验证知识库.md' `
    -Board '示例板块' -SourceNote '10-来源笔记/示例板块/可验证知识库.md' `
    -Wiki '20-Wiki/示例板块/主题/可验证知识库.md'
Assert-True -Condition ($registered -match '^REGISTERED id=1 ') -Message 'registration signature'

$second = & (Join-Path $sandbox 'scripts\Check-Inbox.ps1') -ProjectRoot $sandbox -ConfigPath $configPath -ValidateOnly
Assert-True -Condition ($second.ManifestRows -eq 1 -and $second.Enrolled -eq 1) -Message 'registered row and enrolled file'
Assert-True -Condition ($second.NewFiles -eq 0 -and $second.DuplicateCopies -eq 0 -and $second.UpdatedFiles -eq 0 -and $second.MissingFiles -eq 0 -and $second.SameNameCandidates -eq 0) -Message 'second scan all gates zero'

$validation = & (Join-Path $sandbox 'scripts\Validate-KnowledgeBase.ps1') -ProjectRoot $sandbox -ConfigPath $configPath
Assert-True -Condition ($validation -match '^VALIDATION_PASS ') -Message 'dynamic validation signature'

$guide = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root '00-系统\AI Agent 使用指南.md')
Assert-True -Condition ($guide -match '根目录 index\.md[\s\S]*20-Wiki/<板块>/index\.md[\s\S]*问答索引\.md[\s\S]*问答卡[\s\S]*来源笔记') -Message 'Wiki-first retrieval route'
$maintenance = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'automations\weekly-maintenance.prompt.md')
$ingestion = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'automations\weekly-ingestion.prompt.md')
Assert-True -Condition ($maintenance.Contains('绝不摄入新资料') -and $maintenance.Contains('任一项不为 0')) -Message 'read-only maintenance gate'
Assert-True -Condition ($ingestion.Contains('1–30') -and $ingestion.Contains('SameNameCandidates')) -Message 'bounded ingestion gate'

$rights = @('NOTICE','CITATION.cff','.github\CODEOWNERS') | ForEach-Object { Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $_) }
Assert-True -Condition ((@($rights | Where-Object { $_ -match 'wang4639' })).Count -eq 3) -Message 'author attribution in three rights files'
$licenseText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'LICENSE')
Assert-True -Condition ($licenseText.Contains('Apache License') -and $licenseText.Contains('Version 2.0')) -Message 'Apache-2.0 license body'

$placeholders = Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/]_loop[\\/]' -and $_.Name -notin @('START-HERE.md','AGENTS.md','Agent项目通用规则模板.md','Build-DeliveryPackage.ps1') } | Select-String -Pattern '\{\{REQUIRED:' -SimpleMatch:$false
Assert-True -Condition (@($placeholders).Count -eq 0) -Message 'no public REQUIRED placeholders'

Write-Output "ALL_TESTS_PASSED sandbox=$sandbox"
