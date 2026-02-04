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
