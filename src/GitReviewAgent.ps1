[CmdletBinding()]
param(
    [string]$Path = (Get-Location),
    [int]$MaxCount = 100,
    [switch]$AllBranches,
    [switch]$IncludePassed,
    [switch]$IncludeBranches,
    [string]$Export,
    [switch]$Summary
)

$moduleDir = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $moduleDir 'GitReviewAgent.psm1') -Force

$review = Review-GitActions -Path $Path -MaxCount $MaxCount -AllBranches:$AllBranches -IncludePassed:$IncludePassed -IncludeBranches:$IncludeBranches

if ($Export) {
    Export-GitReview -Review $review -OutPath $Export
    Write-Host "Exported review to: $Export"
}

if ($Summary) {
    Show-GitReviewSummary -Review $review
}

if (-not $Export -and -not $Summary) {
    $review | ConvertTo-Json -Depth 5
}
