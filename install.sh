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

# Setup GNU stow for ~/.config management (optional)
if command -v stow &>/dev/null; then
	echo "Setting up GNU stow for ~/.config..."

	# Run stow from dotfiles directory
	cd "$DOTFILES_PATH"
	if stow --target="$HOME" --no-folding home 2>/dev/null; then
		echo "✓ Successfully stowed ~/.config"
	else
		echo "⚠️  Warning: stow command failed. You may need to manually manage ~/.config"
	fi
else
	echo "⚠️  GNU stow not found. Skipping ~/.config symlink management."
	echo "   Install stow for automatic ~/.config management: brew install stow"
	echo "   Or manually copy files from $DOTFILES_PATH/home/.config/ to ~/.config/"
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
