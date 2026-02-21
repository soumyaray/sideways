# Sideways - Git Worktree Helper

A shell function (`sw`) for managing git worktrees. See `sw --help` or `README.md` for usage.

## Architecture

`worktrees.sh` is organized in three layers:

- **Model** (`_sw_*` functions) - core logic: path resolution, state queries, guards
- **View** (`_sw_error`, output in commands) - user-facing output
- **Controller** (`_sw_cmd_*` functions) - command handlers
- **Router** (`sw()` function) - parses args, computes paths, dispatches to controllers

`SW_VERSION` at the top of the file is auto-updated by `scripts/release.sh` — don't edit manually.

### Design Decisions

- Path convention: `../<project>-worktrees/<branch>` (project name derived from base's git repo root)
- Auto-detect: `sw add` uses existing branch if present, creates new otherwise
- New branches: start from current HEAD
- Branch naming: no prefixes enforced
- Error handling: git errors are propagated (sw add/rm fail properly)
- Terminology: "base" = main working directory, "worktree" = created via `sw add`
- Guards: `sw add` and `sw rm` blocked from worktree subdirectories (must run from base)
- Safety: `sw rm` and `sw done` refuse to remove worktrees with uncommitted changes

---

## Testing

**Unit tests** (109 tests using bats-core):

```bash
brew install bats-core parallel  # if needed
bats -j 10 tests/worktrees.bats
```

Tests cover: add, cd, rm, list, prune, base, info, rebase, done, open, help, and error cases.

**Zsh integration tests** (catches zsh-specific issues like `$path` shadowing):

```bash
zsh tests/zsh-integration.zsh
```

These tests run in actual zsh and catch issues that bash-based bats tests miss.

---

## Key Files

- `worktrees.sh` - the shell function
- `tests/worktrees.bats` - test suite
- `README.md` - user documentation
- `scripts/release.sh` - release automation script
- `.swcopy` - (user-created) patterns for gitignored files to copy
- `.swsymlink` - (user-created) patterns to symlink instead of copy

---

## Releasing

### Pre-release Checklist

1. All changes committed and pushed to `main`
2. Tests pass: `bats -j 10 tests/worktrees.bats` and `zsh tests/zsh-integration.zsh`
3. `../homebrew-sideways` repo exists and is on `main`

### Release Process

```bash
# Preview first
./scripts/release.sh --dry-run 0.4.0

# Then release
./scripts/release.sh 0.4.0
```

The script handles everything:

1. Updates `SW_VERSION` in `worktrees.sh`
2. Commits the version bump
3. Creates and pushes git tag `v0.4.0`
4. Calculates SHA256 from GitHub tarball
5. Updates `../homebrew-sideways/Formula/sideways.rb`
6. Commits and pushes the formula

### Post-release Verification

```bash
brew update && brew upgrade sideways
sw --version  # should show new version
```

---

## Future Ideas

See [ROADMAP.md](ROADMAP.md) for planned features and refactoring opportunities.

---

## Caveats

- **Don't use `sw` commands in Claude sessions** — editors won't follow directory changes from `sw cd`, `sw add -s`, etc. Use git commands directly.
- **Zsh `local` in loops prints to stdout** — In zsh, `local var` (bare declaration without `=value`) inside a loop prints the variable's value to stdout on iterations after the first, because zsh's `local` is an alias for `typeset` which outputs existing variable definitions. This causes spurious output (e.g., blank lines in fzf). **Rules:** (1) never use bare `local var` inside a loop — use `local var=""` or declare before the loop, (2) prefer declaring all loop variables before the loop body, (3) `local var=value` (with assignment) is safe. This issue only affects zsh; bash's `local` does not print.
- **Zsh reserved variable names** — In zsh, `$path` is a special array tied to `$PATH`. Using `local path=...` in a function will shadow it and break command resolution (`command not found`). Other zsh-reserved names to avoid: `$path`, `$status`, `$prompt`, `$signals`, `$commands`, `$functions`, `$history`, `$dirstack`, `$pipestatus`. Always use prefixed names like `wt_path` instead. This bug has occurred twice — always add a zsh integration test when introducing new local variables.
