# Install gum if not present
function Install-Gum {
    if (Get-Command gum -ErrorAction SilentlyContinue) {
        Write-Host "gum is already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing gum..." -ForegroundColor Cyan

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install charmbracelet.gum --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install gum
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install gum
    } else {
        Write-Warning "No supported package manager found (winget, scoop, choco)"
        Write-Warning "Install gum manually: https://github.com/charmbracelet/gum"
        return
    }
}

# Install fzf if not present
function Install-Fzf {
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        Write-Host "fzf is already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing fzf..." -ForegroundColor Cyan

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install junegunn.fzf --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install fzf
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install fzf
    } else {
        Write-Warning "No supported package manager found (winget, scoop, choco)"
        Write-Warning "Install fzf manually: https://github.com/junegunn/fzf"
        return
    }
}

# Install lazygit if not present
function Install-Lazygit {
    if (Get-Command lazygit -ErrorAction SilentlyContinue) {
        Write-Host "lazygit is already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing lazygit..." -ForegroundColor Cyan

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install jesseduffield.lazygit --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install lazygit
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install lazygit
    } else {
        Write-Warning "No supported package manager found (winget, scoop, choco)"
        Write-Warning "Install lazygit manually: https://github.com/jesseduffield/lazygit"
        return
    }
}

# Install oh-my-posh if not present
function Install-OhMyPosh {
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Host "oh-my-posh is already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing oh-my-posh..." -ForegroundColor Cyan

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install JanDeDobbeleer.OhMyPosh --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install oh-my-posh
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install oh-my-posh
    } else {
        Write-Warning "No supported package manager found (winget, scoop, choco)"
        Write-Warning "Install oh-my-posh manually: https://ohmyposh.dev"
        return
    }
}

# Install zoxide if not present
function Install-Zoxide {
    if (Get-Command zoxide -ErrorAction SilentlyContinue) {
        Write-Host "zoxide is already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing zoxide..." -ForegroundColor Cyan

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install ajeetdsouza.zoxide --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install zoxide
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install zoxide
    } else {
        Write-Warning "No supported package manager found (winget, scoop, choco)"
        Write-Warning "Install zoxide manually: https://github.com/ajeetdsouza/zoxide"
        return
    }
}

# Install mise if not present
function Install-Mise {
    if (Get-Command mise -ErrorAction SilentlyContinue) {
        Write-Host "mise is already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing mise..." -ForegroundColor Cyan

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install mise
    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install jdx.mise --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install mise
    } else {
        Write-Warning "No supported package manager found (winget, scoop, choco)"
        Write-Warning "Install mise manually: https://mise.jdx.dev"
        return
    }
}

# Auto-install tools
Install-Gum
Install-Fzf
Install-Lazygit
Install-OhMyPosh
Install-Zoxide
Install-Mise
