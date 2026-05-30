<#
.SYNOPSIS
    Clone every GitHub repository referenced by VoltAgent/awesome-agent-skills.

.EXAMPLE
    .\clone-awesome-agent-skills-repos.ps1

.EXAMPLE
    .\clone-awesome-agent-skills-repos.ps1 -DestinationRoot D:\skills -ListOnly
#>
[CmdletBinding()]
param(
    [string]$DestinationRoot = (Join-Path $PSScriptRoot "..\..\awesome-agent-skills-repos"),
    [string]$ReadmeUrl = "https://raw.githubusercontent.com/VoltAgent/awesome-agent-skills/main/README.md",
    # Use a saved manifest (from export-awesome-agent-skills.ps1) instead of the live README.
    [string]$ManifestPath,
    # Print the discovered repos and exit without cloning.
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Get-AwesomeAgentSkillRepos.ps1")

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required but was not found in PATH."
}

if ($ManifestPath) {
    $repos = Import-AwesomeAgentSkillRepos -ManifestPath $ManifestPath
    $sourceLabel = $ManifestPath
}
else {
    $repos = Get-AwesomeAgentSkillRepos -Url $ReadmeUrl
    $sourceLabel = $ReadmeUrl
}
if (-not $repos -or $repos.Count -eq 0) {
    throw "No GitHub repositories were discovered in $sourceLabel"
}

if ($ListOnly) {
    $repos | Sort-Object Slug | Format-Table Slug, Source -AutoSize
    Write-Host "Discovered $($repos.Count) repositories."
    return
}

$DestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null

Write-Host "Discovered $($repos.Count) repositories. Destination: $DestinationRoot"

$cloned = 0
$skipped = 0
$failed = 0

foreach ($repo in $repos) {
    $targetPath = Join-Path $DestinationRoot $repo.LocalName

    if (Test-Path $targetPath) {
        Write-Host "SKIP  $($repo.Slug) (already exists)"
        $skipped++
        continue
    }

    Write-Host "CLONE $($repo.Slug)"
    # Treeless clone keeps history (so later pulls fast-forward cleanly) while
    # avoiding the cost of downloading every historical blob up front.
    git clone --filter=blob:none $repo.GitUrl $targetPath

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to clone $($repo.Slug)"
        $failed++
        continue
    }

    $cloned++
}

Write-Host "Done. Cloned: $cloned, Skipped: $skipped, Failed: $failed"
