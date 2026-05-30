<#
.SYNOPSIS
    Export the skills/repos listed in VoltAgent/awesome-agent-skills to a JSON
    manifest that the clone/pull scripts (and other tooling) can consume.

.DESCRIPTION
    Writes a single JSON file containing:
      * generatedFrom : the README URL it was built from
      * skillCount / repoCount
      * skills : one entry per skill link (Name, Slug, SubPath, SourceUrl, ...)
      * repos  : one entry per GitHub repo (Slug, GitUrl, LocalName, SkillCount)

    Run this periodically and diff the output to spot newly added skills/repos.

.EXAMPLE
    .\export-awesome-agent-skills.ps1

.EXAMPLE
    .\export-awesome-agent-skills.ps1 -OutputPath D:\skills\manifest.json
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\..\awesome-agent-skills.json"),
    [string]$ReadmeUrl = "https://raw.githubusercontent.com/VoltAgent/awesome-agent-skills/main/README.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Get-AwesomeAgentSkillRepos.ps1")

$skills = Get-AwesomeAgentSkills -Url $ReadmeUrl
if (-not $skills -or $skills.Count -eq 0) {
    throw "No skills were discovered in $ReadmeUrl"
}

$repos = Get-AwesomeAgentSkillRepos -Url $ReadmeUrl

$manifest = [ordered]@{
    generatedFrom = $ReadmeUrl
    skillCount    = $skills.Count
    repoCount     = $repos.Count
    repos         = @($repos | ForEach-Object {
        [ordered]@{
            slug       = $_.Slug
            gitUrl     = $_.GitUrl
            localName  = $_.LocalName
            skillCount = $_.SkillCount
            sources    = $_.Sources
        }
    })
    skills        = @($skills | Sort-Object Slug, SubPath | ForEach-Object {
        [ordered]@{
            name      = $_.Name
            slug      = $_.Slug
            subPath   = $_.SubPath
            sourceUrl = $_.SourceUrl
            source    = $_.Source
        }
    })
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$json = $manifest | ConvertTo-Json -Depth 6
# Write UTF-8 without BOM so the file is portable across tools.
[System.IO.File]::WriteAllText($OutputPath, $json, (New-Object System.Text.UTF8Encoding $false))

Write-Host "Wrote $($skills.Count) skills across $($repos.Count) repos to $OutputPath"
