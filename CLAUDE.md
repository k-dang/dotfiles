# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Cross-platform dotfiles repository supporting macOS (zsh) and Windows (PowerShell). Always installs to `~/dotfiles` (Unix) or `$HOME\dotfiles` (Windows).

## Installation

**macOS:**
```bash
./install.sh
# or one-liner: curl -fsSL https://raw.githubusercontent.com/k-dang/dotfiles/main/install.sh | bash
```

**Windows:**
```powershell
.\install.ps1
# or one-liner: iwr -useb https://raw.githubusercontent.com/k-dang/dotfiles/main/install.ps1 | iex
```

## Verification

```bash
# macOS
~/dotfiles/bin/verify-setup.sh

# Windows
$HOME\dotfiles\bin\verify-setup.ps1
```

## Architecture

Shell config entry points (`shell/zsh.sh` and `shell/powershell.ps1`) source modules then initialize tools (oh-my-posh, zoxide, mise).

Key modules:
- `modules/aliases.{sh,ps1}` - Git worktree aliases (`ga`, `gd`, `gst`/`gs`)
- `modules/local.{sh,ps1}` - Machine-specific config (gitignored)

## Local Configuration

Machine-specific settings go in `modules/local.sh` or `modules/local.ps1` (gitignored). Copy from `modules/local.example.{sh,ps1}` as a starting point.

## Key Aliases

- `ga <branch>` - Create git worktree + branch at `../repo--branch/` and cd into it
- `gd` - Remove current worktree and its branch (requires `gum` for confirmation, expects `repo--branch` folder naming)
- `gst` (macOS) / `gs` (Windows) - git status
