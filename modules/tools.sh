# Install gum if not present
install_gum() {
	if command -v gum &>/dev/null; then
		echo "gum is already installed"
		return 0
	fi

	echo "Installing gum..."

	if command -v brew &>/dev/null; then
		brew install gum
	else
		echo "⚠️  Homebrew not found. Cannot install gum automatically."
		echo "   Install manually: brew install gum"
		return 1
	fi
}

# Install bat if not present
install_bat() {
	if command -v bat &>/dev/null; then
		echo "bat is already installed"
		return 0
	fi

	echo "Installing bat..."

	if command -v brew &>/dev/null; then
		brew install bat
	else
		echo "⚠️  Homebrew not found. Cannot install bat automatically."
		echo "   Install manually: brew install bat"
		return 1
	fi
}

# Install fzf if not present
install_fzf() {
	if command -v fzf &>/dev/null; then
		echo "fzf is already installed"
		return 0
	fi

	echo "Installing fzf..."

	if command -v brew &>/dev/null; then
		brew install fzf
	else
		echo "⚠️  Homebrew not found. Cannot install fzf automatically."
		echo "   Install manually: brew install fzf"
		return 1
	fi
}

# Install lazygit if not present
install_lazygit() {
	if command -v lazygit &>/dev/null; then
		echo "lazygit is already installed"
		return 0
	fi

	echo "Installing lazygit..."

	if command -v brew &>/dev/null; then
		brew install lazygit
	else
		echo "⚠️  Homebrew not found. Cannot install lazygit automatically."
		echo "   Install manually: brew install lazygit"
		return 1
	fi
}

# Install oh-my-posh if not present
install_ohmyposh() {
	if command -v oh-my-posh &>/dev/null; then
		echo "oh-my-posh is already installed"
		return 0
	fi

	echo "Installing oh-my-posh..."

	if command -v brew &>/dev/null; then
		brew install jandedobbeleer/oh-my-posh/oh-my-posh
	else
		echo "⚠️  Homebrew not found. Cannot install oh-my-posh automatically."
		echo "   Install manually: brew install oh-my-posh"
		return 1
	fi
}

# Install zoxide if not present
install_zoxide() {
	if command -v zoxide &>/dev/null; then
		echo "zoxide is already installed"
		return 0
	fi

	echo "Installing zoxide..."

	if command -v brew &>/dev/null; then
		brew install zoxide
	else
		echo "⚠️  Homebrew not found. Cannot install zoxide automatically."
		echo "   Install manually: brew install zoxide"
		return 1
	fi
}

# Install mise if not present
install_mise() {
	if command -v mise &>/dev/null; then
		echo "mise is already installed"
		return 0
	fi

	echo "Installing mise..."

	if command -v brew &>/dev/null; then
		brew install mise
	else
		echo "Installing mise using https://mise.run..."
		curl https://mise.run | sh
	fi
}

# Auto-install tools
install_gum
install_bat
install_fzf
install_lazygit
install_ohmyposh
install_zoxide
install_mise
