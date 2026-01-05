# Dotfiles main PowerShell configuration

$env:DOTFILES_PATH = "$HOME\dotfiles"

# Source modules
if (Test-Path "$env:DOTFILES_PATH\modules\paths.ps1")
{
    . "$env:DOTFILES_PATH\modules\paths.ps1"
}

if (Test-Path "$env:DOTFILES_PATH\modules\aliases.ps1")
{
    . "$env:DOTFILES_PATH\modules\aliases.ps1"
}

# Source local modules (not tracked by git)
if (Test-Path "$env:DOTFILES_PATH\modules\local.ps1")
{
    . "$env:DOTFILES_PATH\modules\local.ps1"
}

# Editor preference (uncomment and set your preferred editor)
$env:EDITOR = "edit"

# Initialize oh-my-posh theme
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue)
{
    oh-my-posh init pwsh --config "$env:DOTFILES_PATH\config\oh-my-posh\config.omp.json" | Invoke-Expression
}

# Initialize zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue)
{
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# Initialize mise
if (Get-Command mise -ErrorAction SilentlyContinue)
{
    mise activate pwsh | Out-String | Invoke-Expression
}
