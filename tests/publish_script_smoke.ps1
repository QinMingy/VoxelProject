[CmdletBinding()]
param(
    [string]$PublisherPath = '',
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0
$script:GitExe = (Get-Command git.exe -ErrorAction Stop).Source
$script:PowerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
if ([string]::IsNullOrWhiteSpace($PublisherPath)) {
    $PublisherPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\publish_demo.ps1'
}
$PublisherPath = (Resolve-Path -LiteralPath $PublisherPath).Path
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$scratch = [IO.Path]::GetFullPath((Join-Path $tempRoot ('moon-publish-smoke-' + [Guid]::NewGuid().ToString('N'))))
$script:CallerDirectory = Join-Path $scratch 'caller-outside-repository'
[void][IO.Directory]::CreateDirectory($script:CallerDirectory)
$script:Scratch = $scratch
$script:PublisherSource = Join-Path $scratch 'publisher-under-test.ps1'
Copy-Item -LiteralPath $PublisherPath -Destination $script:PublisherSource
$script:PublisherHash = (Get-FileHash -LiteralPath $script:PublisherSource -Algorithm SHA256).Hash
$completed = $false

# No fixture can contact a network remote or inherit a real index/worktree from
# the caller. These process-only environment settings are restored in finally.
$gitEnvironmentNames = @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_COMMON_DIR',
    'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_GLOBAL',
    'GIT_CONFIG_SYSTEM', 'GIT_CONFIG_NOSYSTEM', 'GIT_ALLOW_PROTOCOL',
    'GIT_TERMINAL_PROMPT')
$savedGitEnvironment = @{}
foreach ($name in $gitEnvironmentNames) {
    $savedGitEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $null, 'Process')
}
$emptyGitConfig = Join-Path $scratch 'empty.gitconfig'
[IO.File]::WriteAllText($emptyGitConfig, '')
[Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $emptyGitConfig, 'Process')
[Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1', 'Process')
[Environment]::SetEnvironmentVariable('GIT_ALLOW_PROTOCOL', 'file', 'Process')
[Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0', 'Process')

function Assert-True {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw ('PUBLISH SCRIPT FAIL: ' + $Description) }
    $script:AssertionCount++
}

function Write-FixtureFile {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-TestNative {
    param([string]$Executable, [string[]]$NativeArguments)
    $priorPreference = $ErrorActionPreference
    try {
        # Windows PowerShell wraps native stderr as ErrorRecord even for a
        # successful git push; preserve it as evidence instead of terminating.
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Executable @NativeArguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $priorPreference }
    return [pscustomobject]@{
        ExitCode = [int]$code
        Text = (($lines | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    }
}

function Invoke-TestGit {
    param([string]$Repository, [string[]]$GitArguments, [int]$ExpectedExit = 0)
    $result = Invoke-TestNative $script:GitExe (@('-C', $Repository) + $GitArguments)
    if ($result.ExitCode -ne $ExpectedExit) {
        throw ('Fixture git failed: ' + ($GitArguments -join ' ') + "`n" + $result.Text)
    }
    return $result.Text
}

function Invoke-TestGitSeparated {
    param([string]$Repository, [string[]]$GitArguments, [string]$StderrPath)
    $priorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $stdout = @(& $script:GitExe -C $Repository @GitArguments 2> $StderrPath)
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $priorPreference }
    return [pscustomobject]@{
        ExitCode = [int]$code
        Stdout = (($stdout | ForEach-Object { $_.ToString() }) -join "`n").Trim()
        Stderr = [IO.File]::ReadAllText($StderrPath)
    }
}

function Set-FixtureIndexInfo {
    param([string]$Repository, [string]$IndexInfo)
    # Raw stdin preserves the exact LF/tab index-info protocol in Windows
    # PowerShell 5.1. No shell interpretation or dynamic command line is used.
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $script:GitExe
    $start.Arguments = 'update-index --index-info'
    $start.WorkingDirectory = $Repository
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $process.StandardInput.Write($IndexInfo)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ('Fixture update-index failed: ' + $stdout + $stderr) }
    }
    finally { $process.Dispose() }
}

function Invoke-Publisher {
    param([string]$Repository, [string[]]$PublishArguments = @())
    # A publisher accidentally using the caller's current directory encounters
    # an empty test-owned directory, never the real project repository.
    Push-Location -LiteralPath $script:CallerDirectory
    try {
        return Invoke-TestNative $script:PowerShellExe (@('-NoProfile', '-NonInteractive',
            '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Repository 'tools\publish_demo.ps1')) + $PublishArguments)
    }
    finally { Pop-Location }
}

function Configure-FixtureIdentity {
    param([string]$Repository)
    [void](Invoke-TestGit $Repository @('config', 'user.name', 'Publish Smoke Fixture'))
    [void](Invoke-TestGit $Repository @('config', 'user.email', 'publish-smoke@example.invalid'))
    [void](Invoke-TestGit $Repository @('config', 'core.autocrlf', 'false'))
    [void](Invoke-TestGit $Repository @('config', 'commit.gpgsign', 'false'))
    [void](Invoke-TestGit $Repository @('config', 'tag.gpgsign', 'false'))
}

function New-Fixture {
    param([string]$Name, [string]$SeedTag = 'v0.1.1-demo', [switch]$NoRemoteBranch)
    $root = Join-Path $script:Scratch $Name
    $repo = Join-Path $root 'work'
    $origin = Join-Path $root 'origin.git'
    [void][IO.Directory]::CreateDirectory($root)
    [void](Invoke-TestGit $root @('init', '--bare', '--initial-branch=main', $origin))
    [void](Invoke-TestGit $root @('init', '--initial-branch=main', $repo))
    Configure-FixtureIdentity $repo
    Write-FixtureFile (Join-Path $repo 'project.godot') "config_version=5`n`n[application]`nconfig/name=`"Publish Smoke Fixture`"`n"
    Write-FixtureFile (Join-Path $repo '.gitignore') ".demo-data/`n.build/`n.godot/`nexports/`n*.keystore`n.env`n"
    Write-FixtureFile (Join-Path $repo '.github\workflows\release.yml') @'
name: Fixture Release
on:
  push:
    tags:
      - 'v*'
jobs:
  package:
    runs-on: ubuntu-latest
    steps:
      - run: echo local-fixture-only
'@
    Write-FixtureFile (Join-Path $repo 'game.txt') "initial`n"
    [void][IO.Directory]::CreateDirectory((Join-Path $repo 'tools'))
    Copy-Item -LiteralPath $script:PublisherSource -Destination (Join-Path $repo 'tools\publish_demo.ps1')
    [void](Invoke-TestGit $repo @('add', '--all'))
    [void](Invoke-TestGit $repo @('commit', '-m', 'Fixture initial commit'))
    [void](Invoke-TestGit $repo @('remote', 'add', 'origin', $origin))
    [void](Invoke-TestGit $repo @('push', '-u', 'origin', 'main'))
    $branch = 'codex/publish-smoke'
    [void](Invoke-TestGit $repo @('checkout', '-b', $branch))
    if (-not $NoRemoteBranch) {
        [void](Invoke-TestGit $repo @('push', '-u', 'origin', $branch))
    }
    if (-not [string]::IsNullOrEmpty($SeedTag)) {
        [void](Invoke-TestGit $repo @('tag', $SeedTag))
        [void](Invoke-TestGit $repo @('push', 'origin', ('refs/tags/' + $SeedTag)))
    }
    return @{ Root = $root; Repo = $repo; Origin = $origin; Branch = $branch;
        InitialHead = (Invoke-TestGit $repo @('rev-parse', 'HEAD')) }
}

function Index-Snapshot {
    param([string]$Repository)
    # Compare staged paths/modes/blob IDs, not incidental index stat-cache bytes.
    return Invoke-TestGit $Repository @('ls-files', '--stage')
}

function Git-LocalPath {
    param([string]$Repository, [string]$Name)
    $path = Invoke-TestGit $Repository @('rev-parse', '--git-path', $Name)
    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Repository $path }
    return [IO.Path]::GetFullPath($path)
}

function Assert-RemoteRelease {
    param([hashtable]$Fixture, [string]$Version, [string]$Commit)
    $remoteBranch = Invoke-TestGit $Fixture.Origin @('rev-parse', ('refs/heads/' + $Fixture.Branch))
    $remoteTag = Invoke-TestGit $Fixture.Origin @('rev-parse', ('refs/tags/' + $Version + '^{}'))
    Assert-True ($remoteBranch -eq $Commit -and $remoteTag -eq $Commit) 'branch and release tag point to the exact same commit'
    Assert-True ((Invoke-TestGit $Fixture.Origin @('rev-parse', 'refs/heads/main')) -eq $Fixture.InitialHead) 'publishing a feature branch never pushes another branch'
}

try {
    $fixture = New-Fixture 'standard'
    $repo = $fixture.Repo
    [void](Invoke-TestGit $repo @('config', 'push.followTags', 'true'))
    [void](Invoke-TestGit $repo @('tag', '-a', 'local-review-note', '-m', 'Keep this annotated tag local'))
    Write-FixtureFile (Join-Path $repo 'game.txt') "changed gameplay`n"
    Write-FixtureFile (Join-Path $repo 'new-asset.txt') "new asset`n"
    Write-FixtureFile (Join-Path $repo 'already-staged.txt') "user staged change`n"
    [void](Invoke-TestGit $repo @('add', '--', 'already-staged.txt'))
    Write-FixtureFile (Join-Path $repo '.demo-data\progression.cfg') 'PRIVATE_SAVE_SENTINEL'
    Write-FixtureFile (Join-Path $repo '.demo-data\catalogue.cfg') 'PRIVATE_CATALOGUE_SENTINEL'
    Write-FixtureFile (Join-Path $repo 'exports\fixture.zip') 'EXPORTED_BINARY_SENTINEL'
    Write-FixtureFile (Join-Path $repo '.env') 'PRIVATE_ENV_SENTINEL'
    $indexBefore = Index-Snapshot $repo
    $statusBefore = Invoke-TestGit $repo @('status', '--porcelain=v1', '--untracked-files=all')
    $tagsBefore = Invoke-TestGit $repo @('tag', '--list')
    $remoteBefore = Invoke-TestGit $fixture.Origin @('show-ref')
    $fetchHead = Git-LocalPath $repo 'FETCH_HEAD'
    Assert-True (-not (Test-Path -LiteralPath $fetchHead)) 'fixture begins without fetch evidence'
    $result = Invoke-Publisher $repo @('-DryRun')
    Assert-True ($result.ExitCode -eq 0) ('dry run succeeds: ' + $result.Text)
    Assert-True ($result.Text.Contains('v0.1.2-demo')) 'dry run proposes the next patch demo version'
    Assert-True ((Index-Snapshot $repo) -eq $indexBefore) 'dry run preserves the existing staged changes'
    Assert-True ((Invoke-TestGit $repo @('status', '--porcelain=v1', '--untracked-files=all')) -eq $statusBefore) 'dry run preserves tracked and untracked work'
    Assert-True ((Invoke-TestGit $repo @('rev-parse', 'HEAD')) -eq $fixture.InitialHead) 'dry run creates no commit'
    Assert-True ((Invoke-TestGit $repo @('tag', '--list')) -eq $tagsBefore) 'dry run creates no local tag'
    Assert-True ((Invoke-TestGit $fixture.Origin @('show-ref')) -eq $remoteBefore) 'dry run changes no remote refs'
    Assert-True (-not (Test-Path -LiteralPath $fetchHead)) 'dry run performs no fetch write'
    Assert-True (-not (Test-Path -LiteralPath (Git-LocalPath $repo 'publish-demo-pending.json'))) 'dry run leaves no pending publication marker'

    $result = Invoke-Publisher $repo @('-Message', 'Fixture release commit')
    Assert-True ($result.ExitCode -eq 0) ('default release succeeds: ' + $result.Text)
    $publishedHead = Invoke-TestGit $repo @('rev-parse', 'HEAD')
    Assert-True ($publishedHead -ne $fixture.InitialHead) 'all nonignored changes create a new commit'
    Assert-RemoteRelease $fixture 'v0.1.2-demo' $publishedHead
    Assert-True ((Invoke-TestGit $repo @('cat-file', '-t', 'refs/tags/local-review-note')) -eq 'tag') 'fixture keeps an extra annotated tag reachable from the release commit'
    Assert-True (-not ((Invoke-TestGit $fixture.Origin @('tag', '--list')) -split "`n" -contains 'local-review-note')) 'push.followTags=true never publishes an unrelated annotated tag'
    $tracked = (Invoke-TestGit $repo @('ls-tree', '-r', '--name-only', 'HEAD')) -split "`n"
    Assert-True ($tracked -contains 'new-asset.txt' -and $tracked -contains 'already-staged.txt') 'new files and previously staged changes enter the same release commit'
    Assert-True (@($tracked | Where-Object { $_ -match '^(\.demo-data/|exports/|\.env$)' }).Count -eq 0) 'ignored player saves, exports and local environment files stay untracked'
    Assert-True (([IO.File]::ReadAllText((Join-Path $repo '.demo-data\progression.cfg'))) -eq 'PRIVATE_SAVE_SENTINEL') 'publishing preserves ignored save bytes'
    Assert-True ((Invoke-TestGit $repo @('show', '-s', '--format=%s', 'HEAD')) -eq 'Fixture release commit') 'explicit commit message is used verbatim'
    Assert-True ([string]::IsNullOrEmpty((Invoke-TestGit $repo @('status', '--porcelain=v1')))) 'successful publication leaves no nonignored work behind'

    Write-FixtureFile (Join-Path $repo 'duplicate-guard.txt') "must stay uncommitted`n"
    $indexBefore = Index-Snapshot $repo
    $result = Invoke-Publisher $repo @('-Version', 'v0.1.2-demo')
    Assert-True ($result.ExitCode -ne 0) 'an already published version is rejected'
    Assert-True ((Index-Snapshot $repo) -eq $indexBefore -and (Invoke-TestGit $repo @('rev-parse', 'HEAD')) -eq $publishedHead) 'duplicate rejection leaves both index and HEAD unchanged'
    Assert-True ([IO.File]::ReadAllText((Join-Path $repo 'duplicate-guard.txt')).Contains('must stay uncommitted')) 'duplicate rejection preserves the pending worktree file'
    [IO.File]::Delete((Join-Path $repo 'duplicate-guard.txt'))
    $result = Invoke-Publisher $repo
    Assert-True ($result.ExitCode -eq 0) ('clean-tree publication succeeds: ' + $result.Text)
    Assert-True ((Invoke-TestGit $repo @('rev-parse', 'HEAD')) -eq $publishedHead) 'a clean release reuses HEAD instead of creating an empty commit'
    Assert-RemoteRelease $fixture 'v0.1.3-demo' $publishedHead

    # The next version must consider the remote even when its highest tag has
    # not been fetched locally, and always use the agreed -demo output suffix.
    [void](Invoke-TestGit $fixture.Origin @('tag', 'v2.3.9', $publishedHead))
    Assert-True (-not (Invoke-TestGit $repo @('tag', '--list')).Contains('v2.3.9')) 'highest version initially exists only at the publish target'
    $result = Invoke-Publisher $repo
    Assert-True ($result.ExitCode -eq 0) ('remote-highest release succeeds: ' + $result.Text)
    Assert-RemoteRelease $fixture 'v2.3.10-demo' $publishedHead

    [void](Invoke-TestGit $repo @('tag', 'v8.0.0-demo'))
    $indexBefore = Index-Snapshot $repo
    $remoteBefore = Invoke-TestGit $fixture.Origin @('show-ref')
    $result = Invoke-Publisher $repo @('-Version', 'v8.0.0-demo')
    Assert-True ($result.ExitCode -ne 0) 'an arbitrary existing local tag is not treated as a retry without a pending marker'
    Assert-True ((Index-Snapshot $repo) -eq $indexBefore -and (Invoke-TestGit $fixture.Origin @('show-ref')) -eq $remoteBefore) 'unmarked local-tag rejection preserves index and remote refs'

    $empty = New-Fixture 'without-tags' ''
    $result = Invoke-Publisher $empty.Repo
    Assert-True ($result.ExitCode -eq 0) ('first release succeeds: ' + $result.Text)
    Assert-RemoteRelease $empty 'v0.1.0-demo' $empty.InitialHead

    [void](Invoke-TestGit $empty.Repo @('checkout', '--detach', 'HEAD'))
    $indexBefore = Index-Snapshot $empty.Repo
    $result = Invoke-Publisher $empty.Repo
    Assert-True ($result.ExitCode -ne 0) 'detached HEAD cannot silently select a destination branch'
    Assert-True ((Index-Snapshot $empty.Repo) -eq $indexBefore -and (Invoke-TestGit $empty.Repo @('rev-parse', 'HEAD')) -eq $empty.InitialHead) 'detached rejection preserves index and HEAD'

    $newBranch = New-Fixture -Name 'first-remote-branch' -NoRemoteBranch
    $result = Invoke-Publisher $newBranch.Repo
    Assert-True ($result.ExitCode -eq 0) ('first publication of a local branch succeeds: ' + $result.Text)
    Assert-RemoteRelease $newBranch 'v0.1.2-demo' $newBranch.InitialHead

    $diverged = New-Fixture 'diverged'
    $peer = Join-Path $diverged.Root 'peer'
    [void](Invoke-TestGit $diverged.Root @('clone', '--branch', $diverged.Branch, '--no-hardlinks', $diverged.Origin, $peer))
    Configure-FixtureIdentity $peer
    Write-FixtureFile (Join-Path $peer 'remote-change.txt') "remote collaborator change`n"
    [void](Invoke-TestGit $peer @('add', '--all'))
    [void](Invoke-TestGit $peer @('commit', '-m', 'Remote branch advance'))
    [void](Invoke-TestGit $peer @('push', 'origin', $diverged.Branch))
    Write-FixtureFile (Join-Path $diverged.Repo 'local-change.txt') "independent local commit`n"
    [void](Invoke-TestGit $diverged.Repo @('add', '--all'))
    [void](Invoke-TestGit $diverged.Repo @('commit', '-m', 'Local branch divergence'))
    Write-FixtureFile (Join-Path $diverged.Repo 'staged-next.txt') "must remain staged`n"
    [void](Invoke-TestGit $diverged.Repo @('add', '--', 'staged-next.txt'))
    Write-FixtureFile (Join-Path $diverged.Repo 'unstaged-next.txt') "must remain untracked`n"
    $indexBefore = Index-Snapshot $diverged.Repo
    $headBefore = Invoke-TestGit $diverged.Repo @('rev-parse', 'HEAD')
    $remoteBefore = Invoke-TestGit $diverged.Origin @('show-ref')
    $result = Invoke-Publisher $diverged.Repo
    Assert-True ($result.ExitCode -ne 0) 'diverged remote branch is rejected without merging or force-pushing'
    Assert-True ((Index-Snapshot $diverged.Repo) -eq $indexBefore) 'divergence failure does not stage or replace user index contents'
    Assert-True ((Invoke-TestGit $diverged.Repo @('rev-parse', 'HEAD')) -eq $headBefore) 'divergence failure does not create a commit'
    Assert-True ((Invoke-TestGit $diverged.Origin @('show-ref')) -eq $remoteBefore) 'divergence failure changes no remote refs'
    Assert-True (-not (Invoke-TestGit $diverged.Repo @('tag', '--list')).Contains('v0.1.2-demo')) 'divergence failure does not leave a release tag'

    $conflict = New-Fixture 'unmerged'
    [void](Invoke-TestGit $conflict.Repo @('checkout', '-b', 'conflict-side'))
    Write-FixtureFile (Join-Path $conflict.Repo 'game.txt') "other branch contents`n"
    [void](Invoke-TestGit $conflict.Repo @('add', '--all'))
    [void](Invoke-TestGit $conflict.Repo @('commit', '-m', 'Conflicting side'))
    [void](Invoke-TestGit $conflict.Repo @('checkout', $conflict.Branch))
    Write-FixtureFile (Join-Path $conflict.Repo 'game.txt') "current branch contents`n"
    [void](Invoke-TestGit $conflict.Repo @('add', '--all'))
    [void](Invoke-TestGit $conflict.Repo @('commit', '-m', 'Conflicting current branch'))
    [void](Invoke-TestGit $conflict.Repo @('merge', '--no-edit', 'conflict-side') -ExpectedExit 1)
    $indexBefore = Index-Snapshot $conflict.Repo
    Assert-True (-not [string]::IsNullOrEmpty((Invoke-TestGit $conflict.Repo @('ls-files', '--unmerged')))) 'fixture contains a real unresolved merge'
    $headBefore = Invoke-TestGit $conflict.Repo @('rev-parse', 'HEAD')
    $result = Invoke-Publisher $conflict.Repo
    Assert-True ($result.ExitCode -ne 0) 'an in-progress conflicted merge is rejected'
    Assert-True ((Index-Snapshot $conflict.Repo) -eq $indexBefore -and (Invoke-TestGit $conflict.Repo @('rev-parse', 'HEAD')) -eq $headBefore) 'merge rejection never stages conflict markers or resolves the index'

    # Git can report a CRLF conversion warning on stderr while its conflict
    # listing is correctly empty on stdout. Warning text is never a filename.
    $lineEndings = New-Fixture 'line-ending-warning'
    [void](Invoke-TestGit $lineEndings.Repo @('config', 'core.autocrlf', 'true'))
    [void](Invoke-TestGit $lineEndings.Repo @('config', 'core.safecrlf', 'warn'))
    $lfContents = "changed LF-only gameplay`nsecond LF-only line`n"
    Write-FixtureFile (Join-Path $lineEndings.Repo 'game.txt') $lfContents
    $diagnostic = Invoke-TestGitSeparated $lineEndings.Repo @('diff', '--name-only', '--diff-filter=U') (Join-Path $lineEndings.Root 'diff-unmerged.stderr.txt')
    Assert-True ($diagnostic.ExitCode -eq 0 -and [string]::IsNullOrEmpty($diagnostic.Stdout)) 'LF fixture has no unmerged paths on the actual git stdout stream'
    Assert-True ($diagnostic.Stderr -match 'LF.*CRLF') 'the same conflict query emits a genuine LF-to-CRLF warning on stderr'
    $indexBefore = Index-Snapshot $lineEndings.Repo
    $result = Invoke-Publisher $lineEndings.Repo @('-DryRun')
    Assert-True ($result.ExitCode -eq 0) ('line-ending warnings do not masquerade as conflicts during dry run: ' + $result.Text)
    Assert-True ((Index-Snapshot $lineEndings.Repo) -eq $indexBefore) 'warning-only dry run leaves staged content unchanged'
    Assert-True ((Invoke-TestGit $lineEndings.Repo @('rev-parse', 'HEAD')) -eq $lineEndings.InitialHead) 'warning-only dry run creates no commit'
    $result = Invoke-Publisher $lineEndings.Repo
    Assert-True ($result.ExitCode -eq 0) ('line-ending warning allows commit, postcommit verification and push: ' + $result.Text)
    Assert-True ($result.Text -match 'LF.*CRLF') 'the successful publication still exposes the original conversion warning in its console output'
    $lfHead = Invoke-TestGit $lineEndings.Repo @('rev-parse', 'HEAD')
    Assert-True ($lfHead -ne $lineEndings.InitialHead) 'the LF-only change actually creates the release commit'
    Assert-RemoteRelease $lineEndings 'v0.1.2-demo' $lfHead
    $postcommit = Invoke-TestGitSeparated $lineEndings.Repo @('status', '--porcelain=v1') (Join-Path $lineEndings.Root 'postcommit-status.stderr.txt')
    Assert-True ($postcommit.ExitCode -eq 0 -and [string]::IsNullOrEmpty($postcommit.Stdout)) 'postcommit status is clean despite line-ending warnings'
    Assert-True ([IO.File]::ReadAllText((Join-Path $lineEndings.Repo 'game.txt')) -eq $lfContents) 'publication does not rewrite the working file line endings'

    # An unmerged index is possible without MERGE_HEAD (for example after
    # plumbing operations or interrupted tooling). Test actual staged blobs,
    # not a fabricated merge-state marker or conflict-looking worktree text.
    $indexOnly = New-Fixture 'index-only-conflict'
    $baseBlob = Invoke-TestGit $indexOnly.Repo @('rev-parse', 'HEAD:game.txt')
    Write-FixtureFile (Join-Path $indexOnly.Root 'ours.txt') "index ours`n"
    Write-FixtureFile (Join-Path $indexOnly.Root 'theirs.txt') "index theirs`n"
    $oursBlob = Invoke-TestGit $indexOnly.Repo @('hash-object', '-w', (Join-Path $indexOnly.Root 'ours.txt'))
    $theirsBlob = Invoke-TestGit $indexOnly.Repo @('hash-object', '-w', (Join-Path $indexOnly.Root 'theirs.txt'))
    $zeroBlob = '0' * $baseBlob.Length
    $indexInfo = "0 $zeroBlob`tgame.txt`n100644 $baseBlob 1`tgame.txt`n100644 $oursBlob 2`tgame.txt`n100644 $theirsBlob 3`tgame.txt`n"
    Set-FixtureIndexInfo $indexOnly.Repo $indexInfo
    Assert-True (-not (Test-Path -LiteralPath (Git-LocalPath $indexOnly.Repo 'MERGE_HEAD'))) 'index-conflict fixture has no MERGE_HEAD file'
    $unmerged = Invoke-TestGit $indexOnly.Repo @('ls-files', '--unmerged')
    Assert-True (($unmerged -split "`n").Count -eq 3) 'index-conflict fixture contains real base, ours and theirs stages'
    $indexBefore = Index-Snapshot $indexOnly.Repo
    $remoteBefore = Invoke-TestGit $indexOnly.Origin @('show-ref')
    $result = Invoke-Publisher $indexOnly.Repo @('-DryRun')
    Assert-True ($result.ExitCode -ne 0) 'dry run rejects a real unmerged index even without a merge marker'
    $result = Invoke-Publisher $indexOnly.Repo
    Assert-True ($result.ExitCode -ne 0) 'publication rejects a real unmerged index even without a merge marker'
    Assert-True ((Index-Snapshot $indexOnly.Repo) -eq $indexBefore -and (Invoke-TestGit $indexOnly.Repo @('rev-parse', 'HEAD')) -eq $indexOnly.InitialHead) 'index-only conflict rejection preserves all three stages and HEAD'
    Assert-True ((Invoke-TestGit $indexOnly.Origin @('show-ref')) -eq $remoteBefore) 'index-only conflict rejection never changes remote refs'

    $retry = New-Fixture 'atomic-retry'
    Write-FixtureFile (Join-Path $retry.Repo 'game.txt') "release awaiting a working push`n"
    $hook = Join-Path $retry.Origin 'hooks\pre-receive'
    Write-FixtureFile $hook "#!/bin/sh`necho fixture-reject-push >&2`nexit 1`n"
    $remoteBefore = Invoke-TestGit $retry.Origin @('show-ref')
    $result = Invoke-Publisher $retry.Repo
    Assert-True ($result.ExitCode -ne 0) 'server-side hook rejection is reported as publication failure'
    Assert-True ((Invoke-TestGit $retry.Origin @('show-ref')) -eq $remoteBefore) 'atomic rejection advances neither branch nor release tag'
    $retryHead = Invoke-TestGit $retry.Repo @('rev-parse', 'HEAD')
    Assert-True ($retryHead -ne $retry.InitialHead) 'failed push preserves the locally created release commit'
    Assert-True ((Invoke-TestGit $retry.Repo @('rev-parse', 'refs/tags/v0.1.2-demo^{}')) -eq $retryHead) 'failed push preserves the exact local release tag'
    $pending = Git-LocalPath $retry.Repo 'publish-demo-pending.json'
    Assert-True (Test-Path -LiteralPath $pending -PathType Leaf) 'failed push retains a repository-private pending marker'
    $pendingBytes = [IO.File]::ReadAllBytes($pending)
    Assert-True (-not (Invoke-TestGit $retry.Repo @('ls-tree', '-r', '--name-only', 'HEAD')).Contains('publish-demo-pending.json')) 'pending retry state is never included in the release commit'
    [IO.File]::Delete($hook)
    $result = Invoke-Publisher $retry.Repo
    Assert-True ($result.ExitCode -eq 0) ('a second ordinary invocation resumes the pending release: ' + $result.Text)
    Assert-True ((Invoke-TestGit $retry.Repo @('rev-parse', 'HEAD')) -eq $retryHead) 'retry never creates a second release commit'
    Assert-RemoteRelease $retry 'v0.1.2-demo' $retryHead
    Assert-True (-not (Invoke-TestGit $retry.Repo @('tag', '--list')).Contains('v0.1.3-demo')) 'retry uses the pending version instead of consuming another patch version'
    Assert-True (-not (Test-Path -LiteralPath $pending)) 'successful retry clears its pending marker'

    # Simulate the process ending after the server accepted the atomic push but
    # before local retry metadata was removed. An ordinary second double-click
    # must acknowledge the already published version rather than create a new one.
    [IO.File]::WriteAllBytes($pending, $pendingBytes)
    $acceptedRefs = Invoke-TestGit $retry.Origin @('show-ref')
    $acceptedTags = Invoke-TestGit $retry.Repo @('tag', '--list')
    $result = Invoke-Publisher $retry.Repo
    Assert-True ($result.ExitCode -eq 0) ('already accepted pending publication is acknowledged: ' + $result.Text)
    Assert-True ((Invoke-TestGit $retry.Repo @('rev-parse', 'HEAD')) -eq $retryHead) 'acknowledging an accepted push creates no commit'
    Assert-True ((Invoke-TestGit $retry.Repo @('tag', '--list')) -eq $acceptedTags) 'acknowledging an accepted push creates no new version'
    Assert-True ((Invoke-TestGit $retry.Origin @('show-ref')) -eq $acceptedRefs) 'acknowledging an accepted push preserves all remote refs'
    Assert-True (-not (Test-Path -LiteralPath $pending)) 'acknowledged publication clears the leftover pending marker'

    $completed = $true
    Write-Output ('PUBLISH_SCRIPT_SMOKE_OK assertions=' + $script:AssertionCount +
        ' local_bare_only=true dry_run=true ignored_saves=true default_version=true current_branch=true duplicate_guard=true divergence_guard=true clean_release=true atomic_retry=true no_follow_tags=true accepted_pending=true warning_streams=true index_only_conflict=true source_sha256=' + $script:PublisherHash)
}
finally {
    foreach ($name in $gitEnvironmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedGitEnvironment[$name], 'Process')
    }
    if ($completed -and -not $KeepArtifacts) {
        $resolvedScratch = [IO.Path]::GetFullPath($scratch)
        $tempPrefix = $tempRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedScratch.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolvedScratch) -notlike 'moon-publish-smoke-*') {
            throw 'Refusing cleanup outside the verified temporary fixture directory.'
        }
        Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
    }
    else { Write-Output ('Test fixtures retained at: ' + $scratch) }
}
