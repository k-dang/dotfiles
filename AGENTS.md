# Dotfiles

Cross-platform dotfiles repository supporting macOS (zsh) and Windows (PowerShell). Always installs to `~/dotfiles` (Unix) or `$HOME\dotfiles` (Windows).

## Architecture

Shell config entry points (`shell/zsh.sh` and `shell/powershell.ps1`) source modules then initialize tools (oh-my-posh, zoxide, mise).

**Configuration Management:**

- **Shell configs**: Sourced from `~/.zshrc` (not symlinked)
- **~/.config files**: Managed via GNU stow (if installed)
  - Example: `~/.config/git/config` → `~/dotfiles/home/.config/git/config`
- **Managed home directories**: Top-level directories under `home/` are copied by `dot.ps1 sync`
  - Example: `~/.agents/skills/...` → `~/dotfiles/home/.agents/skills/...`

## Where to look

- `shell/` - Entry-point shell configs (`zsh.sh` macOS, `powershell.ps1` Windows)
- `home/` - App and agent configs, one subdirectory per tool, synced into `~`

## Conventions

- Machine-specific settings go in `modules/local.sh` or `modules/local.ps1` (gitignored). Copy from `modules/local.example.{sh,ps1}` as a starting point.
- Stow layout: `home/` mirrors `~`, stow creates symlinks
- `home/.agents/skills/*/agents/openai.yaml` files are kept even when the matching skill is trimmed from `home/.claude/skills/` - don't delete them when mirroring `.claude` skill cleanup into `.agents`

## Anti-patterns

- Edit `~/.config/*` directly (changes lost on stow)
- Hardcode paths (use `$DOTFILES_DIR`, `$HOME`)
- Nested git repos in stowed dirs (creates symlink issues)
