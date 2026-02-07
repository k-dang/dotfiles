# Dotfiles main PowerShell configuration

$env:DOTFILES_PATH = "$HOME\dotfiles"

function Test-DotfilesDebug
{
    $debugValue = "$env:DOTFILES_DEBUG".Trim().ToLowerInvariant()
    return $debugValue -in @("1", "true", "yes", "on")
}

function Invoke-GeneratedInitScript
{
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Generator
    )

    try
    {
        $scriptText = & $Generator | Out-String
    }
    catch
    {
        if (Test-DotfilesDebug)
        {
            Write-Warning "[$Name] init command failed: $($_.Exception.Message)"
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($scriptText))
    {
        if (Test-DotfilesDebug)
        {
            Write-Warning "[$Name] init returned empty output; skipping Invoke-Expression."
        }
        return
    }

    Invoke-Expression $scriptText
}

# Source modules
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
    Invoke-GeneratedInitScript -Name "oh-my-posh" -Generator {
        oh-my-posh init pwsh --config "$env:DOTFILES_PATH\config\oh-my-posh\config.omp.json"
    }
}

# Initialize zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue)
{
    Invoke-GeneratedInitScript -Name "zoxide" -Generator {
        zoxide init powershell
    }
}

# Initialize mise
if (Get-Command mise -ErrorAction SilentlyContinue)
{
    Invoke-GeneratedInitScript -Name "mise" -Generator {
        mise activate pwsh
    }
}
