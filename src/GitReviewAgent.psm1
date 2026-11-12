#requires -Version 5.1

$script:ReviewRules = @{
    MaxCommitMessageLength = 72
    MaxSubjectLength       = 50
    RequiredTypes          = @('feat','fix','docs','style','refactor','perf','test','build','ci','chore')
    ForbiddenWords         = @('fix','fixes','fixed','temp','todo','hack','quick','wip','asap')
    AllowedBranchPrefixes  = @('feature/','fix/','hotfix/','release/','docs/','chore/','refactor/','test/','perf/','build/','ci/')
    MaxBranchNameLength    = 50
    BaseBranchCandidates   = @('main','master','develop')
    MaxStaleDays           = 30
}

function Get-GitRepoPath {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location)
    )
    if (-not (Test-Path -LiteralPath $Path)) { throw "Path not found: $Path" }
    $gitDir = Join-Path $Path '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) {
        $parent = Split-Path -Parent $Path
        if ($parent -and $parent -ne $Path) { return Get-GitRepoPath -Path $parent }
        throw "Not a git repository: $Path"
    }
    return $Path
}

function Get-GitExePath {
    [CmdletBinding()]
    param()
    $candidates = @(
        (Get-Command git -ErrorAction SilentlyContinue).Source,
        'C:\Program Files\Git\bin\git.exe',
        'C:\Program Files (x86)\Git\bin\git.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\git.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
    }
    throw 'git executable not found. Install Git or add it to PATH.'
}

function Invoke-Git {
    [CmdletBinding()]
    param(
        [string]$RepoPath,
        [string[]]$Args
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Get-GitExePath
    $startInfo.Arguments = ($Args -join ' ')
    $startInfo.WorkingDirectory = $RepoPath
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start() | Out-Null
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "git $($Args -join ' ') failed: $stderr"
    }
    return $stdout
}

function Get-GitActions {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location),
        [int]$MaxCount = 100,
        [switch]$AllBranches
    )
    $repoPath = Get-GitRepoPath -Path $Path
    $args = @('log', '--pretty=format:%H%x09%an%x09%ae%x09%ad%x09%s%x09%b', '--date=iso-strict')
    if ($AllBranches) { $args += '--all' }
    if ($MaxCount -gt 0) { $args += '-n', $MaxCount }
    $raw = Invoke-Git -RepoPath $repoPath -Args $args
    $actions = @()
    foreach ($line in $raw -split "`n") {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 6
        if ($parts.Length -lt 5) { continue }
        $actions += [PSCustomObject]@{
            Hash       = $parts[0]
            ShortHash  = $parts[0].Substring(0, [math]::Min(7, $parts[0].Length))
            Author     = $parts[1]
            Email      = $parts[2]
            Date       = [datetime]$parts[3]
            Subject    = $parts[4]
            Body       = if ($parts.Length -ge 6) { $parts[5] } else { '' }
            RepoPath   = $repoPath
        }
    }
    return $actions
}

function Test-CommitSubject {
    [CmdletBinding()]
    param([string]$Subject)
    $issues = @()
    if ($Subject.Length -gt $script:ReviewRules.MaxSubjectLength) {
        $issues += [PSCustomObject]@{ Type = 'Warning'; Message = ("Subject exceeds {0} chars ({1})" -f $script:ReviewRules.MaxSubjectLength, $Subject.Length) }
    }
    $prefix = if ($Subject -match '^([^:]+):') { $Matches[1] } else { '' }
    if ($prefix -and -not ($script:ReviewRules.RequiredTypes -contains $prefix.ToLowerInvariant())) {
        $issues += [PSCustomObject]@{ Type = 'Info'; Message = "Non-standard commit type: '$prefix'" }
    }
    foreach ($word in $script:ReviewRules.ForbiddenWords) {
        if ($Subject -match "\b$word\b") {
            $issues += [PSCustomObject]@{ Type = 'Warning'; Message = "Forbidden word in subject: '$word'" }
        }
    }
    return $issues
}

function Test-CommitBody {
    [CmdletBinding()]
    param([string]$Body, [string]$Subject)
    $issues = @()
    if ([string]::IsNullOrWhiteSpace($Body) -and $Subject.Length -gt $script:ReviewRules.MaxSubjectLength) {
        $issues += [PSCustomObject]@{ Type = 'Info'; Message = 'Long subject with no body; consider adding a body' }
    }
    return $issues
}

function Get-GitBranches {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location)
    )
    $repoPath = Get-GitRepoPath -Path $Path
    $raw = Invoke-Git -RepoPath $repoPath -Args @('branch','-a','--format','%(refname:short)%09%(objectname:short)%09%(committerdate:iso-strict)')
    $branches = @()
    foreach ($line in $raw -split "`n") {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 3
        if ($parts.Length -lt 3) { continue }
        $name = $parts[0]
        $isRemote = $name -match '^remotes/'
        $displayName = if ($isRemote) { $name.Substring('remotes/'.Length) } else { $name }
        $branches += [PSCustomObject]@{
            Name        = $name
            DisplayName = $displayName
            IsRemote    = $isRemote
            IsCurrent   = $name -match '\*'
            ShortHash   = $parts[1]
            Date        = [datetime]$parts[2]
            RepoPath    = $repoPath
        }
    }
    return $branches
}

function Get-GitBaseBranch {
    [CmdletBinding()]
    param([string]$RepoPath)
    $existing = Invoke-Git -RepoPath $RepoPath -Args @('branch','--format','%(refname:short)')
    $existingNames = ($existing -split "`n") | Where-Object { $_ -notmatch '^\*' } | ForEach-Object { $_.Trim() }
    foreach ($candidate in $script:ReviewRules.BaseBranchCandidates) {
        if ($existingNames -contains $candidate) { return $candidate }
    }
    if ($existingNames.Count -gt 0) { return $existingNames[0] }
    return $null
}

function Get-GitAheadBehind {
    [CmdletBinding()]
    param(
        [string]$RepoPath,
        [string]$Branch,
        [string]$BaseBranch
    )
    try {
        $aheadRaw = Invoke-Git -RepoPath $RepoPath -Args @('rev-list','--count',"$BaseBranch..$Branch")
        $ahead = [int]::Parse(($aheadRaw -split "`n")[0].Trim())
    } catch { $ahead = 0 }
    try {
        $behindRaw = Invoke-Git -RepoPath $RepoPath -Args @('rev-list','--count',"$Branch..$BaseBranch")
        $behind = [int]::Parse(($behindRaw -split "`n")[0].Trim())
    } catch { $behind = 0 }
    return [PSCustomObject]@{ Ahead = $ahead; Behind = $behind }
}

function Test-BranchName {
    [CmdletBinding()]
    param([string]$BranchName)
    $issues = @()
    $shortName = $BranchName
    if ($shortName -match '^remotes/') { $shortName = $shortName.Substring('remotes/'.Length) }
    if ($shortName -match '^origin/') { $shortName = $shortName.Substring('origin/'.Length) }

    if ($shortName.Length -gt $script:ReviewRules.MaxBranchNameLength) {
        $issues += [PSCustomObject]@{ Type = 'Warning'; Message = ("Branch name exceeds {0} chars ({1})" -f $script:ReviewRules.MaxBranchNameLength, $shortName.Length) }
    }

    $hasValidPrefix = $false
    foreach ($prefix in $script:ReviewRules.AllowedBranchPrefixes) {
        if ($shortName -like "$prefix*") { $hasValidPrefix = $true; break }
    }
    if (-not $hasValidPrefix) {
        $issues += [PSCustomObject]@{ Type = 'Info'; Message = "Branch name does not use a standard prefix (expected one of: $($script:ReviewRules.AllowedBranchPrefixes -join ', '))" }
    }

    foreach ($word in $script:ReviewRules.ForbiddenWords) {
        if ($shortName -match "\b$word\b") {
            $issues += [PSCustomObject]@{ Type = 'Warning'; Message = "Forbidden word in branch name: '$word'" }
        }
    }
    return $issues
}

function Review-GitBranch {
    [CmdletBinding()]
    param(
        [object]$Branch,
        [string]$BaseBranch
    )
    $issues = @()
    $issues += Test-BranchName -BranchName $Branch.Name

    $aheadBehind = Get-GitAheadBehind -RepoPath $Branch.RepoPath -Branch $Branch.Name -BaseBranch $BaseBranch

    if ($aheadBehind.Behind -gt 0) {
        $issues += [PSCustomObject]@{ Type = 'Info'; Message = ("Branch is {0} commit(s) behind '{1}'; consider rebasing or merging" -f $aheadBehind.Behind, $BaseBranch) }
    }
    if ($aheadBehind.Ahead -eq 0 -and $aheadBehind.Behind -eq 0 -and $Branch.Name -ne $BaseBranch) {
        $issues += [PSCustomObject]@{ Type = 'Info'; Message = "Branch appears to be merged or identical to base branch" }
    }

    $daysStale = ((Get-Date) - $Branch.Date).TotalDays
    if ($daysStale -gt $script:ReviewRules.MaxStaleDays) {
        $issues += [PSCustomObject]@{ Type = 'Warning'; Message = ("Branch is stale ({0} days since last commit)" -f [math]::Round($daysStale)) }
    }

    $passed = ($issues.Count -eq 0)
    $isPrCandidate = ($Branch.Name -ne $BaseBranch -and -not $Branch.IsRemote -and $aheadBehind.Ahead -gt 0)

    return [PSCustomObject]@{
        Name          = $Branch.Name
        DisplayName   = $Branch.DisplayName
        IsRemote      = $Branch.IsRemote
        IsCurrent     = $Branch.IsCurrent
        ShortHash     = $Branch.ShortHash
        Date          = $Branch.Date
        BaseBranch    = $BaseBranch
        Ahead         = $aheadBehind.Ahead
        Behind        = $aheadBehind.Behind
        DaysStale     = [math]::Round($daysStale)
        IsPrCandidate = $isPrCandidate
        Passed        = $passed
        Issues        = $issues
        Severity      = if ($issues.Where{ $_.Type -eq 'Error' }) { 'Error' } elseif ($issues.Where{ $_.Type -eq 'Warning' }) { 'Warning' } else { 'Info' }
    }
}

function Review-GitBranches {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location)
    )
    $repoPath = Get-GitRepoPath -Path $Path
    $branches = Get-GitBranches -Path $Path
    $baseBranch = Get-GitBaseBranch -RepoPath $repoPath
    if (-not $baseBranch) {
        return [PSCustomObject]@{ BaseBranch = $null; Branches = @(); PrCandidates = @() }
    }
    $reviews = @()
    foreach ($branch in $branches) {
        $review = Review-GitBranch -Branch $branch -BaseBranch $baseBranch
        $reviews += $review
    }
    $prCandidates = $reviews | Where-Object { $_.IsPrCandidate }
    return [PSCustomObject]@{
        BaseBranch    = $baseBranch
        Branches      = $reviews
        PrCandidates  = $prCandidates
        TotalBranches = $reviews.Count
        PrCount       = $prCandidates.Count
    }
}

function Review-GitAction {
    [CmdletBinding()]
    param(
        [object]$Action,
        [switch]$IncludePassed
    )
    $issues = @()
    $issues += Test-CommitSubject -Subject $Action.Subject
    $issues += Test-CommitBody -Body $Action.Body -Subject $Action.Subject
    $passed = ($issues.Count -eq 0)
    return [PSCustomObject]@{
        Hash        = $Action.Hash
        ShortHash   = $Action.ShortHash
        Author      = $Action.Author
        Email       = $Action.Email
        Date        = $Action.Date
        Subject     = $Action.Subject
        Passed      = $passed
        Issues      = $issues
        Severity    = if ($issues.Where{ $_.Type -eq 'Error' }) { 'Error' } elseif ($issues.Where{ $_.Type -eq 'Warning' }) { 'Warning' } else { 'Info' }
    }
}

function Review-GitActions {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location),
        [int]$MaxCount = 100,
        [switch]$AllBranches,
        [switch]$IncludePassed,
        [switch]$IncludeBranches
    )
    $actions = Get-GitActions -Path $Path -MaxCount $MaxCount -AllBranches:$AllBranches
    $reviews = @()
    foreach ($action in $actions) {
        $review = Review-GitAction -Action $action -IncludePassed:$IncludePassed
        if ($IncludePassed -or -not $review.Passed) {
            $reviews += $review
        }
    }
    $branchReview = if ($IncludeBranches) { Review-GitBranches -Path $Path } else { $null }
    return [PSCustomObject]@{
        GeneratedAt = [datetime]::UtcNow
        RepoPath    = (Get-GitRepoPath -Path $Path)
        Total       = $actions.Count
        Reviewed    = $reviews.Count
        Passed      = ($reviews | Where-Object { $_.Passed }).Count
        Failed      = ($reviews | Where-Object { -not $_.Passed }).Count
        Reviews     = $reviews
        Branches    = $branchReview
    }
}

function Export-GitReview {
    [CmdletBinding()]
    param(
        [object]$Review,
        [string]$OutPath
    )
    $json = $Review | ConvertTo-Json -Depth 10
    $json | Set-Content -LiteralPath $OutPath -Encoding UTF8
    return $OutPath
}

function Show-GitReviewSummary {
    [CmdletBinding()]
    param([object]$Review)
    Write-Host "Git Review Summary" -ForegroundColor Cyan
    Write-Host ("Repo: " + $Review.RepoPath)
    Write-Host ("Generated: " + $Review.GeneratedAt)
    Write-Host ("Total actions: " + $Review.Total)
    Write-Host ("Reviewed: " + $Review.Reviewed)
    Write-Host ("Passed: " + $Review.Passed) -ForegroundColor Green
    Write-Host ("Failed: " + $Review.Failed) -ForegroundColor Red
    Write-Host ""
    foreach ($r in $Review.Reviews) {
        $color = if ($r.Severity -eq 'Error') { 'Red' } elseif ($r.Severity -eq 'Warning') { 'Yellow' } else { 'White' }
        Write-Host ("[{0}] {1} - {2}" -f $r.ShortHash, $r.Author, $r.Subject) -ForegroundColor $color
        foreach ($issue in $r.Issues) {
            Write-Host ("    - {0}: {1}" -f $issue.Type, $issue.Message) -ForegroundColor $color
        }
    }

    if ($Review.Branches) {
        Write-Host ""
        Write-Host "Branch Review" -ForegroundColor Cyan
        Write-Host ("Base branch: " + $Review.Branches.BaseBranch)
        Write-Host ("Total branches: " + $Review.Branches.TotalBranches)
        Write-Host ("PR candidates: " + $Review.Branches.PrCount) -ForegroundColor Green
        foreach ($b in $Review.Branches.Branches) {
            $color = if ($b.Severity -eq 'Error') { 'Red' } elseif ($b.Severity -eq 'Warning') { 'Yellow' } else { 'White' }
            $marker = if ($b.IsPrCandidate) { ' [PR candidate]' } else { '' }
            Write-Host ("[{0}] {1} - ahead={2} behind={3} stale={4}d{5}" -f $b.ShortHash, $b.DisplayName, $b.Ahead, $b.Behind, $b.DaysStale, $marker) -ForegroundColor $color
            foreach ($issue in $b.Issues) {
                Write-Host ("    - {0}: {1}" -f $issue.Type, $issue.Message) -ForegroundColor $color
            }
        }
    }
}

Export-ModuleMember -Function Get-GitRepoPath, Invoke-Git, Get-GitActions, Get-GitBranches, Get-GitBaseBranch, Get-GitAheadBehind, Review-GitAction, Review-GitActions, Review-GitBranches, Review-GitBranch, Export-GitReview, Show-GitReviewSummary, Test-CommitSubject, Test-CommitBody, Test-BranchName
