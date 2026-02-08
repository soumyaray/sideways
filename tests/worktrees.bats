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

@test "sw add -o: creates worktree and opens in editor" {
    export VISUAL="echo"

    run sw add -o feature-open

    [ "$status" -eq 0 ]
    [ -d "$WT_DIR/feature-open" ]
    # Editor (echo) should output the worktree path
    [[ "$output" == *"$WT_DIR/feature-open"* ]]
}

@test "sw add -so: creates, switches, and opens" {
    export VISUAL="echo"

    sw add -so feature-combo

    # Should be in the worktree
    [[ "$PWD" == *"-worktrees/feature-combo" ]]
    # Worktree should exist
    [ -d "$WT_DIR/feature-combo" ]
}

@test "sw add -o: warns but succeeds when no editor configured" {
    unset VISUAL
    unset EDITOR

    run sw add -o feature-no-editor

    [ "$status" -eq 0 ]
    # Worktree should still be created
    [ -d "$WT_DIR/feature-no-editor" ]
    # Should warn about no editor
    [[ "$output" == *"Warning: cannot open"* ]]
    [[ "$output" == *"no editor configured"* ]]
}

@test "sw add -o: fails from inside a worktree" {
    sw add -s feature-nested
    export VISUAL="echo"

    run sw add -o another-branch

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be run from base directory"* ]]
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

@test "sw rm: without fzf and no branch shows install message" {
    # Temporarily hide fzf if it exists
    local old_path="$PATH"
    PATH="/usr/bin:/bin"

    run sw rm

    PATH="$old_path"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Interactive mode requires fzf"* ]]
    [[ "$output" == *"sw rm [-d|-D] <branch-name>"* ]]
}

@test "sw rm: -d flag without fzf and no branch shows install message" {
    local old_path="$PATH"
    PATH="/usr/bin:/bin"

    run sw rm -d

    PATH="$old_path"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Interactive mode requires fzf"* ]]
    [[ "$output" == *"sw rm [-d|-D] <branch-name>"* ]]
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

    # Current worktree should have asterisk marker (* <space> commit <tab> location <tab> branch)
    [[ "$output" == *"* "*"feature-current"* ]]
    # Base should not have asterisk (space instead, so two spaces before commit)
    [[ "$output" == *"  "*"main"* ]]
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

@test "sw --version: shows version" {
    run sw --version

    [ "$status" -eq 0 ]
    [[ "$output" == "sideways "* ]]
}

@test "sw -V: short version flag works" {
    run sw -V

    [ "$status" -eq 0 ]
    [[ "$output" == "sideways "* ]]
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

@test "sw add: outputs per-line list of copied items" {
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
    # Should list each copied file on its own line with "copy" label
    [[ "$output" == *"  copy  .env"* ]]
    [[ "$output" == *"  copy  CLAUDE.local.md"* ]]
    # Should NOT use old single-line "Copied:" format
    [[ "$output" != *"Copied:"* ]]
}

@test "sw add: no output when nothing to copy" {
    # No .swcopy file
    run sw add feature-nothing

    [ "$status" -eq 0 ]
    # Should not mention copying
    [[ "$output" != *"copy"*"."* ]]
}

@test "sw add: no debug/trace lines in output" {
    echo ".env" > .gitignore
    echo "SECRET=abc" > .env
    git add .gitignore
    git commit -m "Add gitignore"
    echo ".env" > .swcopy

    run sw add feature-no-trace

    [ "$status" -eq 0 ]
    # Should not contain variable assignment traces
    [[ "$output" != *"f="* ]]
    [[ "$output" != *"gitignored_files="* ]]
    [[ "$output" != *"file="* ]]
}

@test "sw add: output contains only expected lines (copy)" {
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "SECRET=abc" > .env
    echo "local" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    cat > .swcopy <<'EOF'
.env
CLAUDE.local.md
EOF

    run sw add feature-strict-output

    [ "$status" -eq 0 ]
    # Every line must be a "Created:" line or a "  copy  "/"  link  " line
    while IFS= read -r line; do
        [[ "$line" == Created:* ]] || [[ "$line" == "  copy  "* ]] || [[ "$line" == "  link  "* ]] || {
            echo "Unexpected output line: '$line'"
            false
        }
    done <<< "$output"
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
# sw add: .swcopy nested patterns
# ============================================================================

@test "sw add: .swcopy nested glob pattern copies matching files" {
    # Create nested structure with gitignored files
    mkdir -p backend_app/db/store
    echo "data1" > backend_app/db/store/test.db
    echo "data2" > backend_app/db/store/cache.db
    echo "not a db" > backend_app/db/store/readme.txt
    cat > .gitignore <<'EOF'
backend_app/db/store/*.db
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    echo "backend_app/db/store/*.db" > .swcopy

    run sw add feature-nested-glob

    [ "$status" -eq 0 ]
    # Matching .db files should be copied
    [ -f "$WT_DIR/feature-nested-glob/backend_app/db/store/test.db" ]
    [ -f "$WT_DIR/feature-nested-glob/backend_app/db/store/cache.db" ]
    # Non-matching file should NOT be copied
    [ ! -f "$WT_DIR/feature-nested-glob/backend_app/db/store/readme.txt" ]
}

@test "sw add: .swcopy nested directory pattern copies entire directory" {
    mkdir -p backend_app/config
    echo "setting1" > backend_app/config/app.yml
    echo "setting2" > backend_app/config/db.yml
    cat > .gitignore <<'EOF'
backend_app/config/
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    echo "backend_app/config/" > .swcopy

    run sw add feature-nested-dir

    [ "$status" -eq 0 ]
    # Directory should be copied with correct nesting
    [ -d "$WT_DIR/feature-nested-dir/backend_app/config" ]
    [ -f "$WT_DIR/feature-nested-dir/backend_app/config/app.yml" ]
    [ -f "$WT_DIR/feature-nested-dir/backend_app/config/db.yml" ]
}

@test "sw add: .swcopy deeply nested path works" {
    mkdir -p a/b/c/d
    echo "deep" > a/b/c/d/file.txt
    cat > .gitignore <<'EOF'
a/b/c/d/file.txt
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    echo "a/b/c/d/file.txt" > .swcopy

    run sw add feature-deep-nest

    [ "$status" -eq 0 ]
    [ -f "$WT_DIR/feature-deep-nest/a/b/c/d/file.txt" ]
    [[ "$(cat "$WT_DIR/feature-deep-nest/a/b/c/d/file.txt")" == "deep" ]]
}

@test "sw add: .swcopy mixed top-level and nested patterns" {
    echo "SECRET=abc" > .env
    mkdir -p logs
    echo "log1" > logs/app.log
    mkdir -p backend_app/db/store
    echo "data" > backend_app/db/store/test.db
    cat > .gitignore <<'EOF'
.env
logs/
backend_app/db/store/*.db
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    cat > .swcopy <<'EOF'
.env
logs/
backend_app/db/store/*.db
EOF

    run sw add feature-mixed

    [ "$status" -eq 0 ]
    # Top-level file
    [ -f "$WT_DIR/feature-mixed/.env" ]
    # Top-level directory
    [ -d "$WT_DIR/feature-mixed/logs" ]
    [ -f "$WT_DIR/feature-mixed/logs/app.log" ]
    # Nested glob
    [ -f "$WT_DIR/feature-mixed/backend_app/db/store/test.db" ]
}

@test "sw add: .swcopy nested pattern with no matches is graceful" {
    cat > .gitignore <<'EOF'
*.db
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    # Pattern that matches nothing (no .db files exist)
    echo "nonexistent/path/*.db" > .swcopy

    run sw add feature-no-match

    [ "$status" -eq 0 ]
    # Worktree should still be created successfully
    [ -d "$WT_DIR/feature-no-match" ]
}

@test "sw add: .swcopy duplicate patterns only copy once" {
    echo "SECRET=abc" > .env
    cat > .gitignore <<'EOF'
.env
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    # .env matches both patterns
    cat > .swcopy <<'EOF'
.env
.e*
EOF

    run sw add feature-dedup

    [ "$status" -eq 0 ]
    [ -f "$WT_DIR/feature-dedup/.env" ]
    # Output should mention .env only once
    local count
    count=$(echo "$output" | grep -o '\.env' | wc -l)
    [ "$count" -eq 1 ]
}

@test "sw add: .swcopy nested dir where only contents are gitignored" {
    # Directory itself is NOT in gitignore, but files inside it are
    mkdir -p backend_app/db/store
    echo "data" > backend_app/db/store/test.db
    echo "tracked" > backend_app/db/store/schema.sql
    cat > .gitignore <<'EOF'
*.db
EOF
    git add .gitignore backend_app/db/store/schema.sql
    git commit -m "Add files"

    # Directory pattern — should still work because contents are gitignored
    echo "backend_app/db/store/" > .swcopy

    run sw add feature-contents-ignored

    [ "$status" -eq 0 ]
    # The gitignored .db file should be copied (not just the tracked schema.sql)
    [ -f "$WT_DIR/feature-contents-ignored/backend_app/db/store/test.db" ]
    [[ "$(cat "$WT_DIR/feature-contents-ignored/backend_app/db/store/test.db")" == "data" ]]
}

@test "sw add: .swcopy supports ** recursive glob pattern" {
    # ** requires bash 4+ (globstar) or zsh; skip on bash 3.x
    shopt -s globstar 2>/dev/null || skip "globstar not supported (bash 3.x)"

    mkdir -p app/db/store app/cache
    echo "data1" > app/db/store/test.db
    echo "data2" > app/cache/sessions.db
    echo "not a db" > app/db/store/readme.txt
    cat > .gitignore <<'EOF'
**/*.db
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    echo "**/*.db" > .swcopy

    run sw add feature-globstar

    [ "$status" -eq 0 ]
    # ** should match .db files at any depth
    [ -f "$WT_DIR/feature-globstar/app/db/store/test.db" ]
    [ -f "$WT_DIR/feature-globstar/app/cache/sessions.db" ]
    # Non-matching file should NOT be copied
    [ ! -f "$WT_DIR/feature-globstar/app/db/store/readme.txt" ]
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

    # .swcopy: copy .env; .swsymlink: symlink CLAUDE.local.md (independent)
    echo ".env" > .swcopy
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

    # .swcopy: non-CLAUDE files; .swsymlink: CLAUDE* pattern
    cat > .swcopy <<'EOF'
.env
.envrc
EOF
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

    echo ".env" > .swcopy
    echo "CLAUDE.local.md" > .swsymlink

    run sw add feature-symlink-output

    [ "$status" -eq 0 ]
    # Should show copied files with "copy" label
    [[ "$output" == *"  copy  .env"* ]]
    # Should show symlinked files with "link" label
    [[ "$output" == *"  link  CLAUDE.local.md"* ]]
}

@test "sw add: output contains only expected lines (copy + symlink)" {
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "SECRET=abc" > .env
    echo "local" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    echo ".env" > .swcopy
    echo "CLAUDE.local.md" > .swsymlink

    run sw add feature-strict-mixed

    [ "$status" -eq 0 ]
    # Must have at least one link line (proves symlinks worked)
    [[ "$output" == *"  link  "* ]]
    # Every line must be a "Created:" line or a "  copy  "/"  link  " line
    while IFS= read -r line; do
        [[ "$line" == Created:* ]] || [[ "$line" == "  copy  "* ]] || [[ "$line" == "  link  "* ]] || {
            echo "Unexpected output line: '$line'"
            false
        }
    done <<< "$output"
}

@test "sw add: .swsymlink works independently without .swcopy" {
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
    # CLAUDE.local.md should be symlinked (from .swsymlink alone)
    [ -L "$WT_DIR/feature-symlink-only/CLAUDE.local.md" ]
    # .env should NOT exist (not in either file)
    [ ! -e "$WT_DIR/feature-symlink-only/.env" ]
}

@test "sw add: errors when same item is in both .swcopy and .swsymlink" {
    echo "CLAUDE.local.md" >> .gitignore
    echo "local" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    echo "CLAUDE.local.md" > .swcopy
    echo "CLAUDE.local.md" > .swsymlink

    run sw add feature-overlap

    [ "$status" -eq 1 ]
    [[ "$output" == *"in both .swcopy and .swsymlink"* ]]
    # Worktree should still be created (git created it) but no files provisioned
}

@test "sw add: overlap detected across glob and literal patterns" {
    cat > .gitignore <<'EOF'
.env
CLAUDE.local.md
EOF
    echo "SECRET=abc" > .env
    echo "local" > CLAUDE.local.md
    git add .gitignore
    git commit -m "Add gitignore"

    # .swcopy glob matches CLAUDE.local.md, which is also in .swsymlink
    echo "CLAUDE*" > .swcopy
    echo "CLAUDE.local.md" > .swsymlink

    run sw add feature-overlap-glob

    [ "$status" -eq 1 ]
    [[ "$output" == *"in both .swcopy and .swsymlink"* ]]
}

# ============================================================================
# sw add: nested .swsymlink patterns
# ============================================================================

@test "sw add: .swsymlink nested directory pattern" {
    mkdir -p backend_app/config
    echo "setting1" > backend_app/config/app.yml
    cat > .gitignore <<'EOF'
backend_app/config/
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    echo "backend_app/config/" > .swsymlink

    run sw add feature-nested-symdir

    [ "$status" -eq 0 ]
    # Should be a symlink, not a copy
    [ -L "$WT_DIR/feature-nested-symdir/backend_app/config" ]
    # Files inside should be accessible
    [ -f "$WT_DIR/feature-nested-symdir/backend_app/config/app.yml" ]
}

@test "sw add: .swsymlink nested file pattern" {
    mkdir -p backend_app/config
    echo "local settings" > backend_app/config/local.yml
    echo "other" > backend_app/config/app.yml
    cat > .gitignore <<'EOF'
backend_app/config/local.yml
backend_app/config/app.yml
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    # Copy app.yml, symlink local.yml (independent, no overlap)
    echo "backend_app/config/app.yml" > .swcopy
    echo "backend_app/config/local.yml" > .swsymlink

    run sw add feature-nested-symfile

    [ "$status" -eq 0 ]
    # local.yml should be a symlink
    [ -L "$WT_DIR/feature-nested-symfile/backend_app/config/local.yml" ]
    # app.yml should be a regular copy
    [ -f "$WT_DIR/feature-nested-symfile/backend_app/config/app.yml" ]
    [ ! -L "$WT_DIR/feature-nested-symfile/backend_app/config/app.yml" ]
}

@test "sw add: nested cp destination preserves full path" {
    # Regression test: cp -R should create backend_app/config/, not just config/
    mkdir -p backend_app/config
    echo "setting" > backend_app/config/app.yml
    cat > .gitignore <<'EOF'
backend_app/config/
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    echo "backend_app/config/" > .swcopy

    run sw add feature-cp-path

    [ "$status" -eq 0 ]
    # Full nested path must be preserved
    [ -d "$WT_DIR/feature-cp-path/backend_app/config" ]
    [ -f "$WT_DIR/feature-cp-path/backend_app/config/app.yml" ]
    # Must NOT appear at top level
    [ ! -d "$WT_DIR/feature-cp-path/config" ] || [ -d "$WT_DIR/feature-cp-path/backend_app/config" ]
}

# ============================================================================
# sw open
# ============================================================================

@test "sw open: without fzf and no branch shows install message" {
    export VISUAL="echo"
    unset EDITOR

    local old_path="$PATH"
    PATH="/usr/bin:/bin"

    run sw open

    PATH="$old_path"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Interactive mode requires fzf"* ]]
    [[ "$output" == *"sw open [-e <editor>] <branch-name>"* ]]
}

@test "sw open: dot without fzf shows install message" {
    export VISUAL="echo"

    local old_path="$PATH"
    PATH="/usr/bin:/bin"

    run sw open .

    PATH="$old_path"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Interactive mode requires fzf"* ]]
}

@test "sw open: falls back to EDITOR when VISUAL not set" {
    unset VISUAL
    export EDITOR="echo"

    run sw open main

    [ "$status" -eq 0 ]
    [[ "$output" == "$TEST_DIR" ]]
}

@test "sw open: -e flag overrides VISUAL and EDITOR" {
    export VISUAL="wrong"
    export EDITOR="wrong"

    run sw open -e echo main

    [ "$status" -eq 0 ]
    [[ "$output" == "$TEST_DIR" ]]
}

@test "sw open: --editor flag works" {
    export VISUAL="wrong"

    run sw open --editor echo main

    [ "$status" -eq 0 ]
    [[ "$output" == "$TEST_DIR" ]]
}

@test "sw open: --editor=value syntax works" {
    export VISUAL="wrong"

    run sw open --editor=echo main

    [ "$status" -eq 0 ]
    [[ "$output" == "$TEST_DIR" ]]
}

@test "sw open: fails without editor configured" {
    unset VISUAL
    unset EDITOR

    run sw open main

    [ "$status" -eq 1 ]
    [[ "$output" == *"no editor configured"* ]]
    [[ "$output" == *"VISUAL"* ]]
    [[ "$output" == *"EDITOR"* ]]
}

@test "sw open: -e flag parsed before fzf fallback" {
    local old_path="$PATH"
    PATH="/usr/bin:/bin"

    run sw open -e echo

    PATH="$old_path"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Interactive mode requires fzf"* ]]
    [[ "$output" == *"sw open [-e <editor>] <branch-name>"* ]]
}

@test "sw open: opens specific worktree from base" {
    sw add feature-open
    export VISUAL="echo"

    run sw open feature-open

    [ "$status" -eq 0 ]
    [[ "$output" == "$WT_DIR/feature-open" ]]
}

@test "sw open: opens base branch from worktree" {
    sw add -s feature-open-base
    # Now in worktree
    export VISUAL="echo"

    run sw open main

    [ "$status" -eq 0 ]
    [[ "$output" == "$TEST_DIR" ]]
}

@test "sw open: opens another worktree from worktree" {
    sw add feature-one
    sw add -s feature-two
    # Now in feature-two
    export VISUAL="echo"

    run sw open feature-one

    [ "$status" -eq 0 ]
    [[ "$output" == "$WT_DIR/feature-one" ]]
}

@test "sw open: branch without worktree shows hint" {
    # Create a branch without a worktree
    git branch feature-no-wt

    export VISUAL="echo"
    run sw open feature-no-wt

    [ "$status" -eq 1 ]
    [[ "$output" == *"is a branch but has no worktree"* ]]
    [[ "$output" == *"sw add feature-no-wt && sw open feature-no-wt"* ]]
}

@test "sw open: nonexistent branch fails" {
    export VISUAL="echo"
    run sw open nonexistent-branch

    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "sw open: rejects unknown options" {
    export VISUAL="echo"
    run sw open --unknown

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]]
}
