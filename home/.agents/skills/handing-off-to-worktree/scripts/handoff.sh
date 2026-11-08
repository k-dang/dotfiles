#!/usr/bin/env bash
# Creates a git worktree for one hand-off and starts an agent in it through a backend.
# Prints one JSON line: {"backend","branch","worktree","session"}.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: handoff.sh --repo DIR --slug SLUG --name NAME --task-file FILE [options]

  --repo DIR             source git repo
  --slug SLUG            kebab-case, starts with a letter, <= 40 chars; names the worktree folder
  --name NAME            human label for the session (space/tab title)
  --task-file FILE       the brief; sent verbatim as the agent's first message
  --branch BRANCH        default: SLUG
  --base REF             default: origin/main
  --backend NAME         default: $HANDOFF_BACKEND or herdr-app (see backends/)
  --model ID             default: claude-opus-5-5
  --effort LEVEL         default: medium
  --permission-mode MODE default: auto
  --dry-run              print what would run; create nothing
EOF
  exit 2
}

repo= slug= name= task_file= branch= base=origin/main dry_run=0
backend=${HANDOFF_BACKEND:-herdr-app}
model=claude-opus-5-5 effort=medium permission_mode=auto

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo) repo=$2; shift 2 ;;
    --slug) slug=$2; shift 2 ;;
    --name) name=$2; shift 2 ;;
    --task-file) task_file=$2; shift 2 ;;
    --branch) branch=$2; shift 2 ;;
    --base) base=$2; shift 2 ;;
    --backend) backend=$2; shift 2 ;;
    --model) model=$2; shift 2 ;;
    --effort) effort=$2; shift 2 ;;
    --permission-mode) permission_mode=$2; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) usage ;;
  esac
done

[[ -n $repo && -n $slug && -n $name && -n $task_file ]] || usage
[[ $slug =~ ^[a-z][a-z0-9-]{0,39}$ ]] || { echo "invalid slug: $slug" >&2; exit 2; }
[[ -f $task_file ]] || { echo "task file not found: $task_file" >&2; exit 2; }
branch=${branch:-$slug}

backend_script="$(cd "$(dirname "$0")" && pwd)/backends/$backend.sh"
[[ -x $backend_script ]] || { echo "unknown backend: $backend (no executable $backend_script)" >&2; exit 2; }

repo=$(git -C "$repo" rev-parse --show-toplevel)
worktree_root=${HANDOFF_WORKTREE_ROOT:-$HOME/.herdr/worktrees}
worktree="$worktree_root/$(basename "$repo")/$slug"
agent_argv=(claude --model "$model" --permission-mode "$permission_mode" --effort "$effort")

if [[ $dry_run == 1 ]]; then
  echo "git -C $repo fetch origin ${base#origin/}" >&2
  echo "git -C $repo worktree add -b $branch $worktree $base" >&2
  echo "$backend_script --worktree $worktree --name '$name' --task-file $task_file -- ${agent_argv[*]}" >&2
  exit 0
fi

[[ ! -e $worktree ]] || { echo "worktree path exists: $worktree" >&2; exit 1; }
git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" && { echo "branch exists: $branch" >&2; exit 1; }

[[ $base == origin/* ]] && git -C "$repo" fetch -q origin "${base#origin/}"
git -C "$repo" worktree add -q -b "$branch" "$worktree" "$base"

session=$("$backend_script" --worktree "$worktree" --name "$name" --task-file "$task_file" -- "${agent_argv[@]}")

jq -cn --arg backend "$backend" --arg branch "$branch" --arg worktree "$worktree" --arg session "$session" \
  '{backend: $backend, branch: $branch, worktree: $worktree, session: $session}'
