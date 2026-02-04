#!/usr/bin/env bats
# Tests for worktrees.sh - Sideways Git Worktree Helper
#
# Run with: bats tests/worktrees.bats
# Install bats: brew install bats-core

# Path to the script under test
SCRIPT_PATH="$BATS_TEST_DIRNAME/../worktrees.sh"

setup() {
    # Create a temporary directory for our test git repo
    # Use pwd -P to resolve symlinks (macOS /var -> /private/var)
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    TEST_DIR=$(pwd -P)
    ORIG_DIR="$PWD"

    # Compute the project-specific worktrees directory
    TEST_PROJ=$(basename "$TEST_DIR")
    WT_DIR="$(dirname "$TEST_DIR")/${TEST_PROJ}-worktrees"

    # Initialize a git repo (already in TEST_DIR)
    git init --initial-branch=main
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Create initial commit (required for worktrees)
    echo "initial" > README.md
    git add README.md
    git commit -m "Initial commit"

    # Source the script to make the sw function available
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
# sw add
# ============================================================================

@test "sw add: creates worktree with new branch" {
    run sw add feature-test

    [ "$status" -eq 0 ]
    [[ "$output" == *"(new branch feature-test)"* ]]

    # Verify worktree exists
    [ -d "$WT_DIR/feature-test" ]

    # Verify branch exists
    run git branch --list feature-test
    [[ "$output" == *"feature-test"* ]]
}

@test "sw add: fails without branch name" {
    run sw add

    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: sw add"* ]]
}

@test "sw add -s: creates worktree and switches to it" {
    sw add -s feature-switch

    # Verify we're now in the worktree directory
    [[ "$PWD" == *"-worktrees/feature-switch" ]]

    # Verify we're on the correct branch
    run git branch --show-current
    [ "$output" = "feature-switch" ]
}

@test "sw add --switch: long form works" {
    sw add --switch feature-long

    [[ "$PWD" == *"-worktrees/feature-long" ]]
}

@test "sw add: rejects unknown options" {
    run sw add -x feature-bad

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: -x"* ]]
}

@test "sw add: creates multiple worktrees" {
    run sw add feature-one
    [ "$status" -eq 0 ]

    run sw add feature-two
    [ "$status" -eq 0 ]

    [ -d "$WT_DIR/feature-one" ]
    [ -d "$WT_DIR/feature-two" ]
}

# ============================================================================
# sw cd
# ============================================================================

@test "sw cd: changes to existing worktree" {
    sw add feature-cd
    sw cd feature-cd

    [[ "$PWD" == *"-worktrees/feature-cd" ]]
}

@test "sw cd: without fzf and no branch shows install message" {
    # Temporarily hide fzf if it exists
    local old_path="$PATH"
    PATH="/usr/bin:/bin"

    run sw cd

    PATH="$old_path"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Interactive mode requires fzf"* ]]
}

@test "sw cd: works from inside a worktree" {
    sw add feature-one
    sw add -s feature-two
    # Now we're in feature-two worktree

    sw cd feature-one
    # Should be in feature-one worktree

    [[ "$PWD" == *"-worktrees/feature-one" ]]
    run git branch --show-current
    [ "$output" = "feature-one" ]
}

# ============================================================================
# sw rm
# ============================================================================

@test "sw rm: removes worktree but keeps branch" {
    sw add feature-remove

    # Verify it exists first
    [ -d "$WT_DIR/feature-remove" ]

    run sw rm feature-remove

    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed worktree:"* ]]

    # Verify worktree is gone
    [ ! -d "$WT_DIR/feature-remove" ]

    # Verify branch still exists
    run git branch --list feature-remove
    [[ "$output" == *"feature-remove"* ]]
}

@test "sw rm -d: removes worktree and deletes merged branch" {
    sw add feature-merged

    # Make the branch "merged" by not adding any commits
    # (it's at same point as main, so -d will work)

    run sw rm -d feature-merged

    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed worktree:"* ]]
    [[ "$output" == *"Deleted branch:"* ]]

    # Verify worktree is gone
    [ ! -d "$WT_DIR/feature-merged" ]

    # Verify branch is gone
    run git branch --list feature-merged
    [ -z "$output" ]
}

@test "sw rm -d: removes worktree but fails to delete unmerged branch" {
    sw add -s feature-unmerged

    # Add a commit so the branch is not merged
    echo "unmerged change" > unmerged.txt
    git add unmerged.txt
    git commit -m "Unmerged commit"

    # Go back to base
    sw base

    run sw rm -d feature-unmerged

    # Command succeeds (worktree removed) but branch deletion fails
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed worktree:"* ]]
    [[ "$output" == *"not fully merged"* ]]

    # Verify worktree is gone
    [ ! -d "$WT_DIR/feature-unmerged" ]

    # Verify branch still exists (deletion failed)
    run git branch --list feature-unmerged
    [[ "$output" == *"feature-unmerged"* ]]
}

@test "sw rm -D: removes worktree and force deletes unmerged branch" {
    sw add -s feature-force

    # Add a commit so the branch is not merged
    echo "force delete change" > force.txt
    git add force.txt
    git commit -m "Force delete commit"

    # Go back to base
    sw base

    run sw rm -D feature-force

    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed worktree:"* ]]
    [[ "$output" == *"Deleted branch:"* ]]

    # Verify worktree is gone
    [ ! -d "$WT_DIR/feature-force" ]

    # Verify branch is gone (force deleted)
    run git branch --list feature-force
    [ -z "$output" ]
}

@test "sw rm: fails without branch name" {
    run sw rm

    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: sw rm"* ]]
}

@test "sw rm: rejects unknown options" {
    sw add feature-bad-opt

    run sw rm -x feature-bad-opt

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option: -x"* ]]
}

# ============================================================================
# sw list / wt ls
# ============================================================================

@test "sw list: shows worktrees" {
    run sw list

    [ "$status" -eq 0 ]
    # Should show at least the main worktree with new format: branch location commit
    [[ "$output" == *"main"* ]]
    [[ "$output" == *"base"* ]]
}

@test "sw ls: alias works" {
    sw add feature-ls

    run sw ls

    [ "$status" -eq 0 ]
    [[ "$output" == *"feature-ls"* ]]
}

@test "sw list: shows multiple worktrees" {
    sw add feature-a
    sw add feature-b

    run sw list

    [[ "$output" == *"feature-a"* ]]
    [[ "$output" == *"feature-b"* ]]
}

@test "sw list: shows current worktree indicator" {
    sw add -s feature-current
    # Now in the worktree
    [[ "$PWD" == *"-worktrees/feature-current" ]]

    run sw list

    # Current worktree should have asterisk marker
    [[ "$output" == *"* feature-current"* ]]
    # Base should not have asterisk (space instead)
    [[ "$output" == *"  main"* ]]
}

@test "sw list: shows modified status" {
    sw add -s feature-dirty
    # Make uncommitted changes in the worktree
    echo "dirty" >> README.md

    run sw list

    [[ "$output" == *"feature-dirty"*"[modified]"* ]]
}

# ============================================================================
# sw prune
# ============================================================================

@test "sw prune: runs without error" {
    run sw prune

    [ "$status" -eq 0 ]
    [[ "$output" == *"Pruned stale worktree references"* ]]
}

@test "sw prune: cleans stale references" {
    sw add feature-stale

    # Manually remove the directory without using git worktree remove
    rm -rf "$WT_DIR/feature-stale"

    # Now prune should clean it up
    run sw prune

    [ "$status" -eq 0 ]

    # Verify it's no longer listed
    run git worktree list
    [[ "$output" != *"feature-stale"* ]]
}

# ============================================================================
# sw help
# ============================================================================

@test "sw help: shows usage" {
    run sw help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Sideways"* ]]
    [[ "$output" == *"From base directory"* ]]
}

@test "sw --help: flag works" {
    run sw --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Sideways"* ]]
}

@test "sw -h: short flag works" {
    run sw -h

    [ "$status" -eq 0 ]
    [[ "$output" == *"Sideways"* ]]
}

@test "sw: no args shows help" {
    run sw

    [ "$status" -eq 0 ]
    [[ "$output" == *"Sideways - Git Worktree Helper"* ]]
}

# ============================================================================
# Error handling
# ============================================================================

@test "sw: unknown command fails" {
    run sw badcommand

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command: badcommand"* ]]
    [[ "$output" == *"Run 'sw help'"* ]]
}

@test "sw add: uses existing branch" {
    # Create a branch without a worktree
    git branch feature-existing

    run sw add feature-existing

    [ "$status" -eq 0 ]
    [[ "$output" == *"(existing branch feature-existing)"* ]]
    [ -d "$WT_DIR/feature-existing" ]
}

@test "sw add: fails if worktree already exists" {
    sw add feature-dup

    run sw add feature-dup

    [ "$status" -ne 0 ]
}

@test "sw add: fails from inside a worktree" {
    sw add -s feature-nested

    run sw add another-branch

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run from base directory"* ]]
}

@test "sw rm: fails from inside a worktree" {
    sw add feature-rm-test
    sw add -s feature-in-wt

    run sw rm feature-rm-test

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run from base directory"* ]]
}

@test "sw rm: fails with uncommitted changes" {
    sw add feature-dirty-rm
    # Make uncommitted changes in the worktree
    echo "dirty" >> "$TEST_DIR/../$(basename "$TEST_DIR")-worktrees/feature-dirty-rm/README.md"

    run sw rm feature-dirty-rm

    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

# ============================================================================
# sw base
# ============================================================================

@test "sw base: jumps to base from worktree" {
    sw add -s feature-base
    # Now we're in the worktree
    [[ "$PWD" == *"-worktrees/feature-base" ]]

    sw base

    # Should be back in the original test directory (base)
    [[ "$PWD" == "$TEST_DIR" ]]
}

@test "sw base: shows message when already in base" {
    run sw base

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already in base directory"* ]]
}

# ============================================================================
# sw info
# ============================================================================

@test "sw info: shows info when in base" {
    run sw info

    [ "$status" -eq 0 ]
    [[ "$output" == *"Branch:"* ]]
    [[ "$output" == *"Path:"* ]]
    [[ "$output" == *"Location: base"* ]]
}

@test "sw info: shows info when in worktree" {
    sw add -s feature-info

    run sw info

    [ "$status" -eq 0 ]
    [[ "$output" == *"Branch:   feature-info"* ]]
    [[ "$output" == *"Location: worktree"* ]]
}

# ============================================================================
# sw rebase
# ============================================================================

@test "sw rebase: requires branch argument" {
    run sw rebase

    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: sw rebase <branch>"* ]]
}

@test "sw rebase: fails without remote" {
    # No remote configured in test repo
    run sw rebase main

    [ "$status" -ne 0 ]
}

# ============================================================================
# sw done
# ============================================================================

@test "sw done: removes worktree and keeps branch" {
    sw add -s feature-done
    # Now we're in the worktree
    [[ "$PWD" == *"-worktrees/feature-done" ]]

    sw done

    # Should be back in base
    [[ "$PWD" == "$TEST_DIR" ]]

    # Worktree should be gone
    [ ! -d "$WT_DIR/feature-done" ]

    # Branch should still exist
    run git branch --list feature-done
    [[ "$output" == *"feature-done"* ]]
}

@test "sw done: fails when in base" {
    run sw done

    [ "$status" -eq 1 ]
    [[ "$output" == *"not in a worktree"* ]]
}

@test "sw done: fails with uncommitted changes" {
    sw add -s feature-dirty-done
    # Make uncommitted changes
    echo "dirty" >> README.md

    run sw done

    [ "$status" -eq 1 ]
    [[ "$output" == *"uncommitted changes"* ]]
}

# ============================================================================
# sw add: gitignored file copying
# ============================================================================

@test "sw add: no .swcopy means nothing copied" {
    # Create gitignore and gitignored files but no .swcopy
    echo ".env" >> .gitignore
    echo "SECRET=abc123" > .env
    git add .gitignore
    git commit -m "Add gitignore"

    run sw add feature-nocopy

    [ "$status" -eq 0 ]
    # File should NOT be copied (no .swcopy)
    [ ! -f "$WT_DIR/feature-nocopy/.env" ]
}

@test "sw add: copies files listed in .swcopy" {
    # Create gitignore and gitignored files
    echo ".env" >> .gitignore
    echo "SECRET=abc123" > .env
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy to include .env
    echo ".env" > .swcopy

    run sw add feature-copy

    [ "$status" -eq 0 ]
    # Verify the gitignored file was copied
    [ -f "$WT_DIR/feature-copy/.env" ]
    [[ "$(cat "$WT_DIR/feature-copy/.env")" == "SECRET=abc123" ]]
}

@test "sw add: copies multiple files from .swcopy" {
    # Create gitignore with multiple patterns
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
.envrc
EOF
    echo "SECRET=abc" > .env
    echo "local instructions" > CLAUDE.local.md
    echo "layout ruby" > .envrc
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy with multiple patterns
    cat > .swcopy <<'EOF'
.env
CLAUDE.local.md
.envrc
EOF

    run sw add feature-multi

    [ "$status" -eq 0 ]
    [ -f "$WT_DIR/feature-multi/.env" ]
    [ -f "$WT_DIR/feature-multi/CLAUDE.local.md" ]
    [ -f "$WT_DIR/feature-multi/.envrc" ]
}

@test "sw add: .swcopy copies directories" {
    # Create gitignore for a directory
    echo "logs/" >> .gitignore
    mkdir -p logs
    echo "log1" > logs/app.log
    echo "log2" > logs/error.log
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy to include logs
    echo "logs/" > .swcopy

    run sw add feature-dir

    [ "$status" -eq 0 ]
    [ -d "$WT_DIR/feature-dir/logs" ]
    [ -f "$WT_DIR/feature-dir/logs/app.log" ]
    [ -f "$WT_DIR/feature-dir/logs/error.log" ]
}

@test "sw add: .swcopy only copies matching patterns" {
    # Create gitignore
    cat > .gitignore <<'EOF'
.env
node_modules/
EOF
    echo "SECRET=abc" > .env
    mkdir -p node_modules/pkg
    echo "package" > node_modules/pkg/index.js
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy to only include .env (not node_modules)
    echo ".env" > .swcopy

    run sw add feature-selective

    [ "$status" -eq 0 ]
    # .env should be copied (in .swcopy)
    [ -f "$WT_DIR/feature-selective/.env" ]
    # node_modules should NOT be copied (not in .swcopy)
    [ ! -d "$WT_DIR/feature-selective/node_modules" ]
}

@test "sw add: .swcopy supports glob patterns" {
    # Create gitignore
    cat > .gitignore <<'EOF'
.env
debug.log
app.log
EOF
    echo "SECRET=abc" > .env
    echo "debug info" > debug.log
    echo "app info" > app.log
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy to include all log files
    echo "*.log" > .swcopy

    run sw add feature-glob

    [ "$status" -eq 0 ]
    # .env should NOT be copied (not in .swcopy)
    [ ! -f "$WT_DIR/feature-glob/.env" ]
    # log files should be copied
    [ -f "$WT_DIR/feature-glob/debug.log" ]
    [ -f "$WT_DIR/feature-glob/app.log" ]
}

@test "sw add: .swcopy comments and blank lines ignored" {
    # Create gitignore
    cat > .gitignore <<'EOF'
.env
build/
EOF
    echo "SECRET=abc" > .env
    mkdir -p build
    echo "output" > build/app.js
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy with comments and blank lines
    cat > .swcopy <<'EOF'
# This is a comment
.env

# Another comment
EOF

    run sw add feature-comments

    [ "$status" -eq 0 ]
    # .env should be copied
    [ -f "$WT_DIR/feature-comments/.env" ]
    # build should NOT be copied (not in .swcopy)
    [ ! -d "$WT_DIR/feature-comments/build" ]
}

@test "sw add: outputs list of copied items" {
    # Create gitignore and files
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "SECRET=abc" > .env
    echo "local" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy
    cat > .swcopy <<'EOF'
.env
CLAUDE.local.md
EOF

    run sw add feature-output

    [ "$status" -eq 0 ]
    # Should list copied files in output
    [[ "$output" == *"Copied:"* ]]
    [[ "$output" == *".env"* ]]
    [[ "$output" == *"CLAUDE.local.md"* ]]
}

@test "sw add: no output when nothing to copy" {
    # No .swcopy file
    run sw add feature-nothing

    [ "$status" -eq 0 ]
    # Should not mention copying
    [[ "$output" != *"Copied:"* ]]
}

@test "sw add -s: copies files before switching" {
    # Create gitignore and file
    echo ".env" >> .gitignore
    echo "SECRET=abc" > .env
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy
    echo ".env" > .swcopy

    sw add -s feature-switch-copy

    # Should be in worktree
    [[ "$PWD" == *"-worktrees/feature-switch-copy" ]]
    # File should exist in worktree
    [ -f ".env" ]
    [[ "$(cat .env)" == "SECRET=abc" ]]
}

@test "sw add: .swcopy itself can be gitignored and copied" {
    # .swcopy should be copied if it's gitignored and in .swcopy
    cat > .gitignore <<'EOF'
.env
.swcopy
EOF
    echo "SECRET=abc" > .env
    cat > .swcopy <<'EOF'
.env
.swcopy
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    run sw add feature-swcopy-copy

    [ "$status" -eq 0 ]
    # .swcopy should be copied
    [ -f "$WT_DIR/feature-swcopy-copy/.swcopy" ]
    [ -f "$WT_DIR/feature-swcopy-copy/.env" ]
}

# ============================================================================
# sw add: .swsymlink support
# ============================================================================

@test "sw add: symlinks files listed in .swsymlink" {
    # Create gitignore and files
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "SECRET=abc" > .env
    echo "local instructions" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    # Create .swcopy to include both files
    cat > .swcopy <<'EOF'
.env
CLAUDE.local.md
EOF
    # Create .swsymlink to symlink CLAUDE.local.md
    echo "CLAUDE.local.md" > .swsymlink

    run sw add feature-symlink

    [ "$status" -eq 0 ]
    # .env should be copied (regular file)
    [ -f "$WT_DIR/feature-symlink/.env" ]
    [ ! -L "$WT_DIR/feature-symlink/.env" ]
    # CLAUDE.local.md should be a symlink
    [ -L "$WT_DIR/feature-symlink/CLAUDE.local.md" ]
    # Symlink should point to base file
    [[ "$(readlink "$WT_DIR/feature-symlink/CLAUDE.local.md")" == *"CLAUDE.local.md" ]]
}

@test "sw add: symlinked file content matches base" {
    echo "CLAUDE.local.md" >> .gitignore
    echo "original content" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    echo "CLAUDE.local.md" > .swcopy
    echo "CLAUDE.local.md" > .swsymlink

    sw add feature-symlink-content

    # Content should match
    [[ "$(cat "$WT_DIR/feature-symlink-content/CLAUDE.local.md")" == "original content" ]]

    # Modify base file
    echo "modified content" > CLAUDE.local.md

    # Worktree should see the change (because it's a symlink)
    [[ "$(cat "$WT_DIR/feature-symlink-content/CLAUDE.local.md")" == "modified content" ]]
}

@test "sw add: .swsymlink supports glob patterns" {
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
.envrc
EOF
    echo "SECRET=abc" > .env
    echo "local" > CLAUDE.local.md
    echo "layout ruby" > .envrc
    git add .gitignore
    git commit -m "Add gitignore"

    # Include all in .swcopy
    cat > .swcopy <<'EOF'
.env
CLAUDE.local.md
.envrc
EOF
    # Symlink CLAUDE* files
    echo "CLAUDE*" > .swsymlink

    run sw add feature-symlink-glob

    [ "$status" -eq 0 ]
    # .env should be copied (not symlinked)
    [ -f "$WT_DIR/feature-symlink-glob/.env" ]
    [ ! -L "$WT_DIR/feature-symlink-glob/.env" ]
    # CLAUDE.local.md should be symlinked
    [ -L "$WT_DIR/feature-symlink-glob/CLAUDE.local.md" ]
    # .envrc should be copied (not symlinked)
    [ -f "$WT_DIR/feature-symlink-glob/.envrc" ]
    [ ! -L "$WT_DIR/feature-symlink-glob/.envrc" ]
}

@test "sw add: .swsymlink can symlink directories" {
    echo "config/" >> .gitignore
    mkdir -p config
    echo "setting1" > config/app.yml
    echo "setting2" > config/db.yml
    git add .gitignore
    git commit -m "Add gitignore"

    echo "config/" > .swcopy
    echo "config/" > .swsymlink

    run sw add feature-symlink-dir

    [ "$status" -eq 0 ]
    # config should be a symlink to directory
    [ -L "$WT_DIR/feature-symlink-dir/config" ]
    # Files inside should be accessible
    [ -f "$WT_DIR/feature-symlink-dir/config/app.yml" ]
}

@test "sw add: outputs symlinked items separately" {
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "SECRET=abc" > .env
    echo "local" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    # Include both in .swcopy
    cat > .swcopy <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "CLAUDE.local.md" > .swsymlink

    run sw add feature-symlink-output

    [ "$status" -eq 0 ]
    # Should show copied files
    [[ "$output" == *"Copied:"* ]]
    [[ "$output" == *".env"* ]]
    # Should show symlinked files
    [[ "$output" == *"Symlinked:"* ]]
    [[ "$output" == *"CLAUDE.local.md"* ]]
}

@test "sw add: .swsymlink without .swcopy does nothing" {
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "SECRET=abc" > .env
    echo "local" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    # Only .swsymlink, no .swcopy
    echo "CLAUDE.local.md" > .swsymlink

    run sw add feature-symlink-only

    [ "$status" -eq 0 ]
    # Nothing should exist (no .swcopy)
    [ ! -e "$WT_DIR/feature-symlink-only/.env" ]
    [ ! -e "$WT_DIR/feature-symlink-only/CLAUDE.local.md" ]
}
