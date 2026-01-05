# Install gum if not present
install_gum() {
	if command -v gum &>/dev/null; then
		echo "gum is already installed"
		return 0
	fi

	echo "Installing gum..."

	if [[ "$OSTYPE" == "darwin"* ]]; then
		# macOS with Homebrew
		if command -v brew &>/dev/null; then
			brew install gum
		else
			echo "⚠️  Homebrew not found. Cannot install gum automatically."
			echo "   Install manually: brew install gum"
			return 1
		fi
	else
		# Linux - try common package managers
		if command -v apt &>/dev/null; then
			sudo apt install -y gum
		elif command -v dnf &>/dev/null; then
			sudo dnf install -y gum
		elif command -v pacman &>/dev/null; then
			sudo pacman -S gum
		else
			echo "⚠️  No supported package manager found."
			echo "   Install gum manually from: https://github.com/charmbracelet/gum"
			return 1
		fi
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
		# Set up fzf key bindings and fuzzy completion
		$(brew --prefix)/opt/fzf/install --all
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
		brew tap jandedobbeleer/oh-my-posh
		brew install oh-my-posh
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
	elif command -v apt &>/dev/null; then
		sudo apt install -y zoxide
	elif command -v dnf &>/dev/null; then
		sudo dnf install -y zoxide
	elif command -v pacman &>/dev/null; then
		sudo pacman -S zoxide
	else
		echo "⚠️  No supported package manager found."
		echo "   Install zoxide manually: https://github.com/ajeetdsouza/zoxide"
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
install_fzf
install_lazygit
install_ohmyposh
install_zoxide
install_mise
