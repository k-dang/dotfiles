#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$temp = Join-Path ([IO.Path]::GetTempPath()) ('dot-skill-links-' + [guid]::NewGuid())
$originalHome = $HOME

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Put-File([string]$Path, [string]$Content = 'fixture') {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Content)
}

try {
    Set-Variable -Name HOME -Scope Script -Force -Value (Join-Path $temp 'home')
    $script:DOTFILES_DIR = Join-Path $temp 'repo'
    $script:SKILL_DIRS = @('.agents/skills', '.claude/skills')
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
    Put-File "$DOTFILES_DIR/home/.agents/skills/shared/SKILL.md"
    Put-File "$DOTFILES_DIR/home/.agents/skills/arena/SKILL.md" 'agents arena'
    Put-File "$DOTFILES_DIR/home/.claude/skills/arena/SKILL.md" 'Claude arena'
    Put-File "$DOTFILES_DIR/home/.claude/skills/shared" '../../.agents/skills/shared'
    Put-File "$DOTFILES_DIR/home/.claude/config.json"
    Put-File "$HOME/.claude/skills/local/SKILL.md" 'local addition'
    Put-File "$HOME/.claude/skills/shared/SKILL.md" 'old copy'
    Resolve-Paths

    $null = Invoke-Sync -DryRun
    Assert-True (-not (Test-Path "$HOME/.agents")) 'Dry run copied files'
    Assert-True (-not (Get-Item "$HOME/.claude/skills").LinkType) 'Dry run created link'
    Assert-True ([IO.File]::ReadAllText("$HOME/.claude/skills/shared/SKILL.md") -eq 'old copy') 'Dry run changed existing skill'

    Assert-True ((Invoke-Sync) -eq 0) 'Sync failed'
    $link = Get-Item "$HOME/.claude/skills/shared"
    $linkCreationTime = $link.CreationTimeUtc
    $expectedKind = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
    Assert-True ($link.LinkType -eq $expectedKind) 'Expected directory link'
    Assert-True (Test-Path "$HOME/.claude/skills/shared/SKILL.md") 'Shared skill missing'
    Assert-True ([IO.File]::ReadAllText("$HOME/.claude/skills/local/SKILL.md") -eq 'local addition') 'Local skill lost'
    Assert-True ([IO.File]::ReadAllText("$HOME/.claude/skills/arena/SKILL.md") -eq 'Claude arena') 'Claude variant lost'
    Assert-True ([IO.File]::ReadAllText("$HOME/.agents/skills/arena/SKILL.md") -eq 'agents arena') 'Agents variant overwritten'
    Assert-True (-not (Get-Item "$HOME/.claude/skills/arena").LinkType) 'Claude variant is shared'

    Put-File "$HOME/.agents/skills/shared/SKILL.md" 'updated through agents'
    Assert-True ([IO.File]::ReadAllText("$HOME/.claude/skills/shared/SKILL.md") -eq 'updated through agents') 'Claude sees a copy'
    Put-File "$HOME/.claude/skills/shared/SKILL.md" 'updated through Claude'
    Assert-True ([IO.File]::ReadAllText("$HOME/.agents/skills/shared/SKILL.md") -eq 'updated through Claude') 'Claude write did not reach agents'
    Assert-True ((Invoke-Sync) -eq 0) 'Repeat sync failed'
    Assert-True ((Get-Item "$HOME/.claude/skills/shared").CreationTimeUtc -eq $linkCreationTime) 'Repeat sync replaced valid link'

    $claudePair = $SYNC_PAIRS | Where-Object Label -eq '.claude'
    $orphans = @(Get-OrphanItems -TargetRoot $claudePair.Target -SourceRoot $claudePair.Source)
    Assert-True (@($orphans | Where-Object { $_.RelativePath.Replace('\', '/') -eq 'skills/shared' }).Count -eq 0) 'Shared link reported as orphan'
    $pairs = @(Get-SkillSyncPairs)
    Assert-True ($pairs.Count -eq 2) 'Cleanup must include Claude-specific skills'
    $claudeOrphans = @(Get-OrphanItems -TargetRoot "$HOME/.claude/skills" -SourceRoot "$DOTFILES_DIR/home/.claude/skills")
    Assert-True (@($claudeOrphans | Where-Object RelativePath -eq 'shared').Count -eq 0) 'Skill-scoped cleanup includes shared link'

    # Exercise a real source directory link as well as Git's plain-file checkout.
    Remove-Item -LiteralPath "$DOTFILES_DIR/home/.claude/skills/shared"
    New-Item -ItemType $expectedKind -Path "$DOTFILES_DIR/home/.claude/skills/shared" -Target "$DOTFILES_DIR/home/.agents/skills/shared" | Out-Null
    Assert-True ((Invoke-Sync) -eq 0) 'Sync with source links failed'
    Assert-True ((Get-Item "$HOME/.claude/skills/shared").CreationTimeUtc -eq $linkCreationTime) 'Sync replaced valid link'
    Assert-True ((Get-Item "$HOME/.claude/skills/shared").LinkType -eq $expectedKind) 'Source link was copied as a directory'

    Set-Variable -Name HOME -Scope Script -Force -Value (Join-Path $temp 'root link home')
    Put-File "$HOME/.agents/skills/arena/SKILL.md" 'agents arena'
    [void][IO.Directory]::CreateDirectory("$HOME/.claude")
    New-Item -ItemType $expectedKind -Path "$HOME/.claude/skills" -Target "$HOME/.agents/skills" | Out-Null
    Resolve-Paths
    Assert-True ((Invoke-Sync) -eq 0) 'Migration from whole-directory link failed'
    Assert-True (-not (Get-Item "$HOME/.claude/skills").LinkType) 'Whole-directory link remains'
    Assert-True ([IO.File]::ReadAllText("$HOME/.agents/skills/arena/SKILL.md") -eq 'agents arena') 'Root link migration overwrote agents variant'
    Assert-True ([IO.File]::ReadAllText("$HOME/.claude/skills/arena/SKILL.md") -eq 'Claude arena') 'Root link migration lost Claude variant'

    Set-Variable -Name HOME -Scope Script -Force -Value (Join-Path $temp 'wrong link home')
    Put-File "$temp/outside/sentinel.txt" 'preserved'
    [void][IO.Directory]::CreateDirectory("$HOME/.claude/skills")
    New-Item -ItemType $expectedKind -Path "$HOME/.claude/skills/shared" -Target "$temp/outside" | Out-Null
    Resolve-Paths
    Assert-True ((Invoke-Sync) -eq 0) 'Replacing incorrect link failed'
    Assert-True ([IO.File]::ReadAllText("$temp/outside/sentinel.txt") -eq 'preserved') 'Replacing link deleted its target'
    Assert-True (Test-Path "$HOME/.claude/skills/shared/SKILL.md") 'Replacement link missing'
    Write-Host 'PowerShell skill links: migration, shared reads/writes, dry run, repeat sync, cleanup and link replacement passed'
}
finally {
    Set-Variable -Name HOME -Scope Script -Force -Value $originalHome
    if (Test-Path -LiteralPath $temp) {
        if (-not ([IO.Path]::GetFullPath($temp)).StartsWith([IO.Path]::GetTempPath())) { throw 'Unexpected test directory' }
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
