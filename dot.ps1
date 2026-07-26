#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SCRIPT_NAME = "dot"
$VERSION = "0.1.0"

$DOTFILES_DIR = $PSScriptRoot
$SYNC_PAIRS = @()

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

function Get-DescendantItems {
    param([Parameter(Mandatory)][string]$Root)

    $directories = New-Object System.Collections.Generic.Queue[string]
    $directories.Enqueue($Root)

    while ($directories.Count -gt 0) {
        $directory = $directories.Dequeue()

        foreach ($item in Get-ChildItem -LiteralPath $directory -Force | Sort-Object -Property FullName) {
            Write-Output $item

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

function Invoke-Orphans {
    Write-Header "Finding orphaned managed home paths"

    if (-not (Test-ManagedPaths)) {
        return 1
    }

    $orphanCount = 0
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

        $targetRoot = $targetItem.FullName

        foreach ($item in Get-DescendantItems -Root $targetRoot) {
            $relativePath = $item.FullName.Substring($targetRoot.Length).TrimStart([char[]]@('\', '/'))
            $sourcePath = Join-Path $syncPair.Source $relativePath

            if (-not (Test-Path -LiteralPath $sourcePath)) {
                $kind = if ($item.PSIsContainer) { "directory" } else { "file" }
                Write-Host "[ORPHAN] $kind $($item.FullName)" -ForegroundColor Yellow
                $orphanCount++
            }
        }
    }

    if ($issues -gt 0) {
        Write-Header "Found $issues issue(s) while finding orphans"
        return 1
    }

    if ($orphanCount -eq 0) {
        Write-Success "No orphaned paths found"
    }
    else {
        Write-Warn "Found $orphanCount orphaned path(s); no files were deleted"
    }

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
    Write-Host "  help      Show this help message"
    Write-Host ""
    Write-Host "OPTIONS:"
    Write-Host "  --dotfiles-dir PATH  Override dotfiles directory"
    Write-Host "  --dry-run            Preview sync changes without copying"
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
        "doctor" {
            if ($dryRun) {
                throw "Option --dry-run is only valid with sync"
            }
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for doctor: $($commandArgs[0])"
            }
        }
        "orphans" {
            if ($dryRun) {
                throw "Option --dry-run is only valid with sync"
            }
            if ($commandArgs.Count -gt 0) {
                throw "Unexpected argument for orphans: $($commandArgs[0])"
            }
        }
        "help" {
            if ($dryRun) {
                throw "Option --dry-run is only valid with sync"
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

    if ($command -eq "doctor") {
        return (Invoke-Doctor)
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
