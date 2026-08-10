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
```powershell
git clone https://github.com/k-dang/dotfiles.git $HOME\dotfiles
$HOME\dotfiles\install.ps1
```

`install.ps1` clones the repo, installs tools, and points `$PROFILE` at `shell/powershell.ps1`. It does not copy `home/` into place, so run a sync afterward to get the managed directories (`.claude`, `.agents`, `.config`, etc.) onto disk:

```powershell
$HOME\dotfiles\dot.ps1 sync
```

## Project Structure

```
dotfiles/
├── dot                      # CLI for dotfiles management (macOS/Linux)
├── dot.ps1                  # CLI for dotfiles management (Windows)
├── install.sh               # Unix one-liner bootstrap
├── install.ps1               # Windows one-liner bootstrap
├── shell/                   # Main shell configurations
│   ├── zsh.sh                # zsh config
│   └── powershell.ps1        # PowerShell config
├── modules/                 # Modular configurations
│   ├── aliases.sh            # Unix aliases and functions
│   ├── aliases.ps1           # PowerShell aliases and functions
│   ├── local.sh               # Unix local config (not tracked)
│   ├── local.ps1              # PowerShell local config (not tracked)
│   ├── local.example.sh       # Unix local config template (tracked)
│   ├── local.example.ps1      # PowerShell local config template (tracked)
│   ├── tools.sh               # Unix tool installation
│   └── tools.ps1              # PowerShell tool installation
├── config/
│   └── oh-my-posh/           # Prompt theme config
├── home/                    # Files synced/stowed into $HOME
│   ├── .config/               # Stowed into ~/.config on macOS/Linux (git, opencode, ...)
│   ├── .agents/               # Copied to $HOME\.agents on Windows (skills)
│   ├── .claude/                # Copied to $HOME\.claude on Windows (skills, agents, hooks)
│   ├── .cursor/                 # Copied to $HOME\.cursor on Windows (agents, commands, skills)
│   └── .pi/                     # Copied to $HOME\.pi on Windows (agent extensions)
└── README.md
```

## Features

- **One-liner install**: Bootstrap from any machine with a single command
- **Fixed location**: Always installs to `~/dotfiles` (or `$HOME\dotfiles` on Windows)
- **Modular structure**: Easy to add new aliases, paths, and tools
- **Cross-platform**: Same structure works on macOS, Linux, and Windows
- **Safe initialization**: Initial setup adds managed symlinks without adopting existing config files
- **Tool installation**: Auto-installs `gum`, `bat`, `fzf`, `lazygit`, `oh-my-posh`, `zoxide`, `mise`, and `eza` during setup

## Dot CLI

Dotfiles management ships as two CLIs with different responsibilities per platform: `dot` (bash) on macOS/Linux, `dot.ps1` (PowerShell) on Windows.

### macOS / Linux: `dot`

```bash
dot init                 # Install tools, non-destructive initial stow, configure shell, chmod bin/ scripts
dot doctor               # Check dependencies and configuration
dot stow                 # Restow ~/.config symlinks after editing files under home/
dot help                 # Show help
```

`dot init` is the first-run command. It installs tools, performs a non-destructive initial stow (using GNU Stow), configures `~/.zshrc`, and makes scripts in `bin/` executable.

`dot stow` is the safe repeat command. It uses `stow --restow` so rerunning it reconciles managed symlinks already managed by stow.

If `dot init` finds an existing real file that conflicts with a managed path under `home/`, it fails fast and leaves that file untouched.

Options: `--dotfiles-dir PATH`, `--version`, `-h`/`--help`.

### Windows: `dot.ps1`

```powershell
dot.ps1 sync              # Copy each top-level directory under home/ into $HOME
dot.ps1 doctor            # Check that each home/ directory has been synced to $HOME
dot.ps1 orphans           # List target paths under $HOME that no longer exist in home/
dot.ps1 help              # Show help
```

Windows has no `stow` equivalent, so `dot.ps1 sync` copies rather than symlinks: it scans every top-level directory under `home/` (currently `.agents`, `.claude`, `.config`, `.cursor`, `.pi`) and copies it to the matching path under `$HOME`, e.g. `home/.claude` -> `$HOME\.claude`.

`dot.ps1 orphans` prints a tree per managed directory of target paths with no matching source under `home/`. It reports the topmost unmatched path only - an orphaned directory is listed once rather than expanded into its whole subtree. It does not delete anything or compare file contents.

Options: `--dotfiles-dir PATH`, `--dry-run` (sync only, preview without copying), `--version`, `-h`/`--help`.

### Typical usage

#### First-time setup (macOS)

```bash
git clone https://github.com/k-dang/dotfiles.git ~/dotfiles
~/dotfiles/dot init
source ~/.zshrc
```

#### First-time setup (Windows)

```powershell
git clone https://github.com/k-dang/dotfiles.git $HOME\dotfiles
$HOME\dotfiles\install.ps1
$HOME\dotfiles\dot.ps1 sync
. $PROFILE
```

#### Verify your setup

```bash
~/dotfiles/dot doctor
```

```powershell
$HOME\dotfiles\dot.ps1 doctor
```

#### Restow after editing managed config files (macOS)

```bash
~/dotfiles/dot stow
```

#### Resync after editing managed config files (Windows)

```powershell
$HOME\dotfiles\dot.ps1 sync
```

You can run `~/dotfiles/dot help` or `$HOME\dotfiles\dot.ps1 help` at any time to see the current command list.

## Verification

### macOS

```bash
# Restart your terminal or source the config
source ~/.zshrc

# Verify setup
~/dotfiles/dot doctor

# Test an alias
ga some-branch
```

### Windows

```powershell
# Restart PowerShell or reload profile
. $PROFILE

# Verify setup
$HOME\dotfiles\dot.ps1 doctor

# Test an alias
ga some-branch
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

Rerun tool installation to pick up new or updated tools:

### macOS

```bash
source ~/dotfiles/modules/tools.sh
```

### Windows

```powershell
. $HOME\dotfiles\modules\tools.ps1
```

Each installer function is idempotent - it skips a tool that's already installed.

## Backup and Restore

### macOS

`dot init` updates `~/.zshrc` in place and does not create automatic backups.

### Windows

`install.ps1` updates `$PROFILE` in place and does not create automatic backups.

## Available Aliases

### macOS

- `cc` - `claude`
- `ccy` - `claude --dangerously-skip-permissions`
- `cca` - `claude --enable-auto-mode`
- `ls`, `ll`, `la`, `lt` - `eza` in place of `ls` (list, long, all, tree), if `eza` is installed
- `ga <branch>` - Create new worktree + branch, `mise trust` it, and step into it
- `gd` - Remove current worktree and its branch (prompts via `gum confirm`)

### Windows

- `cc` - `claude`
- `ccy` - `claude --dangerously-skip-permissions`
- `cca` - `claude --enable-auto-mode`
- `ll`, `lt` - `eza` in place of `ls` (long, tree), if `eza` is installed
- `ga <branch>` - Create new worktree + branch and step into it
- `gd` - Remove current worktree and its branch (prompts via `gum confirm`, falls back to a plain y/n prompt if `gum` isn't installed)

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

## GNU stow

macOS/Linux only - Windows uses `dot.ps1 sync` (copy) instead, since GNU Stow's symlinks don't apply there.

The `dot` CLI already wraps the recommended stow behavior:

- `dot init` performs a non-destructive first-time stow
- `dot stow` performs repeatable restows

If you want to run GNU Stow manually, use these patterns.

First-time stow:
```bash
stow -nv --no-folding -t ~ home
```

```bash
stow --no-folding -t ~ home
```

If Stow reports a conflict, an existing real file is already present at the target path. Move it aside or merge it manually before rerunning the command.

Repeatable restow:

```bash
stow -nv --no-folding --restow -t ~ home
```

```bash
stow --no-folding --restow -t ~ home
```
