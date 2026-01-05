# Verify dotfiles setup on Windows

$DOTFILES_PATH = "$HOME\dotfiles"

Write-Host "Verifying dotfiles setup..." -ForegroundColor Cyan

# Check dotfiles exists
if (-not (Test-Path $DOTFILES_PATH)) {
    Write-Host "❌ FAIL: dotfiles directory not found at $DOTFILES_PATH" -ForegroundColor Red
    exit 1
}
Write-Host "✓ dotfiles directory exists" -ForegroundColor Green

# Check $PROFILE sources dotfiles
if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($profileContent -match "dotfiles\\shell\\powershell.ps1") {
        Write-Host "✓ $PROFILE sources dotfiles" -ForegroundColor Green
    } else {
        Write-Host "❌ FAIL: $PROFILE does not source dotfiles" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "❌ FAIL: $PROFILE not found" -ForegroundColor Red
    exit 1
}

# Check modules exist
foreach ($module in @("aliases.ps1", "paths.ps1")) {
    $modulePath = Join-Path $DOTFILES_PATH "modules\$module"
    if (Test-Path $modulePath) {
        Write-Host "✓ modules\$module exists" -ForegroundColor Green
    } else {
        Write-Host "❌ FAIL: modules\$module not found" -ForegroundColor Red
        exit 1
    }
}

# Check aliases are defined (need to source first)
. (Join-Path $DOTFILES_PATH "shell\powershell.ps1") -ErrorAction SilentlyContinue

if (Get-Command gs -ErrorAction SilentlyContinue) {
    Write-Host "✓ gs function is defined" -ForegroundColor Green
} else {
    Write-Host "❌ FAIL: gs function not defined" -ForegroundColor Red
    exit 1
}

if (Get-Command ga -ErrorAction SilentlyContinue) {
    Write-Host "✓ ga function is defined" -ForegroundColor Green
} else {
    Write-Host "❌ FAIL: ga function not defined" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ All checks passed! Dotfiles setup is working correctly." -ForegroundColor Green
