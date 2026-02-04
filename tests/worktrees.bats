#!/usr/bin/env bats
# Tests for worktrees.sh - Git Worktree Helper Functions
#
# Run with: bats tests/worktrees.bats
# Install bats: brew install bats-core

# Path to the script under test
SCRIPT_PATH="$BATS_TEST_DIRNAME/../worktrees.sh"

setup() {
    # Create a temporary directory for our test git repo
    TEST_DIR=$(mktemp -d)
    ORIG_DIR="$PWD"

    # Compute the project-specific worktrees directory
    TEST_PROJ=$(basename "$TEST_DIR")
    WT_DIR="$(dirname "$TEST_DIR")/${TEST_PROJ}-worktrees"

    # Initialize a git repo
    cd "$TEST_DIR"
    git init --initial-branch=main
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Create initial commit (required for worktrees)
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit"

    # Source the script to make the wt function available
    source "$SCRIPT_PATH"
}

teardown() {
    cd "$ORIG_DIR"

    # Clean up test directory and any worktrees created
    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
        rm -rf "$WT_DIR"
    fi
}

# ============================================================================
# wt add
# ============================================================================

@test "wt add: creates worktree with new branch" {
    run wt add feature-test

    [ "$status" -eq 0 ]
    [[ "$output" == *"(new branch feature-test)"* ]]

    # Verify worktree exists
    [ -d "$WT_DIR/feature-test" ]

    # Verify branch exists
    run git branch --list feature-test
    [[ "$output" == *"feature-test"* ]]
}

@test "wt add: fails without branch name" {
    run wt add

    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: wt add"* ]]
}

@test "wt add -s: creates worktree and switches to it" {
    wt add -s feature-switch

    # Verify we're now in the worktree directory
    [[ "$PWD" == *"-worktrees/feature-switch" ]]

    # Verify we're on the correct branch
    run git branch --show-current
    [ "$output" = "feature-switch" ]
}

@test "wt add --switch: long form works" {
    wt add --switch feature-long

    [[ "$PWD" == *"-worktrees/feature-long" ]]
}

@test "wt add: rejects unknown options" {
    run wt add -x feature-bad

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: -x"* ]]
}

@test "wt add: creates multiple worktrees" {
    run wt add feature-one
    [ "$status" -eq 0 ]

    run wt add feature-two
    [ "$status" -eq 0 ]

    [ -d "$WT_DIR/feature-one" ]
    [ -d "$WT_DIR/feature-two" ]
}

# ============================================================================
# wt cd
# ============================================================================

@test "wt cd: changes to existing worktree" {
    wt add feature-cd
    wt cd feature-cd

    [[ "$PWD" == *"-worktrees/feature-cd" ]]
}

@test "wt cd: without fzf and no branch shows install message" {
    # Temporarily hide fzf if it exists
    local old_path="$PATH"
    PATH="/usr/bin:/bin"

    run wt cd

    PATH="$old_path"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Interactive mode requires fzf"* ]]
}

# ============================================================================
# wt rm
# ============================================================================

@test "wt rm: removes worktree and branch" {
    wt add feature-remove

    # Verify it exists first
    [ -d "$WT_DIR/feature-remove" ]

    run wt rm feature-remove

    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed:"* ]]

    # Verify worktree is gone
    [ ! -d "$WT_DIR/feature-remove" ]

    # Verify branch is gone
    run git branch --list feature-remove
    [ -z "$output" ]
}

@test "wt rm: fails without branch name" {
    run wt rm

    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: wt rm"* ]]
}

# ============================================================================
# wt list / wt ls
# ============================================================================

@test "wt list: shows worktrees" {
    run wt list

    [ "$status" -eq 0 ]
    # Should show at least the main worktree
    [[ "$output" == *"$TEST_DIR"* ]]
}

@test "wt ls: alias works" {
    wt add feature-ls

    run wt ls

    [ "$status" -eq 0 ]
    [[ "$output" == *"feature-ls"* ]]
}

@test "wt list: shows multiple worktrees" {
    wt add feature-a
    wt add feature-b

    run wt list

    [[ "$output" == *"feature-a"* ]]
    [[ "$output" == *"feature-b"* ]]
}

# ============================================================================
# wt prune
# ============================================================================

@test "wt prune: runs without error" {
    run wt prune

    [ "$status" -eq 0 ]
    [[ "$output" == *"Pruned stale worktree references"* ]]
}

@test "wt prune: cleans stale references" {
    wt add feature-stale

    # Manually remove the directory without using git worktree remove
    rm -rf "$WT_DIR/feature-stale"

    # Now prune should clean it up
    run wt prune

    [ "$status" -eq 0 ]

    # Verify it's no longer listed
    run git worktree list
    [[ "$output" != *"feature-stale"* ]]
}

# ============================================================================
# wt help
# ============================================================================

@test "wt help: shows usage" {
    run wt help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Git Worktree Helper"* ]]
    [[ "$output" == *"Commands:"* ]]
}

@test "wt --help: flag works" {
    run wt --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Git Worktree Helper"* ]]
}

@test "wt -h: short flag works" {
    run wt -h

    [ "$status" -eq 0 ]
    [[ "$output" == *"Git Worktree Helper"* ]]
}

@test "wt: no args shows help" {
    run wt

    [ "$status" -eq 0 ]
    [[ "$output" == *"Git Worktree Helper"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "wt: unknown command fails" {
    run wt badcommand

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command: badcommand"* ]]
    [[ "$output" == *"Run 'wt help'"* ]]
}

@test "wt add: uses existing branch" {
    # Create a branch without a worktree
    git branch feature-existing

    run wt add feature-existing

    [ "$status" -eq 0 ]
    [[ "$output" == *"(existing branch feature-existing)"* ]]
    [ -d "$WT_DIR/feature-existing" ]
}

@test "wt add: fails if worktree already exists" {
    wt add feature-dup

    run wt add feature-dup

    [ "$status" -ne 0 ]
}
