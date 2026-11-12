param(
    [string]$Path = (Get-Location),
    [int]$MaxCount = 100,
    [switch]$AllBranches,
    [switch]$IncludePassed,
    [switch]$IncludeBranches,
    [string]$Export,
    [switch]$Summary,
    [switch]$OpenDashboard
)

$scriptDir = $PSScriptRoot

$shouldReview = $Export -or $Summary -or $PSBoundParameters.ContainsKey('Path') -or $PSBoundParameters.ContainsKey('IncludeBranches')

if ($shouldReview) {
    Import-Module (Join-Path -Path $scriptDir -ChildPath 'src\GitReviewAgent.psm1') -Force -ErrorAction Stop

    $review = Review-GitActions -Path $Path -MaxCount $MaxCount -AllBranches:$AllBranches -IncludePassed:$IncludePassed -IncludeBranches:$IncludeBranches

    if ($Export) {
        Export-GitReview -Review $review -OutPath $Export
        Write-Host "Exported review to: $Export"
    }

    if ($Summary) {
        Show-GitReviewSummary -Review $review
    }
}

if ($OpenDashboard) {
    $dashboard = Join-Path -Path $scriptDir -ChildPath 'dashboard\index.html'
    if (Test-Path -LiteralPath $dashboard) {
        Invoke-Item $dashboard
    } else {
        Write-Warning "Dashboard not found: $dashboard"
    }
}
