#!/bin/bash

# Dotfiles main zsh configuration
set -e

export DOTFILES_PATH="$HOME/dotfiles"

# Source modules
if [[ -f "$DOTFILES_PATH/modules/aliases.sh" ]]; then
	source "$DOTFILES_PATH/modules/aliases.sh"
fi

# Source local modules (not tracked by git)
if [[ -f "$DOTFILES_PATH/modules/local.sh" ]]; then
	source "$DOTFILES_PATH/modules/local.sh"
fi

# Editor preference (uncomment and set your preferred editor)
export EDITOR=vim

# Set up fzf key bindings and fuzzy completion
# if command -v fzf &>/dev/null; then
# 	source <(fzf --zsh)
# fi

# Initialize oh-my-posh theme
if command -v oh-my-posh &>/dev/null; then
	eval "$(oh-my-posh init zsh --config "$DOTFILES_PATH/config/oh-my-posh/config.omp.json")"
fi

# Initialize zoxide
if command -v zoxide &>/dev/null; then
	eval "$(zoxide init zsh)"
fi

# Initialize mise
if command -v mise &>/dev/null; then
	eval "$(mise activate zsh)"
fi

return 0
