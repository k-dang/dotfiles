#!/usr/bin/env pwsh
# Standalone regression suite; imports definitions only, never production startup.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ('dot-clean-' + [guid]::NewGuid())
$originalHome = $HOME
$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Assert-Contains {
    param([string]$Text, [string]$Expected)
    Assert-True ($Text.Contains($Expected)) "Expected output to contain: $Expected`n$Text"
}
function Assert-Exists {
    param([string]$Path)
    Assert-True (Test-Path -LiteralPath $Path) "Missing: $Path"
}
function Assert-Absent {
    param([string]$Path)
    Assert-True (-not (Test-Path -LiteralPath $Path)) "Still exists: $Path"
}
function Put-File {
    param([string]$Path)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, 'fixture')
}
function Get-Snapshot {
    # Include directories as well as files; no links are present in these cases.
    (Get-ChildItem -LiteralPath $HOME -Force -Recurse | Sort-Object FullName |
        ForEach-Object { $_.FullName }) -join "`n"
}
function New-Fixture {
    $caseRoot = Join-Path $temp "case-$script:Passed-$script:Failed"
    Set-Variable -Name HOME -Scope Script -Force -Value (Join-Path $caseRoot 'home')
    $script:DOTFILES_DIR = Join-Path $caseRoot 'repo'
    $script:SYNC_PAIRS = @()
    $script:SKILL_DIRS = @('.claude/skills', '.agents/skills')
    foreach ($root in $script:SKILL_DIRS) {
        foreach ($retained in @('live/SKILL.md', 'live/kept/keep.txt')) {
            Put-File "$DOTFILES_DIR/home/$root/$retained"
            Put-File "$HOME/$root/$retained"
        }
        foreach ($stray in @('live/extra file.txt', 'live/cache dir/deep/child.txt',
                'live/.hidden', 'orphan skill/nested/SKILL.md', 'one-sided/SKILL.md',
                '.trash/archived/SKILL.md')) {
            Put-File "$HOME/$root/$stray"
        }
    }
    Put-File "$DOTFILES_DIR/home/.agents/skills/one-sided/SKILL.md"
    Put-File "$DOTFILES_DIR/home/.config/tool/keep.txt"
    Put-File "$HOME/.config/tool/keep.txt"
    Put-File "$HOME/.config/tool/unrelated.txt"
    $script:Wanted = @()
    $script:Offered = @()
    $script:RecheckSource = $null
    $script:Interactive = $true
    $script:PickerCalled = $false
    Resolve-Paths
}
function Invoke-TestAction {
    param([scriptblock]$Action)
    $records = @(& $Action 6>&1)
    $statuses = @($records | Where-Object { $_ -is [int] })
    Assert-True ($statuses.Count -eq 1 -and $statuses[0] -eq 0) 'Clean must return status 0'
    ($records | ForEach-Object { $_.ToString() }) -join "`n"
}
function Get-LabelPath {
    param([string]$Label)
    ($Label -split ' {2,}', 2)[0].Replace('\', '/')
}
function Assert-Row {
    param([string]$Path, [string]$Locations)
    $rows = @($script:Offered | Where-Object { (Get-LabelPath $_) -eq $Path })
    Assert-True ($rows.Count -eq 1) "Expected exactly one row for '$Path', got $($rows.Count)"
    $actual = ($rows[0] -split ' {2,}', 2)[1]
    Assert-True ($actual -eq $Locations) "Wrong locations for '$Path': $actual"
}
function Run-Case {
    param([string]$Name, [scriptblock]$Test)
    Write-Host $Name
    try {
        New-Fixture
        $script:CaseSkipped = $false
        & $Test
        if ($script:CaseSkipped) { $script:Skipped++ } else { $script:Passed++ }
    }
    catch {
        $script:Failed++
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
    }
}

try {
    [void][IO.Directory]::CreateDirectory($temp)
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repo 'dot.ps1'), [ref]$tokens, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) 'dot.ps1 must parse'
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
            . ([scriptblock]::Create($statement.Extent.Text))
        }
    }
    $script:SCRIPT_NAME = 'dot'
    $script:VERSION = 'test'

    # Mock only the terminal boundary, retaining real scanning/grouping/deletion.
    function Test-InteractiveHost { return $script:Interactive }
    function Select-Items {
        param([string[]]$Labels)
        Assert-True $script:Interactive 'Noninteractive clean must not open a picker'
        $script:PickerCalled = $true
        $script:Offered = @($Labels)
        if ($script:RecheckSource) { Put-File $script:RecheckSource }
        foreach ($wantedPath in $script:Wanted) {
            $matches = @(for ($i = 0; $i -lt $Labels.Count; $i++) {
                if ((Get-LabelPath $Labels[$i]) -eq $wantedPath) { $i }
            })
            Assert-True ($matches.Count -eq 1) "Selection not offered exactly once: $wantedPath"
            $matches[0]
        }
    }

    Run-Case 'grouped topmost listing, retained files and dotfile rules' {
        $before = Get-Snapshot
        $output = Invoke-TestAction { Invoke-Clean -DryRun }
        Assert-True ($script:Offered.Count -eq 5) 'Expected five grouped topmost rows'
        Assert-Row 'orphan skill' '.agents .claude'
        Assert-Row 'live/extra file.txt' '.agents .claude'
        Assert-Row 'live/cache dir' '.agents .claude'
        Assert-Row 'live/.hidden' '.agents .claude'
        Assert-Row 'one-sided' '.claude'
        Assert-Contains $output 'No files selected'
        Assert-True ((Get-Snapshot) -eq $before) 'Empty selection changed files'
    }

    Run-Case 'selected dry-run previews, without deleting' {
        $before = Get-Snapshot
        $script:Wanted = @('orphan skill', 'live/extra file.txt', 'live/cache dir')
        $output = Invoke-TestAction { Invoke-Clean -DryRun }
        Assert-Contains $output 'Would delete 6 path(s)'
        Assert-Contains $output 'extra file.txt'
        Assert-True ((Get-Snapshot) -eq $before) 'Dry-run changed fixture tree'
    }

    Run-Case 'delete selected paths only, respecting each source location' {
        $script:Wanted = @('orphan skill', 'live/extra file.txt', 'live/cache dir', 'one-sided')
        $output = Invoke-TestAction { Invoke-Clean }
        Assert-Contains $output 'Deleted 7 orphaned path(s)'
        foreach ($root in $script:SKILL_DIRS) {
            Assert-Absent "$HOME/$root/orphan skill"
            Assert-Absent "$HOME/$root/live/extra file.txt"
            Assert-Absent "$HOME/$root/live/cache dir"
            Assert-Exists "$HOME/$root/live/.hidden"
            Assert-Exists "$HOME/$root/live/SKILL.md"
            Assert-Exists "$HOME/$root/live/kept/keep.txt"
            Assert-Exists "$HOME/$root/.trash/archived/SKILL.md"
        }
        Assert-Absent "$HOME/.claude/skills/one-sided"
        Assert-Exists "$HOME/.agents/skills/one-sided/SKILL.md"
        Assert-Exists "$HOME/.config/tool/unrelated.txt"
        Assert-True (([IO.File]::ReadAllText("$HOME/.claude/skills/live/SKILL.md")) -eq 'fixture') 'Retained file modified'
    }

    Run-Case 'cancel picker on actual clean' {
        $before = Get-Snapshot
        $output = Invoke-TestAction { Invoke-Clean }
        Assert-True $script:PickerCalled 'Expected picker'
        Assert-Contains $output 'No files selected'
        Assert-True ((Get-Snapshot) -eq $before) 'Cancel changed fixture tree'
    }

    Run-Case 'recheck matching source created after selection' {
        $script:Wanted = @('live/extra file.txt')
        $script:RecheckSource = "$DOTFILES_DIR/home/.claude/skills/live/extra file.txt"
        $output = Invoke-TestAction { Invoke-Clean }
        Assert-Contains $output 'Deleted 1 orphaned path(s)'
        Assert-Exists $script:RecheckSource
        Assert-Exists "$HOME/.claude/skills/live/extra file.txt"
        Assert-Absent "$HOME/.agents/skills/live/extra file.txt"
    }

    Run-Case 'missing source and target skill roots are skipped' {
        Remove-Item -LiteralPath "$DOTFILES_DIR/home/.agents/skills" -Recurse -Force
        Remove-Item -LiteralPath "$HOME/.claude/skills" -Recurse -Force
        $output = Invoke-TestAction { Invoke-Clean }
        Assert-Contains $output 'No installed skill directories found'
        Assert-True (-not $script:PickerCalled) 'Missing roots must not open picker'
        Assert-Exists "$HOME/.agents/skills/orphan skill/nested/SKILL.md"
    }

    Run-Case 'noninteractive list-only, Main clean and prune dispatch' {
        $script:Interactive = $false
        $before = Get-Snapshot
        foreach ($command in @('clean', 'prune')) {
            $output = Invoke-TestAction { Main -CliArgs @('--dotfiles-dir', $DOTFILES_DIR, $command) }
            Assert-Contains $output 'showing the list instead'
            Assert-Contains $output 'live'
            Assert-Contains $output 'extra file.txt'
            Assert-True ((Get-Snapshot) -eq $before) "$command changed files without terminal"
        }
        $output = Invoke-TestAction { Main -CliArgs @('clean', '--dry-run') }
        Assert-Contains $output 'No files were deleted'
        Assert-True (-not $script:PickerCalled) 'List-only must not open picker'
        Assert-True ((Get-Snapshot) -eq $before) 'Noninteractive dry-run changed files'
    }

    Run-Case '--all scans other managed roots, default does not' {
        $null = Invoke-TestAction { Invoke-Clean }
        Assert-True (-not (@($script:Offered | Where-Object { (Get-LabelPath $_) -eq 'tool/unrelated.txt' }).Count)) 'Default scan leaked into .config'
        $before = Get-Snapshot
        $script:Wanted = @('tool/unrelated.txt')
        $output = Invoke-TestAction { Main -CliArgs @('clean', '--all', '--dry-run') }
        Assert-Row 'tool/unrelated.txt' '.config'
        Assert-Row 'skills/.trash' '.agents .claude'
        Assert-Contains $output 'Would delete 1 path(s)'
        Assert-True ((Get-Snapshot) -eq $before) '--all dry-run changed files'
        $output = Invoke-TestAction { Main -CliArgs @('clean', '--all') }
        Assert-Contains $output 'Deleted 1 orphaned path(s)'
        Assert-Absent "$HOME/.config/tool/unrelated.txt"
        Assert-Exists "$HOME/.config/tool/keep.txt"
        Assert-Exists "$HOME/.claude/skills/orphan skill/nested/SKILL.md"
    }

    Run-Case 'directory links are leaves and deletion preserves their target' {
        $outside = Join-Path $temp 'outside'
        Put-File "$outside/sentinel.txt"
        [void][IO.Directory]::CreateDirectory("$DOTFILES_DIR/home/.claude/skills/live/linked")
        $kind = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
        try {
            $link = New-Item -ItemType $kind -Path "$HOME/.claude/skills/live/linked" -Target $outside
        }
        catch {
            Write-Host "  SKIP: $kind unavailable: $($_.Exception.Message)"
            $script:CaseSkipped = $true
            return
        }
        Assert-True (($link.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Expected a real link'
        $null = New-Item -ItemType $kind -Path "$HOME/.claude/skills/orphan link" -Target $outside
        $script:Wanted = @('orphan link')
        $output = Invoke-TestAction { Invoke-Clean }
        Assert-Row 'orphan link' '.claude'
        Assert-True (-not (($script:Offered -join "`n").Contains('sentinel.txt'))) 'Scanner descended through link'
        Assert-Contains $output 'Deleted 1 orphaned path(s)'
        Assert-Absent "$HOME/.claude/skills/orphan link"
        Assert-Exists "$outside/sentinel.txt"
        Assert-Exists "$HOME/.claude/skills/live/linked"
    }
}
finally {
    Set-Variable -Name HOME -Scope Script -Force -Value $originalHome
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "`nPowerShell clean: $script:Passed passed, $script:Failed failed, $script:Skipped skipped"
if ($script:Failed -gt 0) { exit 1 }
