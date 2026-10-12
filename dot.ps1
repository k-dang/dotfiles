#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SCRIPT_NAME = "dot"
$VERSION = "0.1.0"

$DOTFILES_DIR = $PSScriptRoot
$SYNC_PAIRS = @()
$SKILL_DIRS = @(".claude/skills", ".agents/skills")

# Single source of truth for the skills add invocation. Referenced by the command
# itself, the argument dispatcher, and the top-level help so they cannot drift.
$SKILLS_ADD_USAGE = ".\dot.ps1 skills add <url> [--force] [--agents-only|--claude-only] [--all] [--dry-run] [--skill=NAME]"

function Write-Header {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Blue
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Resolve-Paths {
    $managedHomePath = Join-Path $DOTFILES_DIR "home"

    if (-not (Test-Path -LiteralPath $managedHomePath -PathType Container)) {
        $script:SYNC_PAIRS = @()
        return
    }

    $script:SYNC_PAIRS = @(
        Get-ChildItem -LiteralPath $managedHomePath -Force -Directory |
            Sort-Object -Property Name |
            ForEach-Object {
                [pscustomobject]@{
                    Label = $_.Name
                    Source = $_.FullName
                    Target = if ([string]::IsNullOrWhiteSpace($HOME)) { $null } else { Join-Path $HOME $_.Name }
                }
            }
    )
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Test-ManagedPaths {
    if ([string]::IsNullOrWhiteSpace($HOME)) {
        Write-ErrorMsg "HOME is not set"
        return $false
    }

    if (-not (Test-Path -LiteralPath $HOME -PathType Container)) {
        Write-ErrorMsg "Home directory does not exist: $HOME"
        return $false
    }

    $managedHomePath = Join-Path $DOTFILES_DIR "home"
    if (-not (Test-Path -LiteralPath $managedHomePath -PathType Container)) {
        Write-ErrorMsg "Managed home directory not found: $managedHomePath"
        return $false
    }

    if ($SYNC_PAIRS.Count -eq 0) {
        Write-ErrorMsg "No managed directories found under $managedHomePath"
        return $false
    }

    return $true
}

function Get-OrphanItems {
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][string]$SourceRoot
    )

    $directories = New-Object System.Collections.Generic.Queue[string]
    $directories.Enqueue($TargetRoot)

    while ($directories.Count -gt 0) {
        $directory = $directories.Dequeue()

        foreach ($item in Get-ChildItem -LiteralPath $directory -Force | Sort-Object -Property FullName) {
            $relativePath = $item.FullName.Substring($TargetRoot.Length).TrimStart([char[]]@('\', '/'))
            $sourcePath = Join-Path $SourceRoot $relativePath

            # Report the topmost orphan only. Everything under an orphaned directory is
            # orphaned too, so descending adds no information and buries the report
            # (node_modules, editor extensions, and caches run to thousands of entries).
            if (-not (Test-Path -LiteralPath $sourcePath)) {
                [pscustomobject]@{
                    RelativePath = $relativePath
                    IsDirectory = $item.PSIsContainer
                }
                continue
            }

            $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            if ($item.PSIsContainer -and -not $isReparsePoint) {
                $directories.Enqueue($item.FullName)
            }
        }
    }
}

function Invoke-SyncPath {
    param(
        [Parameter(Mandatory)]$SyncPair,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $SyncPair.Source -PathType Container)) {
        throw "Source directory not found: $($SyncPair.Source)"
    }

    if (Test-Path -LiteralPath $SyncPair.Target -PathType Container) {
        if ($DryRun) {
            Write-Info "Would use existing target directory: $($SyncPair.Target)"
        }
    }
    elseif ($DryRun) {
        Write-Info "Would create target directory: $($SyncPair.Target)"
    }
    else {
        Ensure-Directory -Path $SyncPair.Target
    }

    $items = @(Get-ChildItem -LiteralPath $SyncPair.Source -Force)
    if ($items.Count -eq 0) {
        Write-Warn "Source $($SyncPair.Label) is empty: $($SyncPair.Source)"
        return
    }

    foreach ($item in $items) {
        if ($DryRun) {
            Write-Info "Would copy $($item.Name) to $($SyncPair.Target)"
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $SyncPair.Target -Recurse -Force
        }
    }
}

function Invoke-Sync {
    param([switch]$DryRun)

    Write-Header "Syncing managed home directories"

    if (-not (Test-ManagedPaths)) {
        return 1
    }

    foreach ($syncPair in $SYNC_PAIRS) {
        Invoke-SyncPath -SyncPair $syncPair -DryRun:$DryRun
    }

    if ($DryRun) {
        Write-Success "Dry run complete for managed home directories"
        Write-Info "No files were copied"
    }
    else {
        Write-Success "Synced managed home directories"
        Write-Info "Non-destructive sync: existing extra files were not deleted"
    }

    return 0
}

function New-OrphanNode {
    return @{
        Children = @{}
        IsOrphan = $false
        IsDirectory = $false
    }
}

function Add-OrphanNode {
    param(
        [Parameter(Mandatory)][hashtable]$Root,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][bool]$IsDirectory
    )

    $node = $Root

    foreach ($segment in ($RelativePath -split '[\\/]')) {
        if (-not $node.Children.ContainsKey($segment)) {
            $node.Children[$segment] = New-OrphanNode
        }
        $node = $node.Children[$segment]
    }

    $node.IsOrphan = $true
    $node.IsDirectory = $IsDirectory
}

function Write-OrphanTree {
    param(
        [Parameter(Mandatory)][hashtable]$Node,
        [string]$Prefix = ""
    )

    $names = @($Node.Children.Keys | Sort-Object)

    for ($i = 0; $i -lt $names.Count; $i++) {
        $name = $names[$i]
        $child = $Node.Children[$name]
        $isLast = $i -eq ($names.Count - 1)

        # A node with children is a directory even when it is only there to group
        # orphans below it, so it is not itself reported as an orphan.
        $isDirectory = $child.IsDirectory -or $child.Children.Count -gt 0
        $label = if ($isDirectory) { "$name/" } else { $name }

        Write-Host "$Prefix$(if ($isLast) { "└─ " } else { "├─ " })" -ForegroundColor DarkGray -NoNewline
        if ($child.IsOrphan) {
            Write-Host $label -ForegroundColor Yellow
        }
        else {
            Write-Host $label -ForegroundColor DarkGray
        }

        if ($child.Children.Count -gt 0) {
            Write-OrphanTree -Node $child -Prefix "$Prefix$(if ($isLast) { "   " } else { "│  " })"
        }
    }
}

function Invoke-Orphans {
    Write-Header "Finding orphaned managed home paths"

    if (-not (Test-ManagedPaths)) {
        return 1
    }

    $orphanCount = 0
    $orphanedLabels = 0
    $issues = 0

    foreach ($syncPair in $SYNC_PAIRS) {
        if (-not (Test-Path -LiteralPath $syncPair.Source -PathType Container)) {
            Write-ErrorMsg "Source $($syncPair.Label) missing: $($syncPair.Source)"
            $issues++
            continue
        }

        if (-not (Test-Path -LiteralPath $syncPair.Target)) {
            Write-ErrorMsg "Target $($syncPair.Label) missing: $($syncPair.Target)"
            $issues++
            continue
        }

        if (-not (Test-Path -LiteralPath $syncPair.Target -PathType Container)) {
            Write-ErrorMsg "Target $($syncPair.Label) is not a directory: $($syncPair.Target)"
            $issues++
            continue
        }

        $targetItem = Get-Item -LiteralPath $syncPair.Target -Force
        $isReparsePoint = ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isReparsePoint) {
            Write-ErrorMsg "Target $($syncPair.Label) is a reparse point: $($syncPair.Target)"
            $issues++
            continue
        }

        $tree = New-OrphanNode
        $labelCount = 0

        foreach ($item in Get-OrphanItems -TargetRoot $targetItem.FullName -SourceRoot $syncPair.Source) {
            Add-OrphanNode -Root $tree -RelativePath $item.RelativePath -IsDirectory $item.IsDirectory
            $labelCount++
        }

        $orphanCount += $labelCount
        if ($labelCount -eq 0) {
            continue
        }

        $orphanedLabels++
        Write-Host ""
        Write-Host $syncPair.Label -ForegroundColor Blue -NoNewline
        Write-Host "  $labelCount orphaned" -ForegroundColor DarkGray
        Write-OrphanTree -Node $tree
    }

    if ($issues -gt 0) {
        Write-Header "Found $issues issue(s) while finding orphans"
        return 1
    }

    if ($orphanCount -eq 0) {
        Write-Success "No orphaned paths found"
    }
    else {
        $directoryWord = if ($orphanedLabels -eq 1) { "directory" } else { "directories" }
        Write-Host ""
        Write-Warn "$orphanCount orphaned path(s) in $orphanedLabels managed $directoryWord; no files were deleted"
    }

    return 0
}

function Get-StaleSkills {
    $stale = @{}

    foreach ($relativePath in $SKILL_DIRS) {
        $source = Join-Path $DOTFILES_DIR "home/$relativePath"
        $target = Join-Path $HOME $relativePath

        # Without a source there is nothing to compare against, and treating every
        # installed skill as stale would offer to delete all of them.
        if (-not (Test-Path -LiteralPath $source -PathType Container) -or
            -not (Test-Path -LiteralPath $target -PathType Container)) {
            continue
        }

        $managed = @(Get-ChildItem -LiteralPath $source -Directory -Force | ForEach-Object Name)

        foreach ($dir in Get-ChildItem -LiteralPath $target -Directory -Force) {
            # Dot-prefixed folders such as .trash are tool bookkeeping, not skills.
            if ($dir.Name.StartsWith(".") -or $dir.Name -in $managed) {
                continue
            }

            if (-not $stale.ContainsKey($dir.Name)) {
                $stale[$dir.Name] = [pscustomobject]@{
                    Name = $dir.Name
                    Locations = New-Object System.Collections.Generic.List[string]
                    Paths = New-Object System.Collections.Generic.List[string]
                }
            }

            $stale[$dir.Name].Locations.Add($relativePath.Split('/')[0])
            $stale[$dir.Name].Paths.Add($dir.FullName)
        }
    }

    $stale.Values | Sort-Object -Property Name
}

function Write-SelectionList {
    param(
        [Parameter(Mandatory)][string[]]$Labels,
        [Parameter(Mandatory)][bool[]]$Selected,
        [Parameter(Mandatory)][int]$Cursor
    )

    $esc = [char]27

    for ($i = 0; $i -lt $Labels.Count; $i++) {
        $pointer = if ($i -eq $Cursor) { ">" } else { " " }
        $mark = if ($Selected[$i]) { "[x]" } else { "[ ]" }
        $color = if ($i -eq $Cursor) { "Cyan" } elseif ($Selected[$i]) { "Yellow" } else { "Gray" }
        Write-Host "$esc[2K$pointer $mark $($Labels[$i])" -ForegroundColor $color
    }

    Write-Host "$esc[2K  up/down move, space toggle, a all, enter delete, esc cancel" -ForegroundColor DarkGray
}

function Select-Items {
    param([Parameter(Mandatory)][string[]]$Labels)

    $esc = [char]27
    $selected = New-Object bool[] $Labels.Count
    $cursor = 0
    $confirmed = $false

    Write-Host "$esc[?25l" -NoNewline
    try {
        Write-SelectionList -Labels $Labels -Selected $selected -Cursor $cursor

        while ($true) {
            $key = [Console]::ReadKey($true).Key

            if ($key -in [ConsoleKey]::UpArrow, [ConsoleKey]::K) {
                $cursor = ($cursor - 1 + $Labels.Count) % $Labels.Count
            }
            elseif ($key -in [ConsoleKey]::DownArrow, [ConsoleKey]::J) {
                $cursor = ($cursor + 1) % $Labels.Count
            }
            elseif ($key -eq [ConsoleKey]::Spacebar) {
                $selected[$cursor] = -not $selected[$cursor]
            }
            elseif ($key -eq [ConsoleKey]::A) {
                $selectAll = $selected -contains $false
                for ($i = 0; $i -lt $selected.Count; $i++) {
                    $selected[$i] = $selectAll
                }
            }
            elseif ($key -eq [ConsoleKey]::Enter) {
                $confirmed = $true
                break
            }
            elseif ($key -in [ConsoleKey]::Escape, [ConsoleKey]::Q) {
                break
            }
            else {
                continue
            }

            Write-Host "$esc[$($Labels.Count + 1)A" -NoNewline
            Write-SelectionList -Labels $Labels -Selected $selected -Cursor $cursor
        }
    }
    finally {
        Write-Host "$esc[?25h" -NoNewline
    }

    if ($confirmed) {
        for ($i = 0; $i -lt $selected.Count; $i++) {
            if ($selected[$i]) {
                $i
            }
        }
    }
}

function Invoke-Prune {
    param([switch]$DryRun)

    Write-Header "Finding skills not in home/"

    if (-not (Test-ManagedPaths)) {
        return 1
    }

    $stale = @(Get-StaleSkills)
    if ($stale.Count -eq 0) {
        Write-Success "No stale skills found"
        return 0
    }

    $width = ($stale | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $labels = @($stale | ForEach-Object { "$($_.Name.PadRight($width))  $($_.Locations -join ' ')" })

    if ($DryRun) {
        $labels | ForEach-Object { Write-Host "  $_" }
        Write-Info "No files were deleted"
        return 0
    }

    $chosen = @(Select-Items -Labels $labels)
    if ($chosen.Count -eq 0) {
        Write-Info "No skills deleted"
        return 0
    }

    foreach ($index in $chosen) {
        foreach ($path in $stale[$index].Paths) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    Write-Success "Deleted $($chosen.Count) skill(s)"
    return 0
}

function Invoke-Doctor {
    Write-Header "Running diagnostics"
    $issues = 0
    $homeAvailable = $false

    if (Test-Path -LiteralPath $DOTFILES_DIR -PathType Container) {
        Write-Success "Dotfiles directory found: $DOTFILES_DIR"
    }
    else {
        Write-ErrorMsg "Dotfiles directory not found: $DOTFILES_DIR"
        $issues++
    }

    if ([string]::IsNullOrWhiteSpace($HOME)) {
        Write-ErrorMsg "HOME is not set"
        $issues++
    }
    elseif (Test-Path -LiteralPath $HOME -PathType Container) {
        Write-Success "Home directory available: $HOME"
        $homeAvailable = $true
    }
    else {
        Write-ErrorMsg "Home directory does not exist: $HOME"
        $issues++
    }

    $managedHomePath = Join-Path $DOTFILES_DIR "home"
    if (-not (Test-Path -LiteralPath $managedHomePath -PathType Container)) {
        Write-ErrorMsg "Managed home directory not found: $managedHomePath"
        $issues++
    }
    elseif ($SYNC_PAIRS.Count -eq 0) {
        Write-ErrorMsg "No managed directories found under $managedHomePath"
        $issues++
    }
    else {
        Write-Success "Managed home directory found: $managedHomePath"
    }

    foreach ($syncPair in $SYNC_PAIRS) {
        if (Test-Path -LiteralPath $syncPair.Source -PathType Container) {
            Write-Success "Source $($syncPair.Label) exists: $($syncPair.Source)"
        }
        else {
            Write-ErrorMsg "Source $($syncPair.Label) missing: $($syncPair.Source)"
            $issues++
        }

        if (-not $homeAvailable) {
            continue
        }

        if (Test-Path -LiteralPath $syncPair.Target -PathType Container) {
            Write-Success "Target $($syncPair.Label) exists: $($syncPair.Target)"
        }
        elseif (Test-Path -LiteralPath $syncPair.Target) {
            Write-ErrorMsg "Target $($syncPair.Label) is not a directory: $($syncPair.Target)"
            $issues++
        }
        else {
            Write-ErrorMsg "Target $($syncPair.Label) missing: $($syncPair.Target)"
            $issues++
        }
    }

    if ($issues -eq 0) {
        Write-Header "All checks passed"
        return 0
    }

    Write-Header "Found $issues issue(s)"
    return 1
}

function ConvertFrom-GitHubTreeUrl {
    param([Parameter(Mandatory)][string]$Url)

    $uri = [System.Uri]$Url
    $hostName = $uri.Host.ToLowerInvariant()
    if ($hostName -ne "github.com" -and $hostName -ne "www.github.com") {
        throw "Expected a GitHub URL like https://github.com/owner/repo/tree/ref/path"
    }

    $parts = @($uri.AbsolutePath -split "/" | Where-Object { $_ -ne "" } | ForEach-Object { [System.Uri]::UnescapeDataString($_) })
    if ($parts.Count -lt 4) {
        throw "Expected a GitHub URL like https://github.com/owner/repo/tree/ref/path"
    }

    $owner = $parts[0]
    $repository = $parts[1]
    if ($repository.EndsWith(".git")) {
        $repository = $repository.Substring(0, $repository.Length - 4)
    }
    if ($parts[2] -ne "tree" -or [string]::IsNullOrWhiteSpace($parts[3])) {
        throw "URL must point to a file tree or skill directory (.../tree/<ref>/<path>)"
    }

    $ref = $parts[3]
    if ($parts.Count -lt 5) {
        throw "URL must point to a file tree or skill directory (.../tree/<ref>/<path>)"
    }
    $treePath = ($parts[4..($parts.Count - 1)] -join "/")

    return [pscustomobject]@{
        Owner = $owner
        Repository = $repository
        Ref = $ref
        Path = $treePath
    }
}

function Find-SkillSource {
    param([Parameter(Mandatory)][string]$SourceRoot)

    if (Test-Path -LiteralPath (Join-Path $SourceRoot "SKILL.md") -PathType Leaf) {
        return @(Get-Item -LiteralPath $SourceRoot)
    }

    $found = @(Get-ChildItem -LiteralPath $SourceRoot -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") -PathType Leaf
    } | Sort-Object -Property Name)

    return $found
}

function Get-SkillDescription {
    param([Parameter(Mandatory)][string]$SkillDirectory)

    $skillFile = Join-Path $SkillDirectory "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
        return $null
    }

    # Read the `description:` key out of the YAML frontmatter. Only the simple
    # one-line form is handled; a folded (> or |) block is reported as-is, which
    # is still more useful in a picker than no description at all. The closing
    # --- is the only terminator: every other frontmatter key is unindented.
    $inFrontmatter = $false
    foreach ($line in @(Get-Content -LiteralPath $skillFile -TotalCount 40 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*---\s*$') {
            if ($inFrontmatter) { break }
            $inFrontmatter = $true
            continue
        }
        if (-not $inFrontmatter) { continue }
        if ($line -match '^\s*description\s*:\s*(.*)$') {
            $value = $Matches[1].Trim()
            if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -gt 1) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            return $value.Trim()
        }
    }
    return $null
}

function Format-SkillLabel {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][string]$Description,
        [int]$MaxDescriptionLength = 72
    )

    if ([string]::IsNullOrWhiteSpace($Description)) {
        return $Name
    }

    $description = ($Description -replace '\s+', ' ').Trim()
    if ($description.Length -gt $MaxDescriptionLength) {
        $description = $description.Substring(0, $MaxDescriptionLength - 3) + "..."
    }

    return "$Name  $description"
}

function Select-SkillsInteractively {
    param(
        [Parameter(Mandatory)][array]$Skills,
        [Parameter(Mandatory)][hashtable]$Descriptions
    )

    $labels = @($Skills | ForEach-Object { Format-SkillLabel -Name $_.Name -Description $Descriptions[$_.Name] })

    # gum needs a real terminal. With stdin redirected it would block forever,
    # so fall through to the numbered prompt, which reads a pipe just fine.
    $gumUsable = (Get-Command gum -ErrorAction SilentlyContinue) -and -not [Console]::IsInputRedirected

    if ($gumUsable) {
        $selected = @($labels | gum choose --no-limit --header "Select skills to install")
        return @($Skills | Where-Object { $selected -contains (Format-SkillLabel -Name $_.Name -Description $Descriptions[$_.Name]) })
    }

    Write-Host "gum unavailable or stdin redirected; falling back to numbered prompt (or rerun with --all / --skill=NAME)."
    for ($i = 0; $i -lt $Skills.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $labels[$i])
    }

    # Re-prompt on bad input instead of aborting: the download has already
    # happened, so throwing away the whole run over a typo is the wrong trade.
    while ($true) {
        $answer = Read-Host "Enter numbers comma-separated, 'all', or blank to cancel"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return @()
        }
        if ($answer.Trim().ToLowerInvariant() -eq "all") {
            return $Skills
        }

        $picked = @()
        $bad = $null
        foreach ($token in ($answer -split ",")) {
            $trimmed = $token.Trim()
            $number = 0
            if ([int]::TryParse($trimmed, [ref]$number) -and $number -ge 1 -and $number -le $Skills.Count) {
                $picked += $Skills[$number - 1]
            }
            else {
                $bad = $trimmed
                break
            }
        }

        if ($bad) {
            Write-Warn "Not a valid selection: '$bad'. Pick 1-$($Skills.Count), or 'all'."
            continue
        }

        return @($picked | Sort-Object -Property Name -Unique)
    }
}

# Destructive steps ask first, but only when a human is there to answer. With
# stdin redirected (a script, a CI job) prompting would hang, so --force stands
# on its own and this returns true.
function Confirm-DestructiveAction {
    param(
        [Parameter(Mandatory)][string]$Verb,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][string]$Subject
    )

    if ([Console]::IsInputRedirected) {
        return $true
    }

    return Read-Confirmation -Verb $Verb -Count $Count -Subject $Subject
}

function Read-Confirmation {
    param(
        [Parameter(Mandatory)][string]$Verb,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][string]$Subject
    )

    $noun = if ($Count -eq 1) { $Subject } else { "${Subject}s" }
    while ($true) {
        $answer = Read-Host "${Verb} $Count existing ${noun}? [y/N]"
        if ($null -eq $answer -or [string]::IsNullOrWhiteSpace($answer)) {
            return $false
        }
        switch ($answer.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-Warn "Please answer y or n." }
        }
    }
}

function Invoke-SkillsAdd {
    param(
        [string[]]$AddArgs,
        [switch]$DryRun
    )

    $url = $null
    $force = $false
    $agentsOnly = $false
    $claudeOnly = $false
    $installAll = $false
    $wanted = New-Object System.Collections.Generic.List[string]

    foreach ($arg in $AddArgs) {
        switch ($arg) {
            "--force" { $force = $true }
            "--agents-only" { $agentsOnly = $true }
            "--claude-only" { $claudeOnly = $true }
            "--all" { $installAll = $true }
            "--dry-run" { $DryRun = $true }
            "--help" {
                Write-Host "USAGE:"
                Write-Host "  $SKILLS_ADD_USAGE"
                Write-Host ""
                Write-Host "  <url>  GitHub tree URL containing one skill or multiple skill directories"
                Write-Host "         e.g. https://github.com/owner/repo/tree/main/skills"
                Write-Host ""
                Write-Host "  Prompts for which skills to install unless --all or --skill=NAME is given."
                Write-Host ""
                Write-Host "  --force  Replace skills that are already installed (asks first on an interactive terminal)"
                Write-Host "  Branch names containing a slash must be percent-encoded (feature%2Fx)."
                return 0
            }
            default {
                if ($arg -eq "-h") {
                    Write-Host "USAGE:"
                    Write-Host "  $SKILLS_ADD_USAGE"
                    return 0
                }
                elseif ($arg.StartsWith("--skill=")) {
                    [void]$wanted.Add($arg.Substring("--skill=".Length))
                }
                elseif ($arg.StartsWith("--skill")) {
                    throw "Use --skill=NAME (repeatable)"
                }
                elseif ($arg.StartsWith("--")) {
                    throw "Unknown option for skills add: $arg"
                }
                elseif ($null -eq $url) {
                    $url = $arg
                }
                else {
                    throw "Unexpected argument for skills add: $arg"
                }
            }
        }
    }

    if ($agentsOnly -and $claudeOnly) {
        throw "Options --agents-only and --claude-only are mutually exclusive"
    }
    if ([string]::IsNullOrWhiteSpace($url)) {
        throw "Missing required <url>. Usage: $SKILLS_ADD_USAGE"
    }
    if ($installAll -and $wanted.Count -gt 0) {
        throw "Options --all and --skill cannot be combined"
    }

    $tree = ConvertFrom-GitHubTreeUrl -Url $url
    $agentsRoot = Join-Path $DOTFILES_DIR "home/.agents/skills"
    $claudeRoot = Join-Path $DOTFILES_DIR "home/.claude/skills"
    $destRoots = @()
    if (-not $claudeOnly) {
        $destRoots += [pscustomobject]@{ Label = ".agents"; Root = $agentsRoot }
    }
    if (-not $agentsOnly) {
        $destRoots += [pscustomobject]@{ Label = ".claude"; Root = $claudeRoot }
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dotfiles-skills-" + [System.IO.Path]::GetRandomFileName())
    try {
        Ensure-Directory -Path $tempRoot
        $zipPath = Join-Path $tempRoot "repository.zip"
        $zipUrl = "https://codeload.github.com/" + [System.Uri]::EscapeDataString($tree.Owner) + "/" + [System.Uri]::EscapeDataString($tree.Repository) + "/zip/" + [System.Uri]::EscapeDataString($tree.Ref)
        Write-Info "Downloading $($tree.Owner)/$($tree.Repository)@$($tree.Ref)..."
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ "User-Agent" = "dotfiles-skills-add" } -ErrorAction Stop

        $extractedPath = Join-Path $tempRoot "extracted"
        Ensure-Directory -Path $extractedPath
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractedPath -Force
        $roots = @(Get-ChildItem -LiteralPath $extractedPath -Directory)
        if ($roots.Count -ne 1) {
            throw "GitHub archive has an unexpected structure"
        }
        $source = Join-Path $roots[0].FullName ($tree.Path -replace "/", [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "Path not found in repository: $($tree.Path)"
        }

        $skills = @(Find-SkillSource -SourceRoot $source)
        if ($skills.Count -eq 0) {
            throw "No skill directories (containing SKILL.md) found under $($tree.Path)"
        }

        $descriptions = @{}
        foreach ($skill in $skills) {
            $descriptions[$skill.Name] = Get-SkillDescription -SkillDirectory $skill.FullName
        }

        $selected = @()
        if ($wanted.Count -gt 0) {
            foreach ($name in $wanted) {
                $match = @($skills | Where-Object { $_.Name -eq $name })
                if ($match.Count -eq 0) {
                    throw "Skill not found in archive: $name"
                }
                $selected += $match[0]
            }
        }
        elseif ($installAll) {
            $selected = $skills
        }
        else {
            # Interactive is the default: --all and --skill= are the opt-outs.
            $selected = @(Select-SkillsInteractively -Skills $skills -Descriptions $descriptions)
        }

        if ($selected.Count -eq 0) {
            Write-Info "No skills selected."
            return 0
        }

        # Resolve every target before writing anything, so a single confirmation
        # can cover the whole run instead of one prompt per file.
        $plan = New-Object System.Collections.Generic.List[object]
        foreach ($skill in ($selected | Sort-Object -Property Name)) {
            foreach ($dest in $destRoots) {
                $target = Join-Path $dest.Root $skill.Name
                $exists = Test-Path -LiteralPath $target
                $action = if (-not $exists) { "install" } elseif ($force) { "replace" } else { "skip" }
                [void]$plan.Add([pscustomobject]@{
                    Skill = $skill
                    Target = $target
                    Qualified = "$($skill.Name) ($($dest.Label))"
                    Exists = $exists
                    Action = $action
                })
            }
        }

        $replaceCount = @($plan | Where-Object { $_.Action -eq "replace" }).Count
        if ($replaceCount -gt 0 -and -not $DryRun) {
            $confirmed = Confirm-DestructiveAction -Verb "Replace" -Count $replaceCount -Subject "skill"
            if (-not $confirmed) {
                Write-Info "Cancelled; nothing was installed."
                return 0
            }
        }

        foreach ($dest in $destRoots) {
            if (-not $DryRun) {
                Ensure-Directory -Path $dest.Root
            }
        }

        $installed = New-Object System.Collections.Generic.List[string]
        $skipped = New-Object System.Collections.Generic.List[string]
        foreach ($entry in $plan) {
            if ($entry.Action -eq "skip") {
                [void]$skipped.Add($entry.Qualified)
                continue
            }
            if ($DryRun) {
                Write-Info "Would $($entry.Action) $($entry.Target)"
                [void]$installed.Add($entry.Qualified)
                continue
            }
            if ($entry.Exists) {
                Remove-Item -LiteralPath $entry.Target -Recurse -Force
            }
            Copy-Item -LiteralPath $entry.Skill.FullName -Destination $entry.Target -Recurse -Force
            [void]$installed.Add($entry.Qualified)
        }

        if ($installed.Count -gt 0) {
            if ($DryRun) {
                Write-Success ("Dry run would install {0}: {1}" -f $installed.Count, ($installed -join ", "))
            }
            else {
                Write-Success ("Installed {0}: {1}" -f $installed.Count, ($installed -join ", "))
            }
        }
        if ($skipped.Count -gt 0) {
            Write-Warn ("Skipped {0} existing: {1}" -f $skipped.Count, ($skipped -join ", "))
            Write-Info "Run again with --force to replace them."
        }
        if ($DryRun) {
            Write-Info "No files were changed"
        }
        else {
            Write-Info "Next: run '.\dot.ps1 sync' on Windows or './dot stow' on macOS to deploy to `$HOME."
        }
        return 0
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-Help {
    Write-Host "$SCRIPT_NAME - Dotfiles management tool (PowerShell)"
    Write-Host "Version: $VERSION"
    Write-Host ""
    Write-Host "USAGE:"
    Write-Host "  .\dot.ps1 [OPTIONS] COMMAND"
    Write-Host ""
    Write-Host "COMMANDS:"
    Write-Host "  sync      Sync top-level directories from home/ into `$HOME"
    Write-Host "  skills add <url> [--force] [--agents-only|--claude-only] [--all] [--dry-run] [--skill=NAME]"
    Write-Host "            Download skills from a GitHub tree URL into home/.agents/skills and home/.claude/skills"
    Write-Host "            Prompts for which skills to install unless --all or --skill=NAME is given"
    Write-Host "  doctor    Run read-only diagnostics for managed sync paths"
    Write-Host "  orphans   List target paths that do not exist in home/"
    Write-Host "  prune     Pick installed skills that are not in home/ to delete"
    Write-Host "  help      Show this help message"
    Write-Host ""
    Write-Host "OPTIONS:"
    Write-Host "  --dotfiles-dir PATH  Override dotfiles directory"
    Write-Host "  --dry-run            Preview sync, skills add, or prune without changing files"
    Write-Host "  --version            Show version information"
    Write-Host "  -h, --help           Show this help message"
    Write-Host ""
}

function Main {
    param([string[]]$CliArgs)

    $remaining = New-Object System.Collections.Generic.List[string]
    $dryRun = $false
    $showHelp = $false
    $showVersion = $false

    for ($i = 0; $i -lt $CliArgs.Count; $i++) {
        $arg = $CliArgs[$i]
        switch ($arg) {
            "--dotfiles-dir" {
                if ($i + 1 -ge $CliArgs.Count) {
                    throw "Missing value for --dotfiles-dir"
                }
                $script:DOTFILES_DIR = $CliArgs[$i + 1]
                $i++
            }
            "--version" {
                $showVersion = $true
            }
            "--dry-run" {
                $dryRun = $true
            }
            "-h" {
                $showHelp = $true
            }
            "--help" {
                $showHelp = $true
            }
            default {
                [void]$remaining.Add($arg)
            }
        }
    }

    $command = if ($remaining.Count -gt 0) { $remaining[0] } else { "help" }
    $commandArgs = @(
        if ($remaining.Count -gt 1) {
            $remaining[1..($remaining.Count - 1)]
        }
    )

    switch ($command) {
        "sync" {
            foreach ($commandArg in $commandArgs) {
                throw "Unknown option for sync: $commandArg"
            }
        }
        "skills" {
            # `skills` and `skills --help` on their own should print the skills add
            # usage instead of a usage error, matching the other commands.
            $subCommand = if ($commandArgs.Count -gt 0) { $commandArgs[0] } else { "" }
            if ($subCommand -eq "" -or $subCommand -eq "-h" -or $subCommand -eq "--help") {
                $commandArgs = @("add", "--help")
                $showHelp = $false
            }
            elseif ($showHelp) {
                if ($subCommand -ne "add") {
                    throw "Usage: $SKILLS_ADD_USAGE"
                }
                if ($commandArgs -notcontains "--help" -and $commandArgs -notcontains "-h") {
                    $commandArgs += "--help"
                }
                $showHelp = $false
            }
            elseif ($subCommand -ne "add") {
                throw "Usage: $SKILLS_ADD_USAGE"
            }
        }
        "doctor" {
            if ($dryRun) {
                throw "Option --dry-run is only valid with sync, skills, and prune"
            }
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for doctor: $($commandArgs[0])"
            }
        }
        "prune" {
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for prune: $($commandArgs[0])"
            }
        }
        "orphans" {
            if ($dryRun) {
                throw "Option --dry-run is only valid with sync, skills, and prune"
            }
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for orphans: $($commandArgs[0])"
            }
        }
        "help" {
            if ($dryRun) {
                throw "Option --dry-run is only valid with sync, skills, and prune"
            }
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for help: $($commandArgs[0])"
            }
        }
        default {
            Write-ErrorMsg "Unknown command: $command"
            Write-Host "Run '.\dot.ps1 help' for usage information"
            return 1
        }
    }

    if ($showVersion) {
        Write-Host "$SCRIPT_NAME version $VERSION"
        return 0
    }

    if ($showHelp -or $command -eq "help") {
        Show-Help
        return 0
    }

    Resolve-Paths

    if ($command -eq "sync") {
        return (Invoke-Sync -DryRun:$dryRun)
    }

    if ($command -eq "skills") {
        $addArgs = @(
            if ($commandArgs.Count -gt 1) {
                $commandArgs[1..($commandArgs.Count - 1)]
            }
        )
        return (Invoke-SkillsAdd -AddArgs $addArgs -DryRun:$dryRun)
    }

    if ($command -eq "doctor") {
        return (Invoke-Doctor)
    }

    if ($command -eq "prune") {
        return (Invoke-Prune -DryRun:$dryRun)
    }

    return (Invoke-Orphans)
}

try {
    $exitCode = Main -CliArgs $args
    exit $exitCode
}
catch {
    Write-ErrorMsg $_.Exception.Message
    exit 1
}
