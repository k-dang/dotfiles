# Add path to PATH if not already present and directory exists
add_path() {
	local path="$1"

	# Check if path already exists in PATH
	if [[ ":$PATH:" == *":$path:"* ]]; then
		return 0
	fi

	# Check if directory exists
	if [[ ! -d "$path" ]]; then
		return 1
	fi

	# Add to PATH
	export PATH="$path:$PATH"
}

# Add common paths
add_path "${HOME}/bin"
add_path "${HOME}/.bin"
add_path "${HOME}/.local/bin"
add_path "${HOME}/.cargo/bin"
add_path "${HOME}/dotfiles/bin"

# Platform-specific paths
if [[ "$OSTYPE" == "darwin"* ]]; then
	# macOS
	add_path "/usr/local/bin"
	add_path "/opt/homebrew/bin"
fi
