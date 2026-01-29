#!/bin/bash
# Sync reference repositories - clone missing, pull existing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.txt"
REPOS_DIR="${REPOS_DIR:-$HOME/dev/reference-repos}"

mkdir -p "$REPOS_DIR"

if [[ ! -f "$REPOS_FILE" ]]; then
    echo "Error: repos.txt not found at $REPOS_FILE"
    exit 1
fi

echo "Syncing repos to $REPOS_DIR"
echo ""

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    url="$line"

    # Extract repo name from URL
    # Handles: git@github.com:org/repo.git, https://github.com/org/repo.git, etc.
    name=$(basename "$url" .git)

    repo_path="$REPOS_DIR/$name"

    if [[ -d "$repo_path/.git" ]]; then
        # Repo exists - try to pull
        cd "$repo_path"

        # Check for uncommitted changes
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            echo "⚠ $name (dirty - skipped pull)"
            continue
        fi

        # Try to pull
        if git pull --quiet 2>/dev/null; then
            # Check if there were actual changes
            if git diff --quiet HEAD@{1} HEAD 2>/dev/null; then
                echo "✓ $name (up to date)"
            else
                echo "✓ $name (updated)"
            fi
        else
            echo "✗ $name (pull failed)"
        fi
    else
        # Repo doesn't exist - clone
        if git clone --quiet "$url" "$repo_path" 2>/dev/null; then
            echo "✓ $name (cloned)"
        else
            echo "✗ $name (clone failed - check URL and auth)"
        fi
    fi
done < "$REPOS_FILE"

echo ""
echo "Done. Repos available at: $REPOS_DIR"
