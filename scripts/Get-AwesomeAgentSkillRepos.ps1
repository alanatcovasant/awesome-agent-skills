<#
.SYNOPSIS
    Shared parser for the VoltAgent/awesome-agent-skills README.

.DESCRIPTION
    The README links to skills two ways:
      * https://officialskills.sh/<owner>/<repo>/<skill...>   (the majority)
      * https://github.com/<owner>/<repo>/...                 (direct links / subpaths)

    Both forms encode the GitHub owner/repo in the first two path segments.

    This file exposes two functions (dot-source it to reuse them):
      * Get-AwesomeAgentSkills      -> one entry per skill link (fine-grained)
      * Get-AwesomeAgentSkillRepos  -> one entry per GitHub repo (deduplicated)

    Links that are not actual skill repositories (image attachments, GitHub
    system pages, and the list's own promo/framework repos) are filtered out.
#>

Set-StrictMode -Version Latest

# GitHub path prefixes that are never user repositories.
$script:ReservedGitHubOwners = @(
    'user-attachments', 'sponsors', 'topics', 'features', 'marketplace',
    'apps', 'about', 'pricing', 'login', 'join', 'settings', 'notifications',
    'orgs', 'users', 'collections', 'explore', 'trending', 'search', 'readme'
)

# Specific repos that appear as badges / promo links rather than skills.
$script:DefaultExcludedSlugs = @(
    'VoltAgent/voltagent',
    'VoltAgent/awesome-agent-skills',
    'VoltAgent/awesome-codex-subagents'
)

$script:OwnerRepoPattern = '^[A-Za-z0-9_.-]+$'

function Get-AwesomeAgentSkills {
    <#
    .SYNOPSIS
        Return one entry per skill link found in the README.
    .OUTPUTS
        Objects with: Name, Owner, Repo, Slug, GitUrl, SubPath, SourceUrl, Source.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        # Additional owner/repo slugs to exclude, on top of the built-in defaults.
        [string[]]$ExcludeSlug = @()
    )

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
    $content = $response.Content

    $excluded = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($slug in ($script:DefaultExcludedSlugs + $ExcludeSlug)) {
        [void]$excluded.Add($slug)
    }

    # Match either host; capture the path up to the first whitespace/markdown/HTML
    # delimiter so we can split and interpret the segments ourselves.
    $linkPattern = 'https://(?<host>officialskills\.sh|github\.com)/(?<path>[^\s)\]"''<>]+)'
    $linkMatches = [regex]::Matches($content, $linkPattern)

    $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    $skills = New-Object System.Collections.Generic.List[object]

    foreach ($match in $linkMatches) {
        $linkHost = $match.Groups['host'].Value
        $segments = $match.Groups['path'].Value.Split('/')
        if ($segments.Count -lt 2) { continue }

        $owner = $segments[0]
        $repo = $segments[1] -replace '\.git$', ''

        if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) { continue }
        if ($owner -notmatch $script:OwnerRepoPattern -or $repo -notmatch $script:OwnerRepoPattern) { continue }
        if ($script:ReservedGitHubOwners -contains $owner.ToLowerInvariant()) { continue }

        $slug = "$owner/$repo"
        if ($excluded.Contains($slug)) { continue }

        # Best-effort skill sub-path within the repo.
        $rest = @()
        if ($segments.Count -gt 2) {
            $tail = @($segments[2..($segments.Count - 1)])
            if ($linkHost -eq 'github.com' -and $tail.Count -ge 2 -and @('tree', 'blob') -contains $tail[0]) {
                # github.com/<owner>/<repo>/tree/<branch>/<path...> -> drop "tree/<branch>"
                $rest = if ($tail.Count -gt 2) { @($tail[2..($tail.Count - 1)]) } else { @() }
            }
            else {
                $rest = $tail
            }
        }

        $rest = @($rest)
        $subPath = ($rest -join '/')
        $name = if ($rest.Count -gt 0) { $rest[-1] } else { $repo }

        # Deduplicate at skill granularity (repo + sub-path).
        $skillKey = "$slug|$subPath"
        if (-not $seen.Add($skillKey)) { continue }

        $skills.Add([pscustomobject]@{
            Name      = $name
            Owner     = $owner
            Repo      = $repo
            Slug      = $slug
            GitUrl    = "https://github.com/$slug.git"
            SubPath   = $subPath
            SourceUrl = $match.Value
            Source    = $linkHost
        })
    }

    return $skills
}

function Get-AwesomeAgentSkillRepos {
    <#
    .SYNOPSIS
        Return one entry per GitHub repo referenced by the README.
    .OUTPUTS
        Objects with: Owner, Repo, Slug, GitUrl, LocalName, SkillCount, Sources.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [string[]]$ExcludeSlug = @()
    )

    $skills = Get-AwesomeAgentSkills -Url $Url -ExcludeSlug $ExcludeSlug

    $repos = New-Object System.Collections.Generic.List[object]
    foreach ($group in ($skills | Group-Object Slug)) {
        $first = $group.Group[0]
        $sources = $group.Group | ForEach-Object Source | Sort-Object -Unique
        $repos.Add([pscustomobject]@{
            Owner      = $first.Owner
            Repo       = $first.Repo
            Slug       = $first.Slug
            GitUrl     = $first.GitUrl
            LocalName  = "$($first.Owner)--$($first.Repo)"
            SkillCount = $group.Count
            Sources    = ($sources -join ',')
        })
    }

    return ($repos | Sort-Object Slug)
}

function Import-AwesomeAgentSkillRepos {
    <#
    .SYNOPSIS
        Read the repo list from a manifest produced by export-awesome-agent-skills.ps1.
    .OUTPUTS
        Objects with: Owner, Repo, Slug, GitUrl, LocalName, SkillCount, Sources.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }

    $manifest = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json
    if (-not $manifest.repos) {
        throw "Manifest has no 'repos' array: $ManifestPath"
    }

    $repos = New-Object System.Collections.Generic.List[object]
    foreach ($r in $manifest.repos) {
        $owner, $repo = $r.slug.Split('/', 2)
        $repos.Add([pscustomobject]@{
            Owner      = $owner
            Repo       = $repo
            Slug       = $r.slug
            GitUrl     = $r.gitUrl
            LocalName  = $r.localName
            SkillCount = $r.skillCount
            Sources    = $r.sources
        })
    }

    return ($repos | Sort-Object Slug)
}
