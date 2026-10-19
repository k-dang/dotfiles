#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SCRIPT_NAME = "dot"
$VERSION = "0.1.0"

$DOTFILES_DIR = $PSScriptRoot
$SYNC_PAIRS = @()
$SKILL_DIRS = @(".claude/skills", ".agents/skills")

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

function Test-SyncPairReady {
    param([Parameter(Mandatory)]$SyncPair)

    if (-not (Test-Path -LiteralPath $SyncPair.Source -PathType Container)) {
        Write-ErrorMsg "Source $($SyncPair.Label) missing: $($SyncPair.Source)"
        return $false
    }

    if (-not (Test-Path -LiteralPath $SyncPair.Target)) {
        Write-ErrorMsg "Target $($SyncPair.Label) missing: $($SyncPair.Target)"
        return $false
    }

    if (-not (Test-Path -LiteralPath $SyncPair.Target -PathType Container)) {
        Write-ErrorMsg "Target $($SyncPair.Label) is not a directory: $($SyncPair.Target)"
        return $false
    }

    $targetItem = Get-Item -LiteralPath $SyncPair.Target -Force
    $isReparsePoint = ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isReparsePoint) {
        Write-ErrorMsg "Target $($SyncPair.Label) is a reparse point: $($SyncPair.Target)"
        return $false
    }

    return $true
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
        if (-not (Test-SyncPairReady -SyncPair $syncPair)) {
            $issues++
            continue
        }

        $targetItem = Get-Item -LiteralPath $syncPair.Target -Force
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

function Get-SkillSyncPairs {
    # Without a usable HOME there is no installed target to clean up.
    if ([string]::IsNullOrWhiteSpace($HOME)) {
        return
    }

    foreach ($relativePath in $SKILL_DIRS) {
        $source = Join-Path $DOTFILES_DIR "home/$relativePath"
        $target = Join-Path $HOME $relativePath

        # Without a source there is nothing to compare against, and without a
        # target there is nothing installed to clean up.
        if (-not (Test-Path -LiteralPath $source -PathType Container) -or
            -not (Test-Path -LiteralPath $target -PathType Container)) {
            continue
        }

        [pscustomobject]@{
            Label = $relativePath.Split('/')[0]
            Source = $source
            Target = $target
        }
    }
}

function Group-OrphanCandidates {
    param([Parameter(Mandatory)][object[]]$Candidates)

    # One checkbox per relative path, with all orphaned copies behind it.
    $Candidates | Group-Object -Property RelativePath | Sort-Object -Property Name | ForEach-Object {
        [pscustomobject]@{
            RelativePath = $_.Name
            Candidates = $_.Group
        }
    }
}

function Get-EntryLabel {
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)]$Entry
    )

    $locations = $Entry.Candidates.Label | Sort-Object -Unique

    "$($Entry.RelativePath.PadRight($Width))  $($locations -join ' ')"
}

function Test-InteractiveHost {
    # The picker needs a real console, so redirected stdin or stdout falls back
    # to a static list instead of throwing or hanging in a pipeline.
    return (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
}

function Invoke-Clean {
    param(
        [switch]$DryRun,
        [switch]$All
    )

    if ($All) {
        Write-Header "Finding orphaned paths under managed home directories"

        if (-not (Test-ManagedPaths)) {
            return 1
        }

        $syncPairs = $SYNC_PAIRS
    }
    else {
        Write-Header "Finding orphaned skills and stray skill files"

        $syncPairs = @(Get-SkillSyncPairs)
        if ($syncPairs.Count -eq 0) {
            Write-Warn "No installed skill directories found"
            Write-Info "Run 'sync' first, or use --all to scan every managed directory"
            return 0
        }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $issues = 0

    foreach ($syncPair in $syncPairs) {
        if (-not (Test-SyncPairReady -SyncPair $syncPair)) {
            $issues++
            continue
        }

        $targetItem = Get-Item -LiteralPath $syncPair.Target -Force

        foreach ($item in Get-OrphanItems -TargetRoot $targetItem.FullName -SourceRoot $syncPair.Source) {
            # Dot-prefixed skill folders such as .trash are tool bookkeeping, not
            # skills, so they are never offered for deletion.
            if (-not $All -and ($item.RelativePath -split '[\\/]')[0].StartsWith(".")) {
                continue
            }

            $candidates.Add([pscustomobject]@{
                Label = $syncPair.Label
                Source = $syncPair.Source
                RelativePath = $item.RelativePath
                Path = Join-Path $syncPair.Target $item.RelativePath
            })
        }
    }

    if ($issues -gt 0) {
        Write-Header "Found $issues issue(s) while finding orphans"
        return 1
    }

    if ($candidates.Count -eq 0) {
        Write-Success "No orphaned paths found"
        return 0
    }

    $entries = @(Group-OrphanCandidates -Candidates $candidates)
    $width = ($entries | ForEach-Object { $_.RelativePath.Length } | Measure-Object -Maximum).Maximum
    $labels = @($entries | ForEach-Object { Get-EntryLabel -Width $width -Entry $_ })

    # --dry-run still opens the picker when there is a terminal, so you can mark
    # rows freely and see what would go. Without a terminal it prints the list.
    if (-not (Test-InteractiveHost)) {
        Write-Warn "No terminal available; showing the list instead"
        $labels | ForEach-Object { Write-Host "  $_" }
        if ($DryRun) {
            Write-Info "No files were deleted"
        }
        else {
            Write-Info "No files were changed"
        }
        return 0
    }

    $chosen = @(Select-Items -Labels $labels)
    if ($chosen.Count -eq 0) {
        Write-Info "No files selected"
        return 0
    }

    $count = 0

    foreach ($index in $chosen) {
        foreach ($candidate in $entries[$index].Candidates) {
            # Re-check immediately before deleting: the path may have been removed,
            # or may have gained a matching source since the list was built.
            if (-not (Test-Path -LiteralPath $candidate.Path)) {
                continue
            }

            if (Test-Path -LiteralPath (Join-Path $candidate.Source $candidate.RelativePath)) {
                Write-Warn "Skipping, now managed by home/: $($candidate.Path)"
                continue
            }

            if ($DryRun) {
                Write-Host "  would delete $($candidate.Path)"
            }
            else {
                $item = Get-Item -LiteralPath $candidate.Path -Force
                $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0

                # Remove links directly; recurse only into real directories.
                if ($item.PSIsContainer -and -not $isReparsePoint) {
                    Remove-Item -LiteralPath $candidate.Path -Recurse -Force
                }
                else {
                    Remove-Item -LiteralPath $candidate.Path -Force
                }
            }

            $count++
        }
    }

    if ($DryRun) {
        Write-Info "Would delete $count path(s) from $($chosen.Count) selection(s)"
        Write-Info "No files were deleted"
    }
    else {
        Write-Success "Deleted $count orphaned path(s) from $($chosen.Count) selection(s)"
    }
    return 0
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

function Show-Help {
    Write-Host "$SCRIPT_NAME - Dotfiles management tool (PowerShell)"
    Write-Host "Version: $VERSION"
    Write-Host ""
    Write-Host "USAGE:"
    Write-Host "  .\dot.ps1 [OPTIONS] COMMAND"
    Write-Host ""
    Write-Host "COMMANDS:"
    Write-Host "  sync      Sync top-level directories from home/ into `$HOME"
    Write-Host "  doctor    Run read-only diagnostics for managed sync paths"
    Write-Host "  orphans   List target paths that do not exist in home/"
    Write-Host "  clean     Pick orphaned skills and stray skill files to delete"
    Write-Host "  help      Show this help message"
    Write-Host ""
    Write-Host "OPTIONS:"
    Write-Host "  --dotfiles-dir PATH  Override dotfiles directory"
    Write-Host "  --dry-run            Preview without changing files (clean still opens the picker)"
    Write-Host "  --all                With clean, scan every managed directory instead of skills"
    Write-Host "  --version            Show version information"
    Write-Host "  -h, --help           Show this help message"
    Write-Host ""
}

function Main {
    param([string[]]$CliArgs)

    $remaining = New-Object System.Collections.Generic.List[string]
    $dryRun = $false
    $all = $false
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
            "--all" {
                $all = $true
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

    # Keep the old name working without a separate validation or execution path.
    if ($command -eq "prune") {
        Write-Warn "'prune' is now part of 'clean'; running clean instead"
        $command = "clean"
    }

    switch ($command) {
        "sync" {
            if ($all) {
                throw "Option --all is only valid with clean"
            }
            foreach ($commandArg in $commandArgs) {
                throw "Unknown option for sync: $commandArg"
            }
        }
        "clean" {
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for clean: $($commandArgs[0])"
            }
        }
        { $_ -in @("doctor", "orphans", "help") } {
            if ($dryRun) {
                throw "Option --dry-run is only valid with sync and clean"
            }
            if ($all) {
                throw "Option --all is only valid with clean"
            }
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for ${command}: $($commandArgs[0])"
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

    if ($command -eq "doctor") {
        return (Invoke-Doctor)
    }

    if ($command -eq "clean") {
        return (Invoke-Clean -DryRun:$dryRun -All:$all)
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
