#!/usr/bin/env bash
# herdr-app backend: opens a new space in the worktree with the agent running and the brief as its task.
# Prints the space's terminal address (read it with `hc read <address>`).
set -euo pipefail

while [[ $# -gt 0 ]]; do
  case $1 in
    --worktree) worktree=$2; shift 2 ;;
    --name) name=$2; shift 2 ;;
    --task-file) task_file=$2; shift 2 ;;
    --) shift; break ;;
    *) echo "herdr-app backend: unknown arg $1" >&2; exit 2 ;;
  esac
done

argv_json=$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1:]))' "$@")
result=$(herdr-app do space.new --name "$name" --folder "$worktree" --argv "$argv_json" --task "$(cat "$task_file")")
jq -er '.terminal' <<<"$result" || { echo "herdr-app: $result" >&2; exit 1; }
