# Misc aliases
function cc
{ 
    claude 
}

# create a new worktree + branch, then step into it
function ga
{
    param(
        [Parameter(Mandatory)]
        [string]$Branch
    )

    $base = Split-Path -Leaf $PWD
    $path = Join-Path (Split-Path -Parent $PWD) "${base}--${Branch}"

    git worktree add -b $Branch $path
    Set-Location $path
}

# remove current worktree and its branch
function gd
{
    if (-not (Get-Command gum -ErrorAction SilentlyContinue))
    {
        Write-Warning "gum is not installed. Run: winget install charmbracelet.gum"
        $response = Read-Host "Remove worktree and branch? (y/n)"
        if ($response -ne "y")
        { 
            Write-Host "Action cancelled." -ForegroundColor Gray
            return 
        }
    } else
    {
        gum confirm "Remove worktree and branch?"
        if ($LASTEXITCODE -ne 0)
        { 
            Write-Host "Action cancelled." -ForegroundColor Gray
            return 
        }
    }

    $currentPath = $PWD.Path
    $worktree    = Split-Path -Leaf $currentPath

    if ($worktree -notlike "*--*")
    {
        Write-Error "Abort: Folder '$worktree' doesn't follow 'root--branch' convention."
        return
    }

    $parts = $worktree -split '--', 2
    $root   = $parts[0]
    $branch = $parts[1]

    $parentPath = Split-Path -Parent $currentPath
    $rootPath   = Join-Path $parentPath $root

    if (Test-Path $rootPath)
    {
        Write-Host "Moving to $rootPath..." -ForegroundColor Cyan
        Set-Location $rootPath
        Start-Sleep -Milliseconds 100
        Write-Host "Removing worktree $worktree..." -ForegroundColor Yellow
        git worktree remove $worktree --force
        Write-Host "Deleting branch $branch..." -ForegroundColor Red
        git branch -D $branch
    } else
    {
        Write-Error "Could not find root repository at $rootPath"
    }
}
