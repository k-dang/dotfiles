# Misc aliases
alias ghss='gh stack sync --remote origin'
alias cc='claude'
alias ccy='claude --dangerously-skip-permissions'
alias cca='claude --permission-mode auto'

# eza (ls replacement)
if command -v eza &>/dev/null; then
  alias ls='eza'
  alias ll='eza -l'
  alias la='eza -la'
  alias lt='eza --tree'
fi

# create a new worktree + branch, then step into it
ga() {
  if [[ -z "$1" ]]; then
    echo "Usage: ga [branch name]"
    return 1
  fi

  local branch="$1"
  local base="$(basename "$PWD")"
  local target="../${base}--${branch}"

  git worktree add -b "$branch" "$target"
  mise trust "$target"
  cd "$target"
}

# remove current worktree and its branch
gd() {
  if gum confirm "Remove worktree and branch?"; then
    local cwd base branch root

    cwd="$(pwd)"
    worktree="$(basename "$cwd")"

    # split on first `--`
    root="${worktree%%--*}"
    branch="${worktree#*--}"

    # Protect against accidentially nuking a non-worktree directory
    if [[ "$root" != "$worktree" ]]; then
      cd "../$root"
      git worktree remove "$worktree" --force
      git branch -D "$branch"
    fi
  fi
}
