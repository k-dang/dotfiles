# Dotfiles

Cross-platform dotfiles setup for development environments with common aliases.

## Quick Start

### macOS

```bash
# Make the script executable
chmod +x setup-macos.sh

# Run the setup script
./setup-macos.sh
```

### Windows (PowerShell 5.x)

```powershell
# Set execution policy if needed
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run the setup script
.\setup-windows.ps1
```

## Features

- **OS-specific setup scripts**: Separate scripts for macOS and Windows
- **Interactive prompts**: Backs up existing configurations before making changes
- **Prerequisites checking**: Verifies required tools are installed
- **Easy to extend**: Monolithic structure for adding more aliases

## Prerequisites

### macOS
- macOS operating system
- zsh shell (default on macOS Catalina and later)
- Git installed
- Optional: Homebrew (not required, but checked for future use)

### Windows
- Windows operating system
- PowerShell 5.x or later
- Git installed

## Verification

### macOS
```bash
# Restart your terminal or source the config
source ~/.zshrc

# Test the alias
gst
```

### Windows
```powershell
# Restart PowerShell or reload profile
. $PROFILE

# Test the alias
gs
```

## Backup and Restore

### macOS
Backups are created as `~/.zshrc.backup.YYYYMMDD_HHMMSS`

To restore:
```bash
cp ~/.zshrc.backup.YYYYMMDD_HHMMSS ~/.zshrc
```

### Windows
Backups are created as `$PROFILE.backup.YYYYMMDD_HHMMSS`

To restore:
```powershell
Copy-Item $PROFILE.backup.YYYYMMDD_HHMMSS $PROFILE
```

## Uninstall

### macOS
```bash
# Remove the source line from .zshrc
# Remove the .zsh_aliases file
rm ~/.zsh_aliases
```

### Windows
```powershell
# Remove the alias function from your profile
# Edit $PROFILE and remove the gs function
```

## Project Structure

```
dotfiles/
├── setup-macos.sh          # macOS zsh setup script
├── setup-windows.ps1       # Windows PowerShell setup script
├── .zsh_aliases            # Zsh aliases file
└── README.md               # This file
```

## License

MIT
