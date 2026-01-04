# Dotfiles Setup Script for Windows (PowerShell 5.x)
# This script sets up common aliases for development environments

param(
    [Parameter(HelpMessage="Show help message")]
    [switch]$Help
)

# Function to print colored messages
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to display help
function Show-Help {
    @"
Dotfiles Setup Script for Windows (PowerShell 5.x)

Usage: .\setup-windows.ps1 [OPTIONS]

Options:
    -Help              Show this help message

 Description:
      This script sets up common aliases for PowerShell on Windows. It will:
      - Check prerequisites (git)
      - Install fzf (fuzzy finder) if not already installed
      - Install lazygit (terminal UI for git) if not already installed
      - Check PowerShell execution policy
      - Backup existing PowerShell profile if it exists
      - Create git alias 'gs' in the profile

Examples:
    .\setup-windows.ps1          # Run the setup
    .\setup-windows.ps1 -Help     # Show help
"@
    exit 0
}

# Show help if requested
if ($Help) {
    Show-Help
}

# Check if running on Windows
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "This script requires PowerShell 5.x or later. Current version: $($PSVersionTable.PSVersion)"
    exit 1
}

Write-Info "Dotfiles Setup Script for Windows (PowerShell 5.x)"
Write-Host ""

# Display PowerShell version
Write-Info "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Host ""

# Check execution policy
$executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
Write-Info "Current execution policy: $executionPolicy"

if ($executionPolicy -eq "Restricted") {
    Write-Warning "Your execution policy is set to Restricted, which prevents running scripts."
    Write-Info "To allow this script to run, please change the execution policy to RemoteSigned:"
    Write-Host "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "Do you want to change the execution policy now? (y/n)"
    
    if ($response -eq "y" -or $response -eq "Y") {
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Success "Execution policy changed to RemoteSigned"
        } catch {
            Write-Error "Failed to change execution policy: $_"
            Write-Info "Please run PowerShell as Administrator and try again."
            exit 1
        }
    } else {
        Write-Info "Setup cancelled by user."
        exit 0
    }
}
Write-Host ""

# Check prerequisites
Write-Info "Checking prerequisites..."

# Check if git is installed
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCommand) {
    Write-Error "Git is not installed. Please install Git first."
    Write-Info "You can download Git from: https://git-scm.com/download/win"
    exit 1
}
Write-Success "Git is installed: $($gitCommand.Version)"

# Install fzf
Write-Info "Installing fzf..."
$fzfCommand = Get-Command fzf -ErrorAction SilentlyContinue
if ($fzfCommand) {
    Write-Success "fzf is already installed"
    try {
        $fzfVersion = fzf --version
        Write-Info "fzf version: $fzfVersion"
    } catch {
        Write-Info "Could not determine fzf version"
    }
} else {
    Write-Info "Attempting to install fzf using winget..."
    $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCommand) {
        try {
            winget install junegunn.fzf --accept-source-agreements --accept-package-agreements
            Write-Success "fzf installed successfully"
        } catch {
            Write-Warning "Failed to install fzf using winget: $_"
            Write-Info "You can install fzf manually using one of these methods:"
            Write-Host "  - winget: winget install junegunn.fzf" -ForegroundColor Yellow
            Write-Host "  - Chocolatey: choco install fzf" -ForegroundColor Yellow
            Write-Host "  - Scoop: scoop install fzf" -ForegroundColor Yellow
        }
    } else {
        Write-Warning "winget is not available. Cannot automatically install fzf."
        Write-Info "You can install fzf manually using one of these methods:"
        Write-Host "  - winget: winget install junegunn.fzf" -ForegroundColor Yellow
        Write-Host "  - Chocolatey: choco install fzf" -ForegroundColor Yellow
        Write-Host "  - Scoop: scoop install fzf" -ForegroundColor Yellow
    }
}

# Install lazygit
Write-Info "Installing lazygit..."
$lazygitCommand = Get-Command lazygit -ErrorAction SilentlyContinue
if ($lazygitCommand) {
    Write-Success "lazygit is already installed"
    try {
        $lazygitVersion = lazygit --version
        Write-Info "lazygit version: $lazygitVersion"
    } catch {
        Write-Info "Could not determine lazygit version"
    }
} else {
    Write-Info "Attempting to install lazygit using winget..."
    $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCommand) {
        try {
            winget install jesseduffield.lazygit --accept-source-agreements --accept-package-agreements
            Write-Success "lazygit installed successfully"
        } catch {
            Write-Warning "Failed to install lazygit using winget: $_"
            Write-Info "You can install lazygit manually using one of these methods:"
            Write-Host "  - winget: winget install jesseduffield.lazygit" -ForegroundColor Yellow
            Write-Host "  - Chocolatey: choco install lazygit" -ForegroundColor Yellow
            Write-Host "  - Scoop: scoop install lazygit" -ForegroundColor Yellow
        }
    } else {
        Write-Warning "winget is not available. Cannot automatically install lazygit."
        Write-Info "You can install lazygit manually using one of these methods:"
        Write-Host "  - winget: winget install jesseduffield.lazygit" -ForegroundColor Yellow
        Write-Host "  - Chocolatey: choco install lazygit" -ForegroundColor Yellow
        Write-Host "  - Scoop: scoop install lazygit" -ForegroundColor Yellow
    }
}

Write-Host ""

# Note about Homebrew
Write-Warning "Homebrew is not available on Windows. For package management on Windows, consider:"
Write-Host "  - Chocolatey: https://chocolatey.org" -ForegroundColor Yellow
Write-Host "  - Scoop: https://scoop.sh" -ForegroundColor Yellow
Write-Host "  - winget (built into Windows 10/11)" -ForegroundColor Yellow

Write-Host ""

# Get the profile path
$profilePath = $PROFILE.CurrentUserCurrentHost
Write-Info "PowerShell profile path: $profilePath"
Write-Host ""

# Backup existing profile if it exists
if (Test-Path $profilePath) {
    Write-Warning "Existing PowerShell profile found at $profilePath"
    
    $response = Read-Host "Do you want to create a backup? (y/n)"
    
    if ($response -eq "y" -or $response -eq "Y") {
        $backupPath = "$profilePath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        
        try {
            Copy-Item $profilePath $backupPath -Force
            Write-Success "Backup created: $backupPath"
        } catch {
            Write-Error "Failed to create backup: $_"
            exit 1
        }
    } else {
        Write-Warning "No backup created. Existing profile will be modified."
    }
} else {
    Write-Info "No existing PowerShell profile found. A new one will be created."
}

Write-Host ""

# Create profile directory if it doesn't exist
$profileDir = Split-Path $profilePath -Parent
if (-not (Test-Path $profileDir)) {
    Write-Info "Creating profile directory: $profileDir"
    try {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        Write-Success "Profile directory created"
    } catch {
        Write-Error "Failed to create profile directory: $_"
        exit 1
    }
}

# Define the git function content
$gitFunction = @"

# Dotfiles aliases
function gs { git status }
# Additional aliases can be added here
"@

# Add function to profile
if (Test-Path $profilePath) {
    # Check if function already exists
    $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($profileContent -match "function gs \{ git status \}") {
        Write-Success "Git alias function 'gs' already exists in profile"
    } else {
        # Append function to profile
        try {
            Add-Content -Path $profilePath -Value $gitFunction -Encoding UTF8
            Write-Success "Added git alias function to profile"
        } catch {
            Write-Error "Failed to add function to profile: $_"
            exit 1
        }
    }
} else {
    # Create new profile with function
    try {
        Set-Content -Path $profilePath -Value $gitFunction -Encoding UTF8
        Write-Success "Created new profile with git alias function"
    } catch {
        Write-Error "Failed to create profile: $_"
        exit 1
    }
}

Write-Host ""

# Verify the setup
Write-Info "Verifying setup..."

if (Test-Path $profilePath) {
    $newProfileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($newProfileContent -match "function gs \{ git status \}") {
        Write-Success "Git alias function found in profile"
    } else {
        Write-Error "Git alias function not found in profile. Setup may have failed."
        exit 1
    }
} else {
    Write-Error "Profile file not found"
    exit 1
}

Write-Host ""

# Display summary
Write-Success "Setup completed successfully!"
Write-Host ""
Write-Host "Summary of changes:"
Write-Host "  - fzf (fuzzy finder) installed"
Write-Host "  - lazygit (terminal UI for git) installed"
Write-Host "  - Git alias 'gs' -> 'git status' is now available"
Write-Host ""
Write-Info "To apply changes, either:"
Write-Host "  1. Restart PowerShell"
Write-Host "  2. Run: . `$PROFILE"
Write-Host ""
Write-Info "Test the alias by running:"
Write-Host "  gs"
Write-Host ""
Write-Info "To view all aliases, run:"
Write-Host "  . `$PROFILE; Get-Alias"
Write-Host ""
Write-Info "To view all functions, run:"
Write-Host "  . `$PROFILE; Get-ChildItem function:"
