#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v stow >/dev/null; then
    printf 'SKIP: GNU Stow is required for the skill-link integration test\n'
    exit 77
fi
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dot-skill-links.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
source <(tr -d '\r' < "$repo/dot" | sed '$d')
HOME="$tmp/home"
DOTFILES_DIR="$tmp/repo"
mkdir -p "$HOME/.claude/skills/local" "$HOME/.claude/skills/shared" \
    "$DOTFILES_DIR/home/.agents/skills/shared" "$DOTFILES_DIR/home/.agents/skills/arena" \
    "$DOTFILES_DIR/home/.claude/skills/arena"
printf 'local addition' > "$HOME/.claude/skills/local/SKILL.md"
printf 'old copy' > "$HOME/.claude/skills/shared/SKILL.md"
printf 'shared' > "$DOTFILES_DIR/home/.agents/skills/shared/SKILL.md"
printf 'agents arena' > "$DOTFILES_DIR/home/.agents/skills/arena/SKILL.md"
printf 'Claude arena' > "$DOTFILES_DIR/home/.claude/skills/arena/SKILL.md"
ln -s ../../.agents/skills/shared "$DOTFILES_DIR/home/.claude/skills/shared"

stow_dotfiles routine
[[ -L "$HOME/.claude/skills/shared" ]]
[[ "$(cat "$HOME/.claude/skills/shared/SKILL.md")" == shared ]]
[[ "$(cat "$HOME/.claude/skills/local/SKILL.md")" == 'local addition' ]]
[[ "$(cat "$HOME/.claude/skills/arena/SKILL.md")" == 'Claude arena' ]]
[[ "$(cat "$HOME/.agents/skills/arena/SKILL.md")" == 'agents arena' ]]
printf 'updated through agents' > "$HOME/.agents/skills/shared/SKILL.md"
[[ "$(cat "$HOME/.claude/skills/shared/SKILL.md")" == 'updated through agents' ]]
printf 'updated through Claude' > "$HOME/.claude/skills/shared/SKILL.md"
[[ "$(cat "$HOME/.agents/skills/shared/SKILL.md")" == 'updated through Claude' ]]
stow_dotfiles routine
[[ "$(list_orphans)" != *shared* ]]

# Migrate a previously installed whole-directory link without mixing variants.
HOME="$tmp/root link home"
mkdir -p "$HOME/.agents/skills" "$HOME/.claude"
ln -s ../.agents/skills "$HOME/.claude/skills"
stow_dotfiles routine
[[ ! -L "$HOME/.claude/skills" && -L "$HOME/.claude/skills/shared" ]]
[[ "$(cat "$HOME/.agents/skills/arena/SKILL.md")" == 'agents arena' ]]
[[ "$(cat "$HOME/.claude/skills/arena/SKILL.md")" == 'Claude arena' ]]
[[ -z "$(list_orphans)" ]]
printf 'Bash skill links: real Stow migration, shared reads/writes, variants, repeat runs and cleanup passed\n'
