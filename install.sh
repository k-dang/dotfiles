#!/bin/bash

# Dotfiles Bootstrap Script for MacOs
# One-liner install: curl -fsSL https://raw.githubusercontent.com/k-dang/dotfiles/main/install.sh | bash
DOTFILES_PATH="$HOME/dotfiles"

# Remove existing dotfiles if present
if [ -d "$DOTFILES_PATH" ]; then
	echo "Removing existing dotfiles..."
	rm -rf "$DOTFILES_PATH"
fi

# Clone dotfiles
echo "Cloning dotfiles to $DOTFILES_PATH..."
git clone https://github.com/k-dang/dotfiles.git "$DOTFILES_PATH"

# Run tools installation (once, during install)
if [ -f "$DOTFILES_PATH/modules/tools.sh" ]; then
	echo "Installing tools..."
	source "$DOTFILES_PATH/modules/tools.sh"
fi

# Backup existing .zshrc
if [ -f "$HOME/.zshrc" ]; then
	BACKUP_FILE="$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
	echo "Backing up existing .zshrc to $BACKUP_FILE..."
	cp "$HOME/.zshrc" "$BACKUP_FILE"
fi

# Ensure .zshrc sources dotfiles
DOTFILES_LINE='source "$HOME/dotfiles/shell/zsh.sh"'
if [[ -f "$HOME/.zshrc" ]] && grep -q "${DOTFILES_LINE}" "$HOME/.zshrc"; then
	echo ".zshrc already sources dotfiles"
else
	echo "Appending dotfiles to .zshrc..."
	{
		echo "# Dotfiles"
		echo "${DOTFILES_LINE}"
	} >>"$HOME/.zshrc"
fi

# Make bin scripts executable
echo "Making bin scripts executable..."
chmod +x "$DOTFILES_PATH/bin/"*.sh

echo ""
echo "✅ Dotfiles setup complete!"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Verify setup: $DOTFILES_PATH/bin/verify-setup.sh"
echo ""
