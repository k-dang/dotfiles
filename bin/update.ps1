# Update dotfiles tools on Windows

$DOTFILES_PATH = "$HOME\dotfiles"

Write-Host "Updating dotfiles tools..." -ForegroundColor Cyan

$toolsPath = Join-Path $DOTFILES_PATH "modules\tools.ps1"
if (Test-Path $toolsPath) {
    . $toolsPath
    Write-Host "[PASS] Tools installed/updated" -ForegroundColor Green
} else {
    Write-Host "[FAIL] FAIL: tools.ps1 not found" -ForegroundColor Red
    exit 1
}
