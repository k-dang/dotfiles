# Add path to PATH if not already present and directory exists
function Add-Path {
    param([string]$Path)

    # Check if already in PATH
    if ($env:PATH -split ';' -contains $Path) {
        return
    }

    # Check if directory exists
    if (-not (Test-Path $Path)) {
        return
    }

    $env:PATH = "$Path;$env:PATH"
}

# Add common paths
Add-Path "$env:USERPROFILE\bin"
Add-Path "$env:USERPROFILE\.bin"
Add-Path "$env:USERPROFILE\.local\bin"
Add-Path "$env:USERPROFILE\dotfiles\bin"
