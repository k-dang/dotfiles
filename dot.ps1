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
    $script:SYNC_PAIRS = @(
        [pscustomobject]@{
            Label = ".config"
            Source = Join-Path $DOTFILES_DIR "home/.config"
            Target = Join-Path $HOME ".config"
        },
        [pscustomobject]@{
            Label = ".agents"
            Source = Join-Path $DOTFILES_DIR "home/.agents"
            Target = Join-Path $HOME ".agents"
        }
    )
}

function Test-DirectoryHasContent {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    return $null -ne (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
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
}

function Test-WriteAccess {
    param([Parameter(Mandatory)][string]$Directory)

    try {
        $tempFile = Join-Path $Directory ".dot-write-test-$([guid]::NewGuid().ToString('N')).tmp"
        Set-Content -LiteralPath $tempFile -Value "ok" -Encoding UTF8
        Remove-Item -LiteralPath $tempFile -Force
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-Doctor {
    Write-Header "Running diagnostics"
    $issues = 0

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
    }
    else {
        Write-ErrorMsg "Home directory does not exist: $HOME"
        $issues++
    }

    foreach ($syncPair in $SYNC_PAIRS) {
        if (Test-Path -LiteralPath $syncPair.Source -PathType Container) {
            Write-Success "Source $($syncPair.Label) exists: $($syncPair.Source)"
        }
        else {
            Write-ErrorMsg "Source $($syncPair.Label) missing: $($syncPair.Source)"
            $issues++
        }

        try {
            Ensure-Directory -Path $syncPair.Target
            Write-Success "Target $($syncPair.Label) exists or was created: $($syncPair.Target)"
        }
        catch {
            Write-ErrorMsg "Cannot create target $($syncPair.Label): $($syncPair.Target)"
            $issues++
        }

        if (Test-Path -LiteralPath $syncPair.Target -PathType Container) {
            if (Test-WriteAccess -Directory $syncPair.Target) {
                Write-Success "Write access confirmed for: $($syncPair.Target)"
            }
            else {
                Write-ErrorMsg "No write access to: $($syncPair.Target)"
                $issues++
            }
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
    Write-Host "  sync      Sync home/.config and home/.agents into `$HOME"
    Write-Host "  doctor    Run diagnostics for managed sync paths"
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
                Write-Host "$SCRIPT_NAME version $VERSION"
                return 0
            }
            "-h" {
                Show-Help
                return 0
            }
            "--help" {
                Show-Help
                return 0
            }
            default {
                [void]$remaining.Add($arg)
            }
        }
    }

    Resolve-Paths

    $command = if ($remaining.Count -gt 0) { $remaining[0] } else { "help" }
    $commandArgs = if ($remaining.Count -gt 1) { $remaining[1..($remaining.Count - 1)] } else { @() }

    switch ($command) {
        "sync" {
            $dryRun = $false

            foreach ($commandArg in $commandArgs) {
                switch ($commandArg) {
                    "--dry-run" {
                        $dryRun = $true
                    }
                    default {
                        throw "Unknown option for sync: $commandArg"
                    }
                }
            }

            Invoke-Sync -DryRun:$dryRun
            return 0
        }
        "doctor" {
            return (Invoke-Doctor)
        }
        "help" {
            Show-Help
            return 0
        }
        default {
            Write-ErrorMsg "Unknown command: $command"
            Write-Host "Run '.\dot.ps1 help' for usage information"
            return 1
        }
    }
}

try {
    $exitCode = Main -CliArgs $args
    exit $exitCode
}
catch {
    Write-ErrorMsg $_.Exception.Message
    exit 1
}
