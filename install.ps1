# Dotfiles Bootstrap Script for Windows PowerShell
# One-liner install: iwr -useb https://raw.githubusercontent.com/k-dang/dotfiles/main/install.ps1 | iex

param(
    [switch]$Local
)

$DOTFILES_PATH = "$HOME\dotfiles"

# Remove existing dotfiles if present
if (Test-Path $DOTFILES_PATH) {
    Write-Host "Removing existing dotfiles..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $DOTFILES_PATH -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 100
    while (Test-Path $DOTFILES_PATH) {
        Remove-Item -Recurse -Force $DOTFILES_PATH -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 100
    }
}

if ($Local) {
    # Copy from local directory
    $sourcePath = $PSScriptRoot
    Write-Host "Copying dotfiles from local directory: $sourcePath..." -ForegroundColor Cyan
    Get-ChildItem -Path $sourcePath -Force | Where-Object { $_.Name -ne '.git' } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DOTFILES_PATH -Recurse -Force
    }
} else {
    # Clone dotfiles
    Write-Host "Cloning dotfiles to $DOTFILES_PATH..." -ForegroundColor Cyan
    git clone https://github.com/k-dang/dotfiles.git $DOTFILES_PATH
}

# Check execution policy
$executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
Write-Host "Current execution policy: $executionPolicy" -ForegroundColor Cyan

if ($executionPolicy -eq "Restricted") {
    Write-Host "Your execution policy is set to Restricted, which prevents running scripts." -ForegroundColor Yellow
    Write-Host "To allow this script to run, please change the execution policy to RemoteSigned:" -ForegroundColor Cyan
    Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "Do you want to change the execution policy now? (y/n)"
    
    if ($response -eq "y" -or $response -eq "Y") {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Host "Execution policy changed to RemoteSigned" -ForegroundColor Green
        } catch {
            Write-Host "Failed to change execution policy: $_" -ForegroundColor Red
            Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Cyan
            exit 1
        }
    } else {
        Write-Host "Setup cancelled by user." -ForegroundColor Cyan
        exit 0
    }
}
Write-Host ""

# Run tools installation (once, during install)
$toolsPath = Join-Path $DOTFILES_PATH "modules\tools.ps1"
if (Test-Path $toolsPath) {
    Write-Host "Installing tools..." -ForegroundColor Cyan
    . $toolsPath
}

# Backup existing profile
if (Test-Path $PROFILE) {
    $BACKUP_FILE = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Host "Backing up existing profile to $BACKUP_FILE..." -ForegroundColor Yellow
    Copy-Item $PROFILE $BACKUP_FILE -Force
}

# Create new profile
Write-Host "Creating PowerShell profile..." -ForegroundColor Cyan
@"
# Dotfiles
. "$HOME\dotfiles\shell\powershell.ps1"
"@ | Out-File -FilePath $PROFILE -Encoding UTF8



Write-Host ""
Write-Host "[PASS] Dotfiles setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart PowerShell or run: . `$PROFILE"
Write-Host "  2. Verify setup: $DOTFILES_PATH\bin\verify-setup.ps1"
Write-Host ""
