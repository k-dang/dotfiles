# Dotfiles

Cross-platform dotfiles setup for development environments with common aliases.

## Quick Start

### macOS

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/k-dang/dotfiles/main/install.sh | bash

# Or clone and run manually
git clone https://github.com/k-dang/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

### Windows (PowerShell 5.x)

```powershell
# One-liner install
iwr -useb https://raw.githubusercontent.com/k-dang/dotfiles/main/install.ps1 | iex

# Or clone and run manually
git clone https://github.com/k-dang/dotfiles.git $HOME\dotfiles
$HOME\dotfiles\install.ps1
```

## Testing Changes Locally

Before pushing changes to git, you can test them locally using the `--local` flag:

### macOS

```bash
cd ~/dotfiles
./install.sh --local
```

### Windows (PowerShell 5.x)

```powershell
cd $HOME\dotfiles
.\install.ps1 -Local
```

The `--local` flag skips the git clone step and uses your current directory instead, allowing you to test changes without committing them first.

## Project Structure

```
dotfiles/
├── install.sh              # Unix one-liner bootstrap
├── install.ps1              # Windows one-liner bootstrap
├── shell/                  # Main shell configurations
│   ├── zsh.sh              # zsh config
│   └── powershell.ps1      # PowerShell config
├── modules/                # Modular configurations
│   ├── aliases.sh           # Unix aliases and functions
│   ├── aliases.ps1         # PowerShell aliases and functions
│   ├── paths.sh             # Unix PATH management
│   ├── paths.ps1           # PowerShell PATH management
│   ├── tools.sh            # Unix tool installation
│   └── tools.ps1           # PowerShell tool installation
├── bin/                    # Utility scripts
│   ├── verify-setup.sh     # Verify Unix setup
│   ├── verify-setup.ps1    # Verify Windows setup
│   ├── update.sh           # Update Unix tools
│   └── update.ps1          # Update Windows tools
└── README.md
```

## Features

- **One-liner install**: Bootstrap from any machine with a single command
- **Fixed location**: Always installs to `~/dotfiles` (or `$HOME\dotfiles` on Windows)
- **Modular structure**: Easy to add new aliases, paths, and tools
- **Cross-platform**: Same structure works on macOS, Linux, and Windows
- **Auto-backup**: Existing configs are backed up before overwriting
- **Tool installation**: Auto-installs tools like `gum`, `fzf`, `lazygit`, `zoxide`, `oh-my-posh` during setup

## Verification

### macOS

```bash
# Restart your terminal or source the config
source ~/.zshrc

# Verify setup
~/dotfiles/bin/verify-setup.sh

# Test an alias
gst
```

### Windows

```powershell
# Restart PowerShell or reload profile
. $PROFILE

# Verify setup
$HOME\dotfiles\bin\verify-setup.ps1

# Test an alias
gs
```

## Adding New Aliases

### macOS

Edit `modules/aliases.sh`:

```bash
# Add your alias
alias myalias='your command here'

# Or add a function
myfunction() {
    echo "Hello, world!"
}
```

No need to edit install scripts - just reload your shell:

```bash
source ~/.zshrc
```

### Windows

Edit `modules/aliases.ps1`:

```powershell
# Add your function
function MyFunction {
    Write-Host "Hello, world!"
}
```

Reload your shell:

```powershell
. $PROFILE
```

## Adding New Paths

### macOS

Edit `modules/paths.sh`:

```bash
# Add your path
add_path "$HOME/my-tools/bin"
```

### Windows

Edit `modules/paths.ps1`:

```powershell
# Add your path
Add-Path "$env:USERPROFILE\my-tools\bin"
```

## Updating Tools

If you want to reinstall or update tools (like `gum`):

### macOS

```bash
~/dotfiles/bin/update.sh
```

### Windows

```powershell
$HOME\dotfiles\bin\update.ps1
```

## Backup and Restore

### macOS

Backups are created as `~/.zshrc.backup.YYYYMMDD_HHMMSS`

To restore:

```bash
cp ~/.zshrc.backup.YYYYMMDD_HHMMSS ~/.zshrc
source ~/.zshrc
```

### Windows

Backups are created as `$PROFILE.backup.YYYYMMDD_HHMMSS`

To restore:

```powershell
Copy-Item $PROFILE.backup.YYYYMMDD_HHMMSS $PROFILE
. $PROFILE
```

## Available Aliases

### macOS

- `gst` - Show git status
- `ga <branch>` - Create new worktree + branch and step into it
- `gd` - Remove current worktree and its branch

### Windows

- `gs` - Show git status
- `ga <branch>` - Create new worktree + branch and step into it
- `gd` - Remove current worktree and its branch

## Uninstall

### macOS

```bash
# Remove dotfiles directory
rm -rf ~/dotfiles

# Remove the source line from .zshrc
# Edit ~/.zshrc and remove the line: source "$HOME/dotfiles/shell/zsh.sh"
```

### Windows

```powershell
# Remove dotfiles directory
Remove-Item -Recurse -Force $HOME\dotfiles

# Remove the source line from your profile
# Edit $PROFILE and remove the line: . "$HOME\dotfiles\shell\powershell.ps1"
```

## Things not covered

Fonts are not covered in the scripts.
Preference is to use [Nerd Fonts](https://www.nerdfonts.com/) to cover icons and they look nice as well.

```
function dev { Set-Location "C:\Users\kevin\Documents\dev" }
```
