[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$Message = '',
    [switch]$DryRun
)

# Publish.cmd uses Windows PowerShell 5.1. Keep this file UTF-8 with BOM.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$versionPattern = '\Av(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*))?\z'
$publishLock = $null
$stage = '预检'

function Invoke-ProjectGit {
    param([string[]]$Arguments, [switch]$AllowFailure)
    # Keep machine-readable stdout separate from warnings/progress on stderr.
    # Native stderr is an ErrorRecord in PS 5.1/7. Split those objects before
    # converting to strings, so warnings cannot become paths, refs or status.
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $records = @(& $script:gitPath --no-optional-locks -C $projectRoot -c core.quotepath=false @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $savedPreference }
    $lines = @()
    $stderrLines = @()
    foreach ($record in $records) {
        if ($record -is [System.Management.Automation.ErrorRecord]) { $stderrLines += $record.ToString() }
        else { $lines += [string]$record }
    }
    $stderrText = $stderrLines -join "`n"
    if ($code -ne 0 -and -not $AllowFailure) {
        throw ("Git 操作失败（退出码 {0}）：{1}" -f $code, ((@($lines) + @($stderrText)) -join "`n"))
    }
    if ($stderrText) { Write-Host $stderrText -ForegroundColor Yellow }
    return [pscustomobject]@{ Code = $code; Lines = $lines; Stderr = $stderrText }
}

function Git-Text {
    param([string[]]$Arguments)
    return ((Invoke-ProjectGit -Arguments $Arguments).Lines -join "`n").Trim()
}

function Git-PrivatePath {
    param([string]$Name)
    $path = Git-Text @('rev-parse', '--git-path', $Name)
    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $projectRoot $path }
    return [IO.Path]::GetFullPath($path)
}

function Get-RemoteRefs {
    $refs = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($line in (Invoke-ProjectGit @('ls-remote', '--heads', '--tags', '--', $script:pushUrl)).Lines) {
        if ($line -match '^([0-9a-f]{40,64})\s+(refs/(?:heads|tags)/.+)$') {
            $refs[$Matches[2]] = $Matches[1]
        }
    }
    return ,$refs
}

function Remote-TagCommit {
    param($Refs, [string]$Tag)
    $ref = 'refs/tags/' + $Tag
    if ($Refs.ContainsKey($ref + '^{}')) { return $Refs[$ref + '^{}'] }
    if ($Refs.ContainsKey($ref)) { return $Refs[$ref] }
    return ''
}

function Next-DemoVersion {
    param([string[]]$Tags)
    $versions = @(
        foreach ($tag in $Tags) {
            $match = [regex]::Match($tag, $versionPattern)
            if ($match.Success) {
                [pscustomobject]@{
                    Major = [bigint]::Parse($match.Groups[1].Value)
                    Minor = [bigint]::Parse($match.Groups[2].Value)
                    Patch = [bigint]::Parse($match.Groups[3].Value)
                }
            }
        }
    )
    if ($versions.Count -eq 0) { return 'v0.1.0-demo' }
    $latest = $versions | Sort-Object Major, Minor, Patch | Select-Object -Last 1
    return 'v{0}.{1}.{2}-demo' -f $latest.Major, $latest.Minor, ($latest.Patch + 1)
}

function Write-Pending {
    param($State)
    $json = $State | ConvertTo-Json
    [IO.File]::WriteAllText($script:pendingPath + '.tmp', $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath ($script:pendingPath + '.tmp') -Destination $script:pendingPath -Force
}

function Assert-Checkout {
    param([string]$ExpectedHead = '')
    $currentBranch = Git-Text @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($currentBranch -cne $branch) { throw '发版过程中分支已切换，已停止；请回到原分支后重试。' }
    if ($ExpectedHead -and (Git-Text @('rev-parse', '--verify', 'HEAD')) -cne $ExpectedHead) {
        throw '发版过程中 HEAD 已改变，已停止；请检查当前提交后重试。'
    }
}

function Show-ResultLinks {
    param([string]$Tag)
    if ($script:pushUrl -match '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$') {
        $web = 'https://github.com/' + $Matches[1]
        Write-Host ('构建进度：' + $web + '/actions/workflows/release.yml') -ForegroundColor Cyan
        Write-Host ('完成后下载：' + $web + '/releases/tag/' + $Tag) -ForegroundColor Cyan
    }
    Write-Host '标签已推送。GitHub Actions 将按现有流程测试、打包并发版；最终结果请查看构建页面。' -ForegroundColor Green
}

try {
    Write-Host '月面采掘 · 一键提交与发版' -ForegroundColor Cyan
    if ($DryRun) { Write-Host '预演模式：仅查看，不修改工作区、暂存区、提交或标签，也不推送。' -ForegroundColor Yellow }
    $gitCommand = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $script:gitPath = $gitCommand.Source
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
        throw '找不到 project.godot，请将入口保留在 Godot 项目根目录。'
    }
    $actualRoot = [IO.Path]::GetFullPath((Git-Text @('rev-parse', '--show-toplevel')))
    if (-not [string]::Equals($actualRoot.TrimEnd('\', '/'), $projectRoot.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
        throw '脚本目录不是此 Git 仓库根目录，已停止以免提交上层工程。'
    }
    if ((Git-Text @('rev-parse', '--is-shallow-repository')) -eq 'true') {
        throw '当前是浅克隆，无法可靠检查分支历史；请先补全历史再发版。'
    }
    $branchResult = Invoke-ProjectGit @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFailure
    if ($branchResult.Code -ne 0) { throw '当前处于 detached HEAD，请切回要发布的分支。' }
    $branch = ($branchResult.Lines -join '').Trim()
    $branchRef = 'refs/heads/' + $branch
    $head = Git-Text @('rev-parse', '--verify', 'HEAD')
    foreach ($operation in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply', 'sequencer')) {
        if (Test-Path -LiteralPath (Git-PrivatePath $operation)) { throw '存在未完成的合并、rebase 或挑选操作，请先处理完毕。' }
    }
    if ((Git-Text @('ls-files', '--unmerged')).Length -gt 0) { throw '存在未解决的冲突，请先处理。' }
    $workflow = Join-Path $projectRoot '.github/workflows/release.yml'
    if (-not (Test-Path -LiteralPath $workflow -PathType Leaf)) { throw '缺少 .github/workflows/release.yml，无法触发打包发版。' }
    $workflowText = [IO.File]::ReadAllText($workflow)
    if ($workflowText -notmatch '(?m)^\s+push:\s*$' -or $workflowText -notmatch '(?m)^\s*-\s*[''"]?v\*[''"]?\s*$') {
        throw 'release.yml 未配置 v* 标签推送触发，请检查工作流。'
    }
    $ignoredWorkflow = Invoke-ProjectGit @('check-ignore', '-q', '--', '.github/workflows/release.yml') -AllowFailure
    if ($ignoredWorkflow.Code -eq 0) { throw '发布工作流被 Git 忽略，无法随本次提交发版。' }
    if ($ignoredWorkflow.Code -ne 1) { throw '无法检查工作流是否会被提交。' }
    $pushUrls = @((Invoke-ProjectGit @('remote', 'get-url', '--push', '--all', 'origin')).Lines)
    if ($pushUrls.Count -ne 1 -or [string]::IsNullOrWhiteSpace($pushUrls[0])) { throw 'origin 必须且只能有一个推送地址。' }
    $script:pushUrl = $pushUrls[0].Trim()
    if ($script:pushUrl -match '^https?://[^/]*@') { throw 'origin 地址中包含内嵌凭据，请改用 Git 凭据管理器后重试。' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $remoteFingerprint = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:pushUrl))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    $script:pendingPath = Git-PrivatePath 'publish-demo-pending.json'
    if (-not $DryRun) {
        try { $publishLock = [IO.File]::Open((Git-PrivatePath 'publish-demo.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { throw '另一个发版进程正在运行，或 Git 目录不可写，请先检查。' }
    }
    $remoteRefs = Get-RemoteRefs
    $pending = $null
    if (Test-Path -LiteralPath $script:pendingPath) {
        $pending = [IO.File]::ReadAllText($script:pendingPath) | ConvertFrom-Json
        if ($pending.schema -ne 1 -or $pending.remote_fingerprint -cne $remoteFingerprint -or $pending.branch -cne $branch -or $pending.commit -cne $head) {
            throw '上次待发布记录与当前仓库/分支/提交不一致。请检查 Git 目录中的 publish-demo-pending.json，保留原标签后处理，脚本不会移动旧标签。'
        }
        if (-not [regex]::IsMatch([string]$pending.tag, $versionPattern)) { throw '上次待发布版本记录无效，请检查 publish-demo-pending.json。' }
        if ($Version -and $Version -cne $pending.tag) { throw ('上次 ' + $pending.tag + ' 尚待推送，请先不带参数重试该版本。') }
        $Version = [string]$pending.tag
    }
    if (-not $Version) {
        $allTags = @((Invoke-ProjectGit @('tag', '--list')).Lines)
        $allTags += @($remoteRefs.Keys | Where-Object { $_.StartsWith('refs/tags/') -and -not $_.EndsWith('^{}') } | ForEach-Object { $_.Substring(10) })
        $Version = Next-DemoVersion $allTags
    }
    if (-not [regex]::IsMatch($Version, $versionPattern)) { throw '版本格式必须为 vX.Y.Z 或 vX.Y.Z-demo，不接受前导零与 +metadata。' }
    $tagRef = 'refs/tags/' + $Version
    $remoteTag = Remote-TagCommit $remoteRefs $Version
    $localTagResult = Invoke-ProjectGit @('show-ref', '--verify', '--quiet', $tagRef) -AllowFailure
    if ($localTagResult.Code -notin @(0, 1)) { throw '无法检查本地标签。' }
    $localTagExists = $localTagResult.Code -eq 0
    if ($pending) {
        if ($localTagExists -and (Git-Text @('rev-parse', '--verify', ($tagRef + '^{commit}'))) -cne $head) { throw '待发布本地标签指向了其他提交，已停止。' }
        if ($remoteTag -and $remoteTag -cne $head) { throw '远端同名标签指向其他提交，已停止；不会覆盖标签。' }
        if ($remoteTag -ceq $head) {
            if (-not $remoteRefs.ContainsKey($branchRef)) { throw '远端已有版本标签，但发布分支不存在，不能确认上次完整推送已完成。' }
            if ($remoteRefs[$branchRef] -cne $head) {
                if ($DryRun) {
                    Write-Host '远端已有同提交标签；预演不下载分支历史，正式运行会进一步确认分支包含该提交。' -ForegroundColor Yellow
                    exit 0
                }
                $null = Invoke-ProjectGit @('fetch', '--no-tags', '--', $script:pushUrl, $branchRef)
                $contained = Invoke-ProjectGit @('merge-base', '--is-ancestor', $head, 'FETCH_HEAD') -AllowFailure
                if ($contained.Code -ne 0) { throw '远端版本标签与发布分支历史不一致，无法确认上次完整推送已完成。' }
            }
            if (-not $DryRun) { Remove-Item -LiteralPath $script:pendingPath }
            Write-Host ('远端已经接受 ' + $Version + '，上次推送已完成；本次没有新建提交或标签。') -ForegroundColor Green
            Show-ResultLinks $Version
            exit 0
        }
    }
    elseif ($localTagExists -or $remoteTag) { throw ('版本 ' + $Version + ' 已存在，请使用新的版本号。') }

    Write-Host ('项目：' + $projectRoot)
    Write-Host ('分支：' + $branch + '    版本：' + $Version)
    $changes = @((Invoke-ProjectGit @('status', '--short', '--untracked-files=all')).Lines)
    if ($changes.Count) { Write-Host '将提交当前项目全部非忽略改动：'; $changes | ForEach-Object { Write-Host $_ } }
    else { Write-Host '工作区无新改动，将直接为当前提交创建发布标签。' }
    if ($pending -and $changes.Count) { throw '上次推送尚待重试，但工作区又有新改动。请先保存/移走这些改动，再重试原版本；不会把新内容塞进旧标签。' }
    if ($DryRun) {
        Write-Host '预演完成。正式运行会检查远端历史、提交变更，并原子推送当前分支和版本标签。' -ForegroundColor Green
        exit 0
    }
    $stage = '同步远端历史'
    if ($remoteRefs.ContainsKey($branchRef)) {
        # Query, fetch and push the same unique push destination, even if the
        # origin fetch URL differs. Never merge, reset or force-push for users.
        $fetch = Invoke-ProjectGit @('fetch', '--no-tags', '--', $script:pushUrl, $branchRef)
        $fetch.Lines | ForEach-Object { Write-Host $_ }
        $ancestor = Invoke-ProjectGit @('merge-base', '--is-ancestor', 'FETCH_HEAD', 'HEAD') -AllowFailure
        if ($ancestor.Code -eq 1) { throw '远端分支已有本地未包含的提交，请先同步并解决分歧，然后重新发版。' }
        if ($ancestor.Code -ne 0) { throw '无法确认远端分支历史，已停止。' }
    }
    if (-not $pending) {
        $stage = '提交代码'
        $null = Git-Text @('var', 'GIT_AUTHOR_IDENT')
        $null = Git-Text @('var', 'GIT_COMMITTER_IDENT')
        Assert-Checkout $head
        $null = Invoke-ProjectGit @('add', '--all', '--', '.')
        $staged = Invoke-ProjectGit @('diff', '--cached', '--quiet', '--exit-code') -AllowFailure
        if ($staged.Code -notin @(0, 1)) { throw '无法检查暂存区。' }
        if ($staged.Code -eq 1) {
            if ([string]::IsNullOrWhiteSpace($Message)) { $Message = 'chore: release ' + $Version }
            (Invoke-ProjectGit @('commit', '-m', $Message)).Lines | ForEach-Object { Write-Host $_ }
        }
        Assert-Checkout
        $head = Git-Text @('rev-parse', '--verify', 'HEAD')
        if ((Git-Text @('status', '--porcelain', '--untracked-files=all')).Length) { throw '提交过程中出现了新改动，请检查后重新运行；本次尚未创建发布标签。' }
        $pending = [ordered]@{ schema = 1; remote_fingerprint = $remoteFingerprint; branch = $branch; commit = $head; tag = $Version }
        Write-Pending $pending
    }
    $stage = '创建版本标签'
    if (-not $localTagExists) {
        $null = Invoke-ProjectGit @('tag', '-a', $Version, '-m', ('Moon Excavation ' + $Version), $head)
    }
    Assert-Checkout $head
    $tagObject = Git-Text @('rev-parse', '--verify', $tagRef)
    if ((Git-Text @('rev-parse', '--verify', ($tagObject + '^{commit}'))) -cne $head) {
        throw '发布标签已被外部移动，已停止；不会把错误标签推送到远端。'
    }
    $stage = '推送分支和版本标签'
    Write-Host ('正在推送 ' + $Version + ' ...') -ForegroundColor Cyan
    # Atomic means a branch rejection cannot leave behind a published tag.
    # No fallback to separate pushes: an unsupported server must fail safely.
    $push = Invoke-ProjectGit @('push', '--atomic', '--no-follow-tags', '--', $script:pushUrl, ($head + ':' + $branchRef), ($tagObject + ':' + $tagRef))
    $push.Lines | ForEach-Object { Write-Host $_ }
    Remove-Item -LiteralPath $script:pendingPath
    Show-ResultLinks $Version
    exit 0
}
catch {
    Write-Host ("`n发版停止（" + $stage + '）：' + $_.Exception.Message) -ForegroundColor Red
    if ($script:pendingPath -and (Test-Path -LiteralPath $script:pendingPath)) {
        Write-Host '本地提交和待发布版本已保留。排除网络/认证等问题后，再次双击 Publish.cmd 会重试同一版本。' -ForegroundColor Yellow
    }
    exit 1
}
finally {
    if ($null -ne $publishLock) { $publishLock.Dispose() }
}
