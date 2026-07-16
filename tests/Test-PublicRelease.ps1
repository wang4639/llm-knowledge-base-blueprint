param([string]$ProjectRoot = '.')

$ErrorActionPreference = 'Stop'

function Add-Hit {
    param([System.Collections.Generic.List[string]]$List,[string]$Type,[string]$Path)
    $List.Add("$Type::$Path")
}

$root = [IO.Path]::GetFullPath($ProjectRoot)
$required = @('README.md','AI-REPRODUCE.md','index.md','LICENSE','NOTICE','CITATION.cff','.github\CODEOWNERS','SECURITY.md')
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf)) { throw "PUBLIC_RELEASE_MISSING::$relative" }
}

$allFiles = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
$internalHits = [System.Collections.Generic.List[string]]::new()
$privacyHits = [System.Collections.Generic.List[string]]::new()
$secretHits = [System.Collections.Generic.List[string]]::new()
$horizonHits = [System.Collections.Generic.List[string]]::new()

$forbiddenNames = @('START-HERE.md','AGENTS.md','Agent项目通用规则模板.md','Build-DeliveryPackage.ps1','auth.json')
$forbiddenExtensions = @('.db','.sqlite','.sqlite3','.log','.pem','.key')
foreach ($file in $allFiles) {
    $relative = $file.FullName.Substring($root.TrimEnd('\').Length + 1).Replace('\','/')
    if ($forbiddenNames -contains $file.Name -or $relative.StartsWith('_loop/')) { Add-Hit $internalHits 'internal' $relative }
    if ($forbiddenExtensions -contains $file.Extension.ToLowerInvariant()) { Add-Hit $secretHits 'forbidden-extension' $relative }
    if ($file.Name -eq '.env' -or ($file.Name.StartsWith('.env.') -and $file.Name -ne '.env.example')) { Add-Hit $secretHits 'environment-file' $relative }
    if ($relative -eq 'tests/Test-PublicRelease.ps1') { continue }

    $text = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    $privatePathPattern = '[A-Za-z]:' + '[\\/]' + 'Users' + '[\\/]'
    $privateCorpusPattern = 'wsh文件' + '总库|苍' + '云|我的' + '资料'
    if ($text -match $privatePathPattern -or $text -match $privateCorpusPattern) { Add-Hit $privacyHits 'private-path-or-corpus' $relative }

    $secretPatterns = @(
        ('s'+'k-'+'[A-Za-z0-9_-]{20,}'),
        ('g'+'h'+'[pousr]_[A-Za-z0-9]{20,}'),
        ('A'+'KIA[0-9A-Z]{16}'),
        ('A'+'Iza[0-9A-Za-z_-]{30,}'),
        ('-----BEGIN '+'(RSA |EC |OPENSSH )?PRIVATE KEY-----'),
        ('(?i)(api[_-]?'+'key|access[_-]?'+'token|auth[_-]?'+'token|password|client[_-]?'+'secret)\s*[:=]\s*["'']?[A-Za-z0-9_./+-]{16,}')
    )
    foreach ($pattern in $secretPatterns) {
        if ($text -match $pattern) { Add-Hit $secretHits 'secret-pattern' $relative; break }
    }

    $horizonImplementation = '(?i)(' + 'run-' + 'horizon|horizon-' + '2|HORIZON' + '_|data[\\/]profiles|data[\\/]summaries|x_' + 'cookies)'
    if ($text -match $horizonImplementation) { Add-Hit $horizonHits 'horizon-implementation' $relative }
}

if ($internalHits.Count -gt 0 -or $privacyHits.Count -gt 0 -or $secretHits.Count -gt 0 -or $horizonHits.Count -gt 0) {
    $all = @($internalHits) + @($privacyHits) + @($secretHits) + @($horizonHits)
    throw ("PUBLIC_RELEASE_SCAN_FAILED`n" + ($all -join "`n"))
}

$notice = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'NOTICE')
$citation = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root 'CITATION.cff')
$owners = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root '.github\CODEOWNERS')
if ($notice -notmatch 'wang4639' -or $citation -notmatch 'wang4639' -or $owners -notmatch '@wang4639') {
    throw 'PUBLIC_RELEASE_ATTRIBUTION_FAILED'
}

Write-Output "PUBLIC_RELEASE_SCAN_PASSED files=$($allFiles.Count) secret_hits=0 privacy_hits=0 horizon_implementation_hits=0 internal_hits=0"
