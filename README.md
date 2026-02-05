# Dotfiles

Cross-platform dotfiles setup for development environments with common aliases.

## Quick Start

### macOS

One-liner install
```bash
curl -fsSL https://raw.githubusercontent.com/k-dang/dotfiles/main/install.sh | bash
```

Or clone and run manually
```bash
git clone https://github.com/k-dang/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Or use the CLI
```bash
git clone https://github.com/k-dang/dotfiles.git ~/dotfiles
~/dotfiles/dot init
```

### Windows (PowerShell 5.x)

One-liner install
```powershell
iwr -useb https://raw.githubusercontent.com/k-dang/dotfiles/main/install.ps1 | iex
```

Or clone and run manually
```
git clone https://github.com/k-dang/dotfiles.git $HOME\dotfiles
$HOME\dotfiles\install.ps1
```

## Project Structure

```
dotfiles/
├── dot                      # CLI for dotfiles management
├── install.sh              # Unix one-liner bootstrap
├── install.ps1              # Windows one-liner bootstrap
├── shell/                  # Main shell configurations
│   ├── zsh.sh              # zsh config
│   └── powershell.ps1      # PowerShell config
├── modules/                # Modular configurations
│   ├── aliases.sh           # Unix aliases and functions
│   ├── aliases.ps1         # PowerShell aliases and functions
│   ├── local.sh             # Unix local config (not tracked)
│   ├── local.ps1           # PowerShell local config (not tracked)
│   ├── local.example.sh     # Unix local config template (tracked)
│   ├── local.example.ps1   # PowerShell local config template (tracked)
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

## Dot CLI

The `dot` command is a full CLI alternative to `install.sh` with subcommands and flags.

### Commands

```bash
dot init                 # Full setup (tools, stow, shell config)
dot update               # Pull latest changes and restow configs
dot doctor               # Check dependencies and configuration
dot stow                 # Recreate symlinks for ~/.config
dot link                 # Install dot into PATH (symlink)
dot unlink               # Remove the symlink
dot help                 # Show help
```

### Options

```bash
--dotfiles-dir PATH      # Override dotfiles directory
--no-clone               # Do not attempt to clone repo
--skip-tools             # Skip modules/tools.sh
--skip-stow              # Skip stow of ~/.config
--skip-shell             # Skip .zshrc changes
--version                # Show version
-h, --help               # Show help
```

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

## Adding Local Configuration

For machine-specific configuration that shouldn't be tracked in git (work-related paths, company-specific aliases, local tools, etc.), use the local module files.

Example templates are provided in `modules/local.example.sh` and `modules/local.example.ps1` to help you get started.

### macOS

Copy the example and customize it:

```bash
cp modules/local.example.sh modules/local.sh
vim modules/local.sh
```

Edit `modules/local.sh`:

```bash
# Add your alias
alias myworkalias='your command here'

# Or add a function
myworkfunction() {
    echo "Machine-specific setup"
}

# Or set environment variables
export WORKSPACE="$HOME/workspace"
```

The file will be automatically sourced if it exists.

### Windows

Copy the example and customize it:

```powershell
Copy-Item modules\local.example.ps1 modules\local.ps1
notepad modules\local.ps1
```

Edit `modules/local.ps1`:

```powershell
# Add your function
function MyWorkFunction {
    Write-Host "Machine-specific setup"
}

# Or set environment variables
$env:WORKSPACE = "$env:USERPROFILE\workspace"
```

The file will be automatically sourced if it exists.

**Note**: 
- `modules/local.sh` and `modules/local.ps1` are listed in `.gitignore` and will not be committed
- `modules/local.example.sh` and `modules/local.example.ps1` ARE committed and serve as templates
- Copy the example files to create your local configuration

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
