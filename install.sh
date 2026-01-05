#!/bin/bash

# Dotfiles Bootstrap Script for MacOs
# One-liner install: curl -fsSL https://raw.githubusercontent.com/k-dang/dotfiles/main/install.sh | bash

set -e

# Parse arguments
USE_LOCAL=false
if [[ "$1" == "--local" ]]; then
	USE_LOCAL=true
fi

DOTFILES_PATH="$HOME/dotfiles"

# Remove existing dotfiles if present
if [ -d "$DOTFILES_PATH" ]; then
	echo "Removing existing dotfiles..."
	rm -rf "$DOTFILES_PATH"
fi

if [ "$USE_LOCAL" = true ]; then
	# Copy from local directory
	SOURCE_PATH="$(cd "$(dirname "$0")" && pwd)"
	echo "Copying dotfiles from local directory: $SOURCE_PATH..."
	cp -r "$SOURCE_PATH" "$DOTFILES_PATH"
else
	# Clone dotfiles
	echo "Cloning dotfiles to $DOTFILES_PATH..."
	git clone https://github.com/k-dang/dotfiles.git "$DOTFILES_PATH"
fi

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

# Create new .zshrc
echo "Creating .zshrc..."
cat >"$HOME/.zshrc" <<'EOF'
# Dotfiles
source "$HOME/dotfiles/shell/zsh.sh"
EOF

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
