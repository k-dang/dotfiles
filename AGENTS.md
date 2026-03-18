# Dotfiles

Cross-platform dotfiles repository supporting macOS (zsh) and Windows (PowerShell). Always installs to `~/dotfiles` (Unix) or `$HOME\dotfiles` (Windows).

## Structure

- `install.sh` / `install.ps1` - Platform installers
- `shell/` - Entry-point shell config scripts
- `modules/` - Reusable shell modules and aliases
- `home/` - Files intended for `~/.config` via stow

## Architecture

Shell config entry points (`shell/zsh.sh` and `shell/powershell.ps1`) source modules then initialize tools (oh-my-posh, zoxide, mise).

**Configuration Management:**

- **Shell configs**: Sourced from `~/.zshrc` (not symlinked)
- **~/.config files**: Managed via GNU stow (if installed)
  - Example: `~/.config/git/config` → `~/dotfiles/home/.config/git/config`
  - Initial adoption may create a backup at `~/.config.backup.YYYYMMDD_HHMMSS`

Key modules:

- `modules/aliases.{sh,ps1}` - Git worktree aliases (`ga`, `gd`, `gst`/`gs`)
- `modules/local.{sh,ps1}` - Machine-specific config (gitignored)

## Where to look

- `shell/zsh.sh` - macOS entry-point shell config
- `shell/powershell.ps1` - Windows entry-point shell config
- `modules/aliases.{sh,ps1}` - Common shell aliases and git helpers
- `modules/local.example.{sh,ps1}` - Template for machine-specific config
- `home/.config/` - Stowed app configs (e.g., git)

## Conventions

- Machine-specific settings go in `modules/local.sh` or `modules/local.ps1` (gitignored). Copy from `modules/local.example.{sh,ps1}` as a starting point.
- Stow layout: `home/` mirrors `~`, stow creates symlinks

## Anti-patterns

- Edit `~/.config/*` directly (changes lost on stow)
- Hardcode paths (use `$DOTFILES_DIR`, `$HOME`)
- Nested git repos in stowed dirs (creates symlink issues)

## Commands

```bash
dot init                 # Full setup (tools, stow, shell config)
dot update               # Pull latest changes and restow configs
dot doctor               # Check dependencies and configuration
dot stow                 # Recreate symlinks for ~/.config
dot link                 # Install dot into PATH (symlink)
dot unlink               # Remove the symlink
dot help                 # Show help
```
