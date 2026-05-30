<#
.SYNOPSIS
    Update the cloned awesome-agent-skills repositories, and report any repos
    that are listed but not yet cloned.

.DESCRIPTION
    By default the set of expected repos comes from the live README (or a saved
    manifest via -ManifestPath). Repos present on disk are pulled (fast-forward
    only); repos that are listed but missing locally are reported as "NEW" so you
    can clone them. Use -AllGitRepos to instead pull every git repo found on disk,
    regardless of the list.

.EXAMPLE
    .\pull-awesome-agent-skills-repos.ps1

.EXAMPLE
    .\pull-awesome-agent-skills-repos.ps1 -ManifestPath ..\..\awesome-agent-skills.json
#>
[CmdletBinding()]
param(
    [string]$DestinationRoot = (Join-Path $PSScriptRoot "..\..\awesome-agent-skills-repos"),
    [string]$ReadmeUrl = "https://raw.githubusercontent.com/VoltAgent/awesome-agent-skills/main/README.md",
    # Use a saved manifest (from export-awesome-agent-skills.ps1) instead of the live README.
    [string]$ManifestPath,
    # Pull every git repo found on disk, ignoring the list.
    [switch]$AllGitRepos
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Get-AwesomeAgentSkillRepos.ps1")

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required but was not found in PATH."
}

$DestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
if (-not (Test-Path $DestinationRoot)) {
    throw "Destination path not found: $DestinationRoot"
}

$targets = @()
$missing = @()

if ($AllGitRepos) {
    $targets = Get-ChildItem -Path $DestinationRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName ".git") } |
        ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Path = $_.FullName }
        }
}
else {
    if ($ManifestPath) {
        $repos = Import-AwesomeAgentSkillRepos -ManifestPath $ManifestPath
    }
    else {
        $repos = Get-AwesomeAgentSkillRepos -Url $ReadmeUrl
    }

    foreach ($repo in $repos) {
        $path = Join-Path $DestinationRoot $repo.LocalName
        if (Test-Path (Join-Path $path ".git")) {
            $targets += [pscustomobject]@{ Name = $repo.Slug; Path = $path }
        }
        else {
            $missing += $repo
        }
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Found $($missing.Count) newly listed repo(s) not yet cloned:"
    foreach ($repo in $missing) {
        Write-Host "  NEW   $($repo.Slug)"
    }
    Write-Host "Run clone-awesome-agent-skills-repos.ps1 to fetch them.`n"
}

if (-not $targets -or @($targets).Count -eq 0) {
    if ($missing.Count -gt 0) {
        Write-Host "Nothing to pull yet."
        return
    }
    throw "No repositories found to update under $DestinationRoot"
}

Write-Host "Updating $(@($targets).Count) repositories in $DestinationRoot"

$updated = 0
$failed = 0

foreach ($target in $targets) {
    Write-Host "PULL  $($target.Name)"
    git -C $target.Path pull --ff-only --prune

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to update $($target.Name)"
        $failed++
        continue
    }

    $updated++
}

Write-Host "Done. Updated: $updated, Failed: $failed, New (uncloned): $($missing.Count)"
