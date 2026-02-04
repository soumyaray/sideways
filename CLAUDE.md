# Sideways - Git Worktree Shortcuts

## Shell Function: sw

**Source:** `worktrees.sh` (add to `~/.zshrc`)
**Status:** Complete

### Usage Summary

**From base directory only:**

| Command               | Description                                        |
| --------------------- | -------------------------------------------------- |
| `sw add <branch>`     | Create worktree, copy gitignored files             |
| `sw add -s <branch>`  | Create worktree and cd into it                     |
| `sw rm <branch>`      | Remove worktree (keep branch)                      |
| `sw rm -d <branch>`   | Remove worktree + delete branch (if merged)        |
| `sw rm -D <branch>`   | Remove worktree + force delete branch              |
| `sw prune`            | Remove stale worktree references                   |

**From worktree subdirectory only:**

| Command              | Description                              |
| -------------------- | ---------------------------------------- |
| `sw base`            | Jump back to base                        |
| `sw rebase <branch>` | Fetch and rebase onto origin/\<branch\>  |
| `sw done`            | Remove worktree (keep branch), cd to base|

**Anywhere:**

| Command              | Description                              |
| -------------------- | ---------------------------------------- |
| `sw cd <branch>`     | Switch to worktree                       |
| `sw cd`              | Interactive selection via fzf            |
| `sw list` / `sw ls`  | List worktrees (* = current, [modified]) |
| `sw info`            | Show current branch, path, location      |
| `sw --help` / `sw`   | Show help                                |

### Design Decisions

- Path convention: `../<project>-worktrees/<branch>` (project name derived from base's git repo root)
- Auto-detect: `sw add` uses existing branch if present, creates new otherwise
- New branches: start from current HEAD
- Branch naming: no prefixes enforced
- Error handling: git errors are propagated (sw add/rm fail properly)
- Terminology: "base" = main working directory, "worktree" = created via `sw add`
- Guards: `sw add` and `sw rm` blocked from worktree subdirectories (must run from base)
- Safety: `sw rm` and `sw done` refuse to remove worktrees with uncommitted changes

### Testing

**Unit tests** (41 tests using bats-core):

```bash
brew install bats-core  # if needed
bats tests/worktrees.bats
```

Tests cover: add, cd, rm, list, prune, base, info, rebase, done, help, and error cases.

**Zsh integration tests** (catches zsh-specific issues like `$path` shadowing):

```bash
zsh tests/zsh-integration.zsh
```

These tests run in actual zsh and catch issues that bash-based bats tests miss.

### Key Files

- `worktrees.sh` - the shell function
- `tests/worktrees.bats` - test suite
- `README.md` - user documentation
- `scripts/release.sh` - release automation script
- `.swcopy` - (user-created) patterns for gitignored files to copy
- `.swsymlink` - (user-created) patterns to symlink instead of copy

---

## Release Script

**Source:** `scripts/release.sh`

Automates the full release process: tagging, pushing, and updating the Homebrew formula.

### Usage

```bash
./scripts/release.sh [--dry-run] <version>
./scripts/release.sh --init [version]

# Examples:
./scripts/release.sh --init              # First release (v0.1.0)
./scripts/release.sh 0.2.0               # Release v0.2.0
./scripts/release.sh --dry-run 0.2.0     # Preview without making changes
```

- `--init` creates the first release (defaults to 0.1.0), warns if tags already exist
- `--dry-run` shows what would happen without making changes

### What it does

1. Validates version format (X.Y.Z) and checks tag doesn't exist
2. Runs pre-flight checks (clean working dir, on main branch, homebrew-sideways repo exists)
3. Creates and pushes annotated git tag
4. Fetches tarball from GitHub and calculates SHA256
5. Updates `../homebrew-sideways/Formula/sideways.rb` with new version and SHA
6. Commits and pushes the formula update

### Requirements

- Must run from repo root
- Working directory must be clean
- Must be on main branch
- `../homebrew-sideways` repo must exist with `Formula/sideways.rb`

---

## Future Ideas

### Nice-to-have commands

- `sw diff` - Show diff against main branch
- `sw push` - Push current branch (`git push -u origin HEAD`)
- `sw open` - Open current worktree in IDE/editor

### Other ideas

- Claude command for interactive workflows (issue #, branch naming conventions)
- Bulk cleanup command
