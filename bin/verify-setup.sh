#!/bin/bash
set -e

DOTFILES_PATH="$HOME/dotfiles"

echo "Verifying dotfiles setup..."

# Check dotfiles exists
if [[ ! -d "$DOTFILES_PATH" ]]; then
	echo "❌ FAIL: dotfiles directory not found at $DOTFILES_PATH"
	exit 1
fi
echo "✓ dotfiles directory exists"

# Check .zshrc sources dotfiles
if [[ -f "$HOME/.zshrc" ]] && grep -q "source.*dotfiles/shell/zsh.sh" "$HOME/.zshrc"; then
	echo "✓ .zshrc sources dotfiles"
else
	echo "❌ FAIL: .zshrc does not source dotfiles"
	exit 1
fi

# Check modules exist
for module in aliases.sh paths.sh; do
	if [[ ! -f "$DOTFILES_PATH/modules/$module" ]]; then
		echo "❌ FAIL: modules/$module not found"
		exit 1
	fi
	echo "✓ modules/$module exists"
done

# Check aliases are defined (need to source first)
source "$DOTFILES_PATH/shell/zsh.sh" 2>/dev/null || true

if type gst &>/dev/null; then
	echo "✓ gst alias is defined"
else
	echo "❌ FAIL: gst alias not defined"
	exit 1
fi

if type ga &>/dev/null; then
	echo "✓ ga function is defined"
else
	echo "❌ FAIL: ga function not defined"
	exit 1
fi

echo ""
echo "✅ All checks passed! Dotfiles setup is working correctly."
