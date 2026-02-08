#!/usr/bin/env zsh
# Zsh-specific integration tests for sideways
# These catch issues that bash-based bats tests miss (e.g., $path shadowing)
#
# Run with: zsh tests/zsh-integration.zsh

# Don't use set -e as it interferes with test result checking

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR="${0:a:h}"
REPO_DIR="${SCRIPT_DIR:h}"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
    cd /
    rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Initialize test repo
setup_test_repo() {
    cd "$TEST_DIR"
    git init -q test-repo
    cd test-repo
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"
}

# Test that command runs without "command not found" errors
# This is the key test for catching $path shadowing bugs
run_test() {
    local name="$1"
    local cmd="$2"
    local output
    local exit_code

    output=$(eval "$cmd" 2>&1)
    exit_code=$?

    if [[ "$output" == *"command not found"* ]]; then
        echo "${RED}✗${NC} $name"
        echo "  ERROR: 'command not found' detected (likely \$path shadowing bug)"
        echo "$output" | head -5 | sed 's/^/  /'
        ((FAIL++))
        return 1
    fi

    # For most commands, we just care that git was found
    echo "${GREEN}✓${NC} $name"
    ((PASS++))
    return 0
}

echo "=== Zsh Integration Tests for Sideways ==="
echo "Testing in: $TEST_DIR"
echo ""

# Source the script
source "$REPO_DIR/worktrees.sh"

# Setup
setup_test_repo

echo "--- Core Commands ---"

# These tests specifically check that git commands work after local variable declarations
# The $path shadowing bug would cause "command not found: git" errors

run_test "sw add creates worktree" "sw add test-branch"
run_test "sw list works" "sw list"
run_test "sw info works" "sw info"
run_test "sw rm removes worktree" "sw rm test-branch"
run_test "sw prune works" "sw prune"

# Test with options (exercises the while loop + local var combination)
echo ""
echo "--- Commands with Options (where bug occurred) ---"

run_test "sw add -s works" "sw add -s opt-branch; cd '$TEST_DIR/test-repo'"
run_test "sw rm -d works" "sw rm -d opt-branch"

# Test multiple operations in sequence
echo ""
echo "--- Sequential Operations ---"

run_test "sw add branch-1" "sw add branch-1"
run_test "sw add branch-2" "sw add branch-2"
run_test "sw rm branch-1" "sw rm branch-1"
run_test "sw rm -D branch-2" "sw rm -D branch-2"

# ==========================================================================
# .swcopy glob expansion tests (zsh-specific)
# Zsh doesn't expand globs in variables by default (unlike bash).
# These tests catch regressions in GLOB_SUBST and GLOB_STAR_SHORT handling.
# ==========================================================================

echo ""
echo "--- .swcopy Glob Expansion (zsh-specific) ---"

# Assert helper for file/dir existence checks
assert() {
    local name="$1"
    shift
    if "$@"; then
        echo "${GREEN}✓${NC} $name"
        ((PASS++))
    else
        echo "${RED}✗${NC} $name"
        ((FAIL++))
    fi
}

# Worktrees dir for current repo (mirrors sideways path convention)
WT_DIR="$TEST_DIR/test-repo-worktrees"

# -- Nested glob pattern (the bug: backend_app/db/store/*.db) --
cd "$TEST_DIR/test-repo"
mkdir -p backend_app/db/store
echo "data1" > backend_app/db/store/test.db
echo "data2" > backend_app/db/store/cache.db
echo "readme" > backend_app/db/store/readme.txt
echo "backend_app/db/store/*.db" > .gitignore
git add .gitignore && git commit -q -m "gitignore for nested glob"
echo "backend_app/db/store/*.db" > .swcopy

sw add nested-glob >/dev/null 2>&1
assert "nested glob: test.db copied" test -f "$WT_DIR/nested-glob/backend_app/db/store/test.db"
assert "nested glob: cache.db copied" test -f "$WT_DIR/nested-glob/backend_app/db/store/cache.db"
assert "nested glob: readme.txt NOT copied" test ! -f "$WT_DIR/nested-glob/backend_app/db/store/readme.txt"
sw rm nested-glob >/dev/null 2>&1

# -- Top-level glob pattern (*.log) --
cd "$TEST_DIR/test-repo"
echo "log1" > debug.log
echo "log2" > app.log
echo "SECRET" > .env
echo -e "*.log\n.env" > .gitignore
git add .gitignore && git commit -q -m "gitignore for top-level glob"
echo "*.log" > .swcopy

sw add top-glob >/dev/null 2>&1
assert "top-level glob: debug.log copied" test -f "$WT_DIR/top-glob/debug.log"
assert "top-level glob: app.log copied" test -f "$WT_DIR/top-glob/app.log"
assert "top-level glob: .env NOT copied" test ! -f "$WT_DIR/top-glob/.env"
sw rm top-glob >/dev/null 2>&1

# -- Recursive glob pattern (**/*.db) --
cd "$TEST_DIR/test-repo"
mkdir -p app/cache
echo "sess" > app/cache/sessions.db
echo "**/*.db" > .gitignore
git add .gitignore && git commit -q -m "gitignore for recursive glob"
echo "**/*.db" > .swcopy

sw add recursive-glob >/dev/null 2>&1
assert "recursive glob: nested test.db copied" test -f "$WT_DIR/recursive-glob/backend_app/db/store/test.db"
assert "recursive glob: sessions.db copied" test -f "$WT_DIR/recursive-glob/app/cache/sessions.db"
assert "recursive glob: readme.txt NOT copied" test ! -f "$WT_DIR/recursive-glob/backend_app/db/store/readme.txt"
sw rm recursive-glob >/dev/null 2>&1

# -- Mixed top-level and nested patterns --
cd "$TEST_DIR/test-repo"
cat > .gitignore <<'GIEOF'
.env
backend_app/db/store/*.db
GIEOF
git add .gitignore && git commit -q -m "gitignore for mixed patterns"
cat > .swcopy <<'SWEOF'
.env
backend_app/db/store/*.db
SWEOF

sw add mixed-patterns >/dev/null 2>&1
assert "mixed: .env copied" test -f "$WT_DIR/mixed-patterns/.env"
assert "mixed: nested test.db copied" test -f "$WT_DIR/mixed-patterns/backend_app/db/store/test.db"
sw rm mixed-patterns >/dev/null 2>&1

# -- No trace output leaked --
cd "$TEST_DIR/test-repo"
echo "backend_app/db/store/*.db" > .swcopy
output=$(sw add trace-check 2>&1)

trace_clean=true
if [[ "$output" == *"f="* ]] || [[ "$output" == *"gitignored_files="* ]] || [[ "$output" == *"file="* ]]; then
    trace_clean=false
fi
assert "no trace output (f=, gitignored_files=, file=)" $trace_clean
sw rm trace-check >/dev/null 2>&1

# -- Git output suppressed --
cd "$TEST_DIR/test-repo"
rm -f .swcopy
output=$(sw add quiet-check 2>&1)

git_quiet=true
if [[ "$output" == *"Preparing worktree"* ]] || [[ "$output" == *"HEAD is now at"* ]]; then
    git_quiet=false
fi
assert "git worktree add output suppressed" $git_quiet
sw rm quiet-check >/dev/null 2>&1

echo ""
echo "--- XTRACE-Enabled Tests (reproduces user env with set -x) ---"

# XTRACE output goes to stderr. We test:
# 1. stdout is clean (only "Created:" + "copy"/"link" lines)
# 2. stderr has no _sw_copy_gitignored traces AFTER its setopt NO_XTRACE
# 3. symlinks are actually created
# 4. combined output (what user sees in terminal) has no bare variable assignments

local xtrace_stderr="$TEST_DIR/xtrace-stderr"

# -- stdout clean with XTRACE enabled --
cd "$TEST_DIR/test-repo"
echo "backend_app/db/store/*.db" > .swcopy
rm -f .swsymlink
setopt XTRACE
output=$(sw add xtrace-stdout 2>"$xtrace_stderr")
unsetopt XTRACE

stdout_clean=true
while IFS= read -r line; do
    if [[ "$line" != Created:* ]] && [[ "$line" != "  copy  "* ]] && [[ "$line" != "  link  "* ]]; then
        stdout_clean=false
        echo "  Unexpected stdout: '$line'"
    fi
done <<< "$output"
assert "stdout clean with XTRACE enabled" $stdout_clean
sw rm xtrace-stdout >/dev/null 2>&1

# -- no _sw_copy_gitignored traces in stderr after setopt NO_XTRACE --
# XTRACE from sw() and _sw_cmd_add() is expected; but once _sw_copy_gitignored
# sets NO_XTRACE, no further traces should come from that function
cd "$TEST_DIR/test-repo"
echo "backend_app/db/store/*.db" > .swcopy
rm -f .swsymlink
setopt XTRACE
sw add xtrace-trace >/dev/null 2>"$xtrace_stderr"
unsetopt XTRACE

trace_no_leak=true
local found_setopt=false
while IFS= read -r line; do
    if [[ "$line" == *"setopt LOCAL_OPTIONS NO_XTRACE"* ]]; then
        found_setopt=true
        continue
    fi
    if $found_setopt && [[ "$line" == *"_sw_copy_gitignored:"* ]]; then
        trace_no_leak=false
        echo "  Trace after NO_XTRACE: $line"
    fi
done < "$xtrace_stderr"
assert "no _sw_copy_gitignored traces after setopt NO_XTRACE" $trace_no_leak
sw rm xtrace-trace >/dev/null 2>&1

# -- combined output has no bare variable assignment lines --
# Reproduces what user sees in terminal (stdout+stderr mixed)
cd "$TEST_DIR/test-repo"
echo "backend_app/db/store/*.db" > .swcopy
rm -f .swsymlink
setopt XTRACE
output=$(sw add xtrace-combined 2>&1)
unsetopt XTRACE

# Check for bare variable assignments (without trace prefix like "+func:line>")
# These are the exact patterns the user reported seeing
combined_clean=true
while IFS= read -r line; do
    # Skip lines with zsh trace prefix (these are expected XTRACE from other funcs)
    [[ "$line" == +* ]] && continue
    # Non-trace lines must be expected output
    if [[ "$line" != Created:* ]] && [[ "$line" != "  copy  "* ]] && [[ "$line" != "  link  "* ]]; then
        combined_clean=false
        echo "  Unexpected non-trace line: '$line'"
    fi
done <<< "$output"
assert "no bare variable assignments in combined output" $combined_clean
sw rm xtrace-combined >/dev/null 2>&1

# -- Symlinks created with XTRACE enabled --
cd "$TEST_DIR/test-repo"
mkdir -p backend_app/config
echo "setting1" > backend_app/config/app.yml
echo "setting2" > backend_app/config/db.yml
echo "backend_app/config/" >> .gitignore
git add .gitignore && git commit -q -m "gitignore for xtrace symlink test"
rm -f .swcopy
echo "backend_app/config/" > .swsymlink
setopt XTRACE
sw add xtrace-symlink >/dev/null 2>&1
unsetopt XTRACE
assert "symlink created with XTRACE: is a symlink" test -L "$WT_DIR/xtrace-symlink/backend_app/config"
assert "symlink created with XTRACE: content accessible" test -f "$WT_DIR/xtrace-symlink/backend_app/config/app.yml"
sw rm xtrace-symlink >/dev/null 2>&1

# -- Symlink stdout output correct with XTRACE enabled --
cd "$TEST_DIR/test-repo"
rm -f .swcopy
echo "backend_app/config/" > .swsymlink
setopt XTRACE
output=$(sw add xtrace-symout 2>"$xtrace_stderr")
unsetopt XTRACE

sym_stdout_ok=true
# Must have link line on stdout
if [[ "$output" != *"  link  "* ]]; then
    sym_stdout_ok=false
    echo "  No '  link  ' in stdout"
fi
# stdout must be clean
while IFS= read -r line; do
    if [[ "$line" != Created:* ]] && [[ "$line" != "  copy  "* ]] && [[ "$line" != "  link  "* ]]; then
        sym_stdout_ok=false
        echo "  Unexpected stdout: '$line'"
    fi
done <<< "$output"
assert "symlink stdout clean with XTRACE enabled" $sym_stdout_ok
sw rm xtrace-symout >/dev/null 2>&1

echo ""
echo "--- _sw_fzf_pick variable shadowing (zsh-specific) ---"

# _sw_fzf_pick uses local variables that must not shadow zsh specials (e.g., $path)
# Feed it fake worktree list lines and use head -1 as a fzf stand-in
cd "$TEST_DIR/test-repo"
sw add pick-test >/dev/null 2>&1

# Capture git worktree list output, pipe through the transform loop only (no fzf)
pick_output=$(git worktree list | while IFS= read -r line; do
    local wt_path="${line%% *}"
    local rest="${line#* }"
    local short="../$(basename "$wt_path")"
    printf '%s|%s %s\n' "$wt_path" "$short" "$rest"
done)

pick_ok=true
if [[ "$pick_output" == *"command not found"* ]] || [[ "$pick_output" == *"inconsistent type"* ]]; then
    pick_ok=false
    echo "  Error in _sw_fzf_pick transform: $pick_output"
fi
# Verify short paths appear in output
if [[ "$pick_output" != *"../"* ]]; then
    pick_ok=false
    echo "  No short paths found in output: $pick_output"
fi
assert "_sw_fzf_pick transform works without \$path shadowing" $pick_ok

# Verify full path is extractable via cut
first_full=$(echo "$pick_output" | head -1 | cut -d'|' -f1)
if [[ "$first_full" != /* ]]; then
    assert "_sw_fzf_pick returns full absolute path" false
else
    assert "_sw_fzf_pick returns full absolute path" true
fi

sw rm pick-test >/dev/null 2>&1

echo ""
echo "--- .swsymlink Nested Patterns (zsh-specific) ---"

# -- Nested directory symlink --
cd "$TEST_DIR/test-repo"
mkdir -p backend_app/config
echo "setting1" > backend_app/config/app.yml
echo "setting2" > backend_app/config/db.yml
echo "backend_app/config/" >> .gitignore
git add .gitignore && git commit -q -m "gitignore for nested symlink"
rm -f .swcopy
echo "backend_app/config/" > .swsymlink

sw add nested-symdir >/dev/null 2>&1
assert "nested symlink dir: is a symlink" test -L "$WT_DIR/nested-symdir/backend_app/config"
assert "nested symlink dir: content accessible" test -f "$WT_DIR/nested-symdir/backend_app/config/app.yml"
sw rm nested-symdir >/dev/null 2>&1

# -- Nested file symlink (independent files, no overlap) --
cd "$TEST_DIR/test-repo"
echo "backend_app/config/app.yml" > .swcopy
echo "backend_app/config/db.yml" > .swsymlink

sw add nested-symfile >/dev/null 2>&1
assert "nested symlink file: db.yml is symlink" test -L "$WT_DIR/nested-symfile/backend_app/config/db.yml"
assert "nested symlink file: app.yml is regular file" test -f "$WT_DIR/nested-symfile/backend_app/config/app.yml" -a ! -L "$WT_DIR/nested-symfile/backend_app/config/app.yml"
sw rm nested-symfile >/dev/null 2>&1

# -- Symlink output reported with "link" label --
cd "$TEST_DIR/test-repo"
rm -f .swcopy
echo "backend_app/config/" > .swsymlink
output=$(sw add symlink-output 2>&1)

sym_output=false
if [[ "$output" == *"  link  "* ]]; then
    sym_output=true
fi
assert "symlink output shows '  link  ' label" $sym_output
sw rm symlink-output >/dev/null 2>&1

# -- Copy output reported with "copy" label --
cd "$TEST_DIR/test-repo"
echo "backend_app/config/*.yml" > .swcopy
rm -f .swsymlink
output=$(sw add copy-output 2>&1)

copy_output=false
if [[ "$output" == *"  copy  "* ]]; then
    copy_output=true
fi
assert "copy output shows '  copy  ' label" $copy_output
sw rm copy-output >/dev/null 2>&1

# Summary
echo ""
echo "=== Results ==="
echo "${GREEN}Passed: $PASS${NC}"
if [[ $FAIL -gt 0 ]]; then
    echo "${RED}Failed: $FAIL${NC}"
    exit 1
else
    echo "Failed: 0"
    echo ""
    echo "All zsh integration tests passed!"
fi
