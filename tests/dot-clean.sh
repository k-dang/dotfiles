#!/usr/bin/env bash
# Standalone regression suite; never run clean against the caller's HOME.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dot-clean.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# Load functions without running main; tolerate a Windows checkout's CRLF.
source <(tr -d '\r' < "$repo/dot" | sed '$d')
tr -d '\r' < "$repo/dot" > "$tmp/dot"
passed=0 failed=0 skipped=0

fail() { printf '  FAIL: %s\n' "$*" >&2; return 1; }
assert_has() { [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"; }
assert_lacks() { [[ "$1" != *"$2"* ]] || fail "unexpected output: $2"; }
assert_exists() { [[ -e "$1" || -L "$1" ]] || fail "missing: $1"; }
assert_absent() { [[ ! -e "$1" && ! -L "$1" ]] || fail "still exists: $1"; }
put() { mkdir -p "$(dirname "$1")"; printf 'fixture\n' > "$1"; }
snapshot() { find "$HOME" -print | sort; }

fixture() {
    HOME="$tmp/case-$passed-$failed/home"
    DOTFILES_DIR="$tmp/case-$passed-$failed/repo"
    SKILL_DIRS=(".claude/skills" ".agents/skills")
    export HOME
    mkdir -p "$HOME" "$DOTFILES_DIR/home"
    local root
    for root in "${SKILL_DIRS[@]}"; do
        put "$DOTFILES_DIR/home/$root/live/SKILL.md"
        put "$DOTFILES_DIR/home/$root/live/kept/keep.txt"
        put "$HOME/$root/live/SKILL.md"
        put "$HOME/$root/live/kept/keep.txt"
        put "$HOME/$root/live/extra file.txt"
        put "$HOME/$root/live/cache dir/deep/child.txt"
        put "$HOME/$root/live/.hidden"
        put "$HOME/$root/orphan skill/nested/SKILL.md"
        put "$HOME/$root/one-sided/SKILL.md"
        put "$HOME/$root/.trash/archived/SKILL.md"
    done
    put "$DOTFILES_DIR/home/.agents/skills/one-sided/SKILL.md"
    put "$DOTFILES_DIR/home/.config/tool/keep.txt"
    put "$HOME/.config/tool/keep.txt"
    put "$HOME/.config/tool/unrelated.txt"
    CHOOSE_PATHS='' RECHECK_SOURCE='' CANCEL=false
    can_prompt() { return 0; }
}

# Select actual offered fixture rows, not fabricated labels. Command substitution
# runs gum in a subshell, so race hooks communicate through the filesystem.
gum() {
    [[ "$1" == choose ]] || return 2
    local rows row wanted
    rows="$(< /dev/stdin)"
    printf '%s\n' "$rows" > "$tmp/offered"
    if $CANCEL; then return 130; fi
    if [[ -n "$RECHECK_SOURCE" ]]; then put "$RECHECK_SOURCE"; fi
    while IFS= read -r row; do
        while IFS= read -r wanted; do
            [[ -n "$wanted" ]] || continue
            if [[ "$row" == "$wanted  "* ]]; then printf '%s\n' "$row"; fi
        done <<< "$CHOOSE_PATHS"
    done <<< "$rows"
}

expect_row() {
    local rows="$1" path="$2" expected="$3" row locations count=0
    while IFS= read -r row; do
        if [[ "$row" == "$path  "* ]]; then
            locations="${row#"$path"}"
            locations="${locations#"${locations%%[! ]*}"}"
            [[ "$locations" == "$expected" ]] || fail "$path locations: '$locations', wanted '$expected'"
            ((++count))
        fi
    done <<< "$rows"
    [[ "$count" == 1 ]] || fail "expected exactly one row for '$path', got $count"
}

test_listing() {
    fixture
    local rows count
    rows="$(list_orphans)"
    expect_row "$rows" 'orphan skill' '.agents .claude'
    expect_row "$rows" 'live/extra file.txt' '.agents .claude'
    expect_row "$rows" 'live/cache dir' '.agents .claude'
    expect_row "$rows" 'live/.hidden' '.agents .claude'
    expect_row "$rows" 'one-sided' '.claude'
    count="$(printf '%s\n' "$rows" | wc -l)"
    [[ "$count" -eq 5 ]] || fail "expected five grouped, topmost rows: $rows"
    assert_lacks "$rows" 'child.txt'
    assert_lacks "$rows" 'nested/SKILL.md'
    assert_lacks "$rows" '.trash'
    assert_lacks "$rows" 'keep.txt'
    assert_lacks "$rows" '.config'
}

test_dry_run() {
    fixture
    local before output
    before="$(snapshot)"
    CHOOSE_PATHS=$'orphan skill\nlive/extra file.txt\nlive/cache dir'
    output="$(cmd_clean --dry-run)"
    assert_has "$output" 'Would delete 6 path(s)'
    assert_has "$output" "$HOME/.claude/skills/live/extra file.txt"
    [[ "$(snapshot)" == "$before" ]] || fail 'dry-run changed the fixture tree'
}

test_selected_only() {
    fixture
    CHOOSE_PATHS=$'orphan skill\nlive/extra file.txt\nlive/cache dir\none-sided'
    local output root
    output="$(cmd_clean)"
    assert_has "$output" 'Deleted 7 orphaned path(s)'
    for root in "${SKILL_DIRS[@]}"; do
        assert_absent "$HOME/$root/orphan skill"
        assert_absent "$HOME/$root/live/extra file.txt"
        assert_absent "$HOME/$root/live/cache dir"
        assert_exists "$HOME/$root/live/.hidden"
        assert_exists "$HOME/$root/live/SKILL.md"
        assert_exists "$HOME/$root/live/kept/keep.txt"
        assert_exists "$HOME/$root/.trash/archived/SKILL.md"
    done
    assert_absent "$HOME/.claude/skills/one-sided"
    assert_exists "$HOME/.agents/skills/one-sided/SKILL.md"
    assert_exists "$HOME/.config/tool/unrelated.txt"
    [[ "$(< "$HOME/.claude/skills/live/SKILL.md")" == fixture ]] || fail 'retained file modified'
}

test_cancel() {
    fixture
    local before output
    before="$(snapshot)"; CANCEL=true
    output="$(cmd_clean)"
    assert_has "$output" 'No files selected'
    [[ "$(snapshot)" == "$before" ]] || fail 'cancel changed the fixture tree'
}

test_recheck() {
    fixture
    CHOOSE_PATHS='live/extra file.txt'
    RECHECK_SOURCE="$DOTFILES_DIR/home/.claude/skills/live/extra file.txt"
    local output
    output="$(cmd_clean)"
    assert_has "$output" 'Deleted 1 orphaned path(s)'
    assert_exists "$RECHECK_SOURCE"
    assert_exists "$HOME/.claude/skills/live/extra file.txt"
    assert_absent "$HOME/.agents/skills/live/extra file.txt"
}

test_missing_roots() {
    fixture
    rm -rf "$DOTFILES_DIR/home/.agents/skills" "$HOME/.claude/skills"
    [[ -z "$(list_orphans)" ]] || fail 'missing roots must not produce candidates'
    local output
    output="$(cmd_clean)"
    assert_has "$output" 'No orphaned paths found'
    assert_exists "$HOME/.agents/skills/orphan skill/nested/SKILL.md"
}

test_noninteractive_cli() {
    fixture
    local before output command
    before="$(snapshot)"
    for command in clean prune; do
        output="$(HOME="$HOME" bash "$tmp/dot" --dotfiles-dir "$DOTFILES_DIR" "$command" </dev/null)"
        assert_has "$output" 'showing the list instead'
        assert_has "$output" 'live/extra file.txt'
        [[ "$(snapshot)" == "$before" ]] || fail "$command noninteractive deleted files"
    done
    output="$(HOME="$HOME" bash "$tmp/dot" --dotfiles-dir "$DOTFILES_DIR" clean --dry-run </dev/null)"
    assert_has "$output" 'No files were deleted'
    [[ "$(snapshot)" == "$before" ]] || fail 'noninteractive dry-run changed files'
}

test_missing_gum() {
    fixture
    command_exists() { [[ "$1" != gum ]] && command -v "$1" >/dev/null 2>&1; }
    local before output
    before="$(snapshot)"
    output="$(cmd_clean --dry-run)"
    assert_has "$output" 'gum not found; showing the list instead'
    assert_has "$output" 'live/extra file.txt'
    assert_has "$output" 'No files were deleted'
    if output="$(cmd_clean 2>&1)"; then
        fail 'interactive cleanup must require gum'
    fi
    assert_has "$output" 'gum not found. Install it with: brew install gum'
    [[ "$(snapshot)" == "$before" ]] || fail 'missing gum changed files'
}

test_invalid_arguments() {
    fixture
    local before output flag
    before="$(snapshot)"
    for flag in --unexpected --all; do
        if output="$(HOME="$HOME" bash "$tmp/dot" --dotfiles-dir "$DOTFILES_DIR" clean --dry-run "$flag" 2>&1 </dev/null)"; then
            fail "clean --dry-run $flag should fail"
        fi
        assert_has "$output" "Unexpected argument for clean: $flag"
    done
    if output="$(HOME="$HOME" bash "$tmp/dot" --dotfiles-dir "$DOTFILES_DIR" clean --all 2>&1 </dev/null)"; then
        fail 'Bash clean --all should fail'
    fi
    assert_has "$output" 'Unexpected argument for clean: --all'
    [[ "$(snapshot)" == "$before" ]] || fail 'invalid arguments changed files'
}

test_links() {
    fixture
    local outside="$tmp/outside" output rows
    put "$outside/sentinel.txt"
    mkdir -p "$DOTFILES_DIR/home/.claude/skills/live/linked"
    if ! ln -s "$outside" "$HOME/.claude/skills/live/linked" 2>/dev/null ||
        [[ ! -L "$HOME/.claude/skills/live/linked" ]]; then
        printf '  SKIP: real symlinks unavailable (MSYS may copy instead)\n'
        return 77
    fi
    ln -s "$outside" "$HOME/.claude/skills/orphan link"
    ln -s "$outside/missing" "$HOME/.claude/skills/dangling link"
    rows="$(list_orphans)"
    assert_lacks "$rows" 'sentinel.txt'
    expect_row "$rows" 'orphan link' '.claude'
    expect_row "$rows" 'dangling link' '.claude'
    CHOOSE_PATHS=$'orphan link\ndangling link'
    output="$(cmd_clean)"
    assert_has "$output" 'Deleted 2 orphaned path(s)'
    assert_absent "$HOME/.claude/skills/orphan link"
    assert_absent "$HOME/.claude/skills/dangling link"
    assert_exists "$outside/sentinel.txt"
    assert_exists "$HOME/.claude/skills/live/linked"
}

run() {
    printf '%s\n' "$1"
    set +e
    (set -e; "$1")
    local status=$?
    set -e
    case "$status" in
        0) ((++passed)) ;;
        77) ((++skipped)) ;;
        *) ((++failed)) ;;
    esac
}
for case in test_listing test_dry_run test_selected_only test_cancel test_recheck test_missing_roots test_noninteractive_cli test_missing_gum test_invalid_arguments test_links; do
    run "$case"
done
printf '\nBash clean: %s passed, %s failed, %s skipped\n' "$passed" "$failed" "$skipped"
[[ "$failed" == 0 ]]
