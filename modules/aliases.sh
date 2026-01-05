# Git aliases
alias gst='git status'

# create a new worktree + branch, then step into it
ga() {
	local branch="$1"
	if [[ -z "$branch" ]]; then
		echo "Usage: ga <branch-name>"
		return 1
	fi

	local base=$(basename "$PWD")
	local path="$(dirname "$PWD")/${base}--${branch}"

	git worktree add -b "$branch" "$path"
	cd "$path"
}

# remove current worktree and its branch
gd() {
	if ! gum confirm "Remove worktree and branch?"; then
		echo "Action cancelled."
		return
	fi

	local current_path="$PWD"
	local worktree=$(basename "$current_path")

	if [[ "$worktree" != *"--"* ]]; then
		echo "Abort: Folder '$worktree' doesn't follow 'root--branch' convention." >&2
		return 1
	fi

	local root="${worktree%%--*}"
	local branch="${worktree#*--}"

	local parent_path=$(dirname "$current_path")
	local root_path="$parent_path/$root"

	if [[ -d "$root_path" ]]; then
		echo "Moving to $root_path..."
		cd "$root_path"
		echo "Removing worktree $worktree..."
		git worktree remove "$worktree" --force
		echo "Deleting branch $branch..."
		git branch -D "$branch"
	else
		echo "Could not find root repository at $root_path" >&2
		return 1
	fi
}
