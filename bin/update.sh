#!/bin/bash
set -e

DOTFILES_PATH="$HOME/dotfiles"

echo "Updating dotfiles tools..."

if [[ -f "$DOTFILES_PATH/modules/tools.sh" ]]; then
	source "$DOTFILES_PATH/modules/tools.sh"
	echo "✅ Tools installed/updated"
else
	echo "❌ FAIL: tools.sh not found"
	exit 1
fi
