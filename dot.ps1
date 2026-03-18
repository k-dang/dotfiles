#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SCRIPT_NAME = "dot"
$VERSION = "0.1.0"

$DOTFILES_DIR = $PSScriptRoot
$SOURCE_CONFIG_DIR = ""
$TARGET_CONFIG_DIR = ""

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
    $script:SOURCE_CONFIG_DIR = Join-Path $DOTFILES_DIR "home/.config"
    $script:TARGET_CONFIG_DIR = Join-Path $HOME ".config"
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

function Invoke-Sync {
    Write-Header "Syncing config files"

    if (-not (Test-Path -LiteralPath $SOURCE_CONFIG_DIR -PathType Container)) {
        throw "Source directory not found: $SOURCE_CONFIG_DIR"
    }

    Ensure-Directory -Path $TARGET_CONFIG_DIR

    $items = Get-ChildItem -LiteralPath $SOURCE_CONFIG_DIR -Force
    if ($items.Count -eq 0) {
        Write-Warn "Source .config is empty: $SOURCE_CONFIG_DIR"
    }
    else {
        foreach ($item in $items) {
            Copy-Item -LiteralPath $item.FullName -Destination $TARGET_CONFIG_DIR -Recurse -Force
        }
    }

    Write-Success "Synced $SOURCE_CONFIG_DIR to $TARGET_CONFIG_DIR"
    Write-Info "Non-destructive sync: existing extra files were not deleted"
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

    if (Test-Path -LiteralPath $SOURCE_CONFIG_DIR -PathType Container) {
        Write-Success "Source config exists: $SOURCE_CONFIG_DIR"
    }
    else {
        Write-ErrorMsg "Source config missing: $SOURCE_CONFIG_DIR"
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

    try {
        Ensure-Directory -Path $TARGET_CONFIG_DIR
        Write-Success "Target config exists or was created: $TARGET_CONFIG_DIR"
    }
    catch {
        Write-ErrorMsg "Cannot create target config directory: $TARGET_CONFIG_DIR"
        $issues++
    }

    if (Test-Path -LiteralPath $TARGET_CONFIG_DIR -PathType Container) {
        if (Test-WriteAccess -Directory $TARGET_CONFIG_DIR) {
            Write-Success "Write access confirmed for: $TARGET_CONFIG_DIR"
        }
        else {
            Write-ErrorMsg "No write access to: $TARGET_CONFIG_DIR"
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
    Write-Host "  sync      Sync home/.config to `$HOME/.config"
    Write-Host "  doctor    Run diagnostics"
    Write-Host "  help      Show this help message"
    Write-Host ""
    Write-Host "OPTIONS:"
    Write-Host "  --dotfiles-dir PATH  Override dotfiles directory"
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

    switch ($command) {
        "sync" {
            Invoke-Sync
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
