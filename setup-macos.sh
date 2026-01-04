#!/bin/bash

# Dotfiles Setup Script for macOS (zsh)
# This script sets up common aliases for development environments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display help
show_help() {
	cat <<EOF
Dotfiles Setup Script for macOS (zsh)

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --version       Show version information

 Description:
      This script sets up common aliases for zsh on macOS. It will:
      - Check prerequisites (git, homebrew)
      - Install fzf (fuzzy finder) if not already installed
      - Install lazygit (terminal UI for git) if not already installed
      - Backup existing .zshrc if it exists
      - Create .zsh_aliases file with common aliases
      - Source .zsh_aliases from .zshrc

Examples:
    $0                  # Run the setup
    $0 --help           # Show help
EOF
	exit 0
}

# Function to show version
show_version() {
	echo "Dotfiles Setup Script for macOS - Version 1.0.0"
	exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	-h | --help)
		show_help
		;;
	-v | --version)
		show_version
		;;
	*)
		print_error "Unknown option: $1"
		show_help
		;;
	esac
	shift
done

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
	print_error "This script is designed for macOS only. Current OS: $(uname)"
	exit 1
fi

print_info "Dotfiles Setup Script for macOS (zsh)"
echo ""

# Check if zsh is the default shell
if [[ ! "$SHELL" =~ zsh ]]; then
	print_warning "Your default shell is not zsh. Current shell: $SHELL"
	print_warning "This script will configure zsh, but it won't be your default shell."
	echo ""
	read -p "Do you want to continue? (y/n) " -n 1 -r
	echo ""
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		print_info "Setup cancelled by user."
		exit 0
	fi
fi

# Check prerequisites
print_info "Checking prerequisites..."

# Check if git is installed
if ! command -v git &>/dev/null; then
	print_error "Git is not installed. Please install Git first."
	print_info "You can install Git using: brew install git"
	exit 1
fi
print_success "Git is installed: $(git --version)"

# Check if Homebrew is installed (optional, for future use)
if command -v brew &>/dev/null; then
	print_success "Homebrew is installed: $(brew --version | head -n 1)"
else
	print_warning "Homebrew is not installed. This is optional but recommended for future package management."
	print_info "You can install Homebrew using: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
fi

# Install fzf
print_info "Installing fzf..."
if command -v fzf &>/dev/null; then
	print_success "fzf is already installed: $(fzf --version)"
else
	if command -v brew &>/dev/null; then
		if brew install fzf; then
			print_success "fzf installed successfully"
			# Set up fzf key bindings and fuzzy completion
			print_info "Setting up fzf key bindings and fuzzy completion..."
			$(brew --prefix)/opt/fzf/install --all
		else
			print_error "Failed to install fzf"
			exit 1
		fi
	else
		print_warning "fzf cannot be installed without Homebrew"
		print_info "You can install fzf manually after installing Homebrew: brew install fzf"
	fi
fi

# Install lazygit
print_info "Installing lazygit..."
if command -v lazygit &>/dev/null; then
	print_success "lazygit is already installed: $(lazygit --version)"
else
	if command -v brew &>/dev/null; then
		if brew install lazygit; then
			print_success "lazygit installed successfully"
		else
			print_error "Failed to install lazygit"
			exit 1
		fi
	else
		print_warning "lazygit cannot be installed without Homebrew"
		print_info "You can install lazygit manually after installing Homebrew: brew install lazygit"
	fi
fi

echo ""

# Define file paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="$HOME/.zshrc"
ZSH_ALIASES="$SCRIPT_DIR/.zsh_aliases"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"

# Check if .zsh_aliases exists in the script directory
if [[ ! -f "$ZSH_ALIASES" ]]; then
	print_error ".zsh_aliases file not found in script directory: $SCRIPT_DIR"
	exit 1
fi

print_success "Found .zsh_aliases file"
echo ""

# Backup existing .zshrc if it exists
if [[ -f "$ZSHRC" ]]; then
	print_warning "Existing .zshrc found at $ZSHRC"

	read -p "Do you want to create a backup? (y/n) " -n 1 -r
	echo ""

	if [[ $REPLY =~ ^[Yy]$ ]]; then
		BACKUP_FILE="$ZSHRC$BACKUP_SUFFIX"

		if cp "$ZSHRC" "$BACKUP_FILE"; then
			print_success "Backup created: $BACKUP_FILE"
		else
			print_error "Failed to create backup"
			exit 1
		fi
	else
		print_warning "No backup created. Existing .zshrc will be modified."
	fi
else
	print_info "No existing .zshrc found. A new one will be created."
fi

echo ""

# Source .zsh_aliases from .zshrc
SOURCE_LINE="source \"$ZSH_ALIASES\""

if [[ -f "$ZSHRC" ]]; then
	# Check if source line already exists
	if grep -q "$SOURCE_LINE" "$ZSHRC"; then
		print_success ".zsh_aliases is already sourced in .zshrc"
	else
		# Append source line to .zshrc
		if echo "" >>"$ZSHRC" && echo "# Dotfiles aliases" >>"$ZSHRC" && echo "$SOURCE_LINE" >>"$ZSHRC"; then
			print_success "Added source line to .zshrc"
		else
			print_error "Failed to add source line to .zshrc"
			exit 1
		fi
	fi
else
	# Create new .zshrc with source line
	if echo "# Dotfiles aliases" >"$ZSHRC" && echo "$SOURCE_LINE" >>"$ZSHRC"; then
		print_success "Created new .zshrc with source line"
	else
		print_error "Failed to create .zshrc"
		exit 1
	fi
fi

echo ""

# Verify the setup
print_info "Verifying setup..."

if grep -q "$SOURCE_LINE" "$ZSHRC"; then
	print_success "Source line found in .zshrc"
else
	print_error "Source line not found in .zshrc. Setup may have failed."
	exit 1
fi

if [[ -f "$ZSH_ALIASES" ]]; then
	print_success ".zsh_aliases file exists"
else
	print_error ".zsh_aliases file not found"
	exit 1
fi

echo ""

# Display summary
print_success "Setup completed successfully!"
echo ""
echo "Summary of changes:"
echo "  - fzf (fuzzy finder) installed and configured"
echo "  - lazygit (terminal UI for git) installed"
echo "  - .zsh_aliases is being sourced from .zshrc"
echo "  - Git alias 'gst' -> 'git status' is now available"
echo ""
print_info "To apply changes, either:"
echo "  1. Restart your terminal"
echo "  2. Run: source ~/.zshrc"
echo ""
print_info "Test the alias by running:"
echo "  gst"
echo ""
print_info "To view all aliases, run:"
echo "  source ~/.zshrc && alias"
