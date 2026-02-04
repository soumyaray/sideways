# wt - Git Worktree Helper

A shell function for managing git [worktrees](#background) with sensible defaults.

## Quick Example

```bash
# You're in ~/code/myapp (base, on main branch) and need to fix an issue

wt add -s fix-issue        # Creates worktree and switches to it
# Now you're in ~/code/myapp-worktrees/fix-issue (on fix-issue branch)

# Work on the fix, then go back
wt base                    # Back to ~/code/myapp (base, on main branch)

wt list                    # See all worktrees
```

Resulting directory structure:

```text
~/code/
  myapp/                    # base (your main checkout)
  myapp-worktrees/
    pr-review/              # worktree (on pr-review branch)
```

**Why this over [other worktree tools](https://github.com/topics/git-worktree)?**

- **Zero dependencies** — pure shell (~230 lines), optional fzf for interactive selection
- **Workflow commands** — `wt rebase <branch>` (sync with any branch), `wt done` (cleanup and return to base)
- **Safety guards** — blocks `add`/`rm` from worktree subdirectories to prevent mistakes

## Installation

Source the script in your shell configuration:

```bash
# Add to ~/.zshrc or ~/.bashrc
source /path/to/worktrees.sh
```

## Usage

```text
wt <command> [options]
```

**From base directory only:**

| Command               | Description                                 |
| --------------------- | ------------------------------------------- |
| `wt add <branch>`     | Create worktree (new or existing branch)    |
| `wt add -s <branch>`  | Create worktree and cd into it              |
|                       |                                             |
| `wt rm <branch>`      | Remove worktree (keep branch)               |
| `wt rm -d <branch>`   | Remove worktree + delete branch (if merged) |
| `wt rm -D <branch>`   | Remove worktree + force delete branch       |
|                       |                                             |
| `wt prune`            | Remove stale worktree references            |

**From worktree subdirectory only:**

| Command              | Description                               |
| -------------------- | ----------------------------------------- |
| `wt base`            | Jump back to base                         |
|                      |                                           |
| `wt rebase <branch>` | Fetch and rebase onto origin/\<branch\>   |
| `wt done`            | Remove worktree (keep branch), cd to base |

**Anywhere:**

| Command              | Description                              |
| -------------------- | ---------------------------------------- |
| `wt cd <branch>`     | Switch to worktree                       |
| `wt cd`              | Interactive selection via fzf            |
|                      |                                          |
| `wt list` / `wt ls`  | List all worktrees                       |
| `wt info`            | Show current branch, path, location      |
| `wt --help`          | Show help                                |

## Examples

```bash
# From base: create and manage worktrees
wt add -s feature-login    # Create worktree and switch to it
wt cd feature-login        # Switch to existing worktree
wt cd                      # Interactive picker (requires fzf)
wt rm feature-login        # Remove worktree (keep branch)
wt rm -D feature-login     # Remove worktree and force delete branch

# From worktree: navigate and sync
wt info                    # See where you are
wt rebase main             # Fetch and rebase onto origin/main
wt base                    # Jump back to base
wt done                    # Remove worktree (keep branch), cd to base
```

## Opinionated Defaults

This tool makes deliberate choices to keep worktree management simple:

| Decision | Convention | Rationale |
| -------- | ---------- | --------- |
| **Worktree location** | `../<project>-worktrees/<branch>` | Keeps worktrees alongside base, namespaced per project to avoid collisions |
| **Branch handling** | Auto-detect | `wt add` uses an existing branch if present, creates a new one otherwise |
| **Branch base** | Current HEAD | New branches start from wherever you are |
| **Branch naming** | Direct | No prefixes or conventions enforced—use whatever branch name you want |

Example with multiple projects:

```text
~/code/
  myapp/                       # base
  myapp-worktrees/
    feature-login/             # worktree (wt add feature-login)
    bugfix-header/             # worktree (wt add bugfix-header)
  other-project/               # base
  other-project-worktrees/
    experiment/                # worktree
```

## Dependencies

- Git
- fzf (optional, for interactive worktree selection)

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core):

```bash
# Install bats
brew install bats-core  # macOS

# Run tests
bats tests/worktrees.bats
```

## Background

Git worktrees let you have multiple branches checked out simultaneously in separate directories. Instead of stashing or committing work-in-progress to switch branches, you just `cd` to another directory.

**The problem:** Git's built-in worktree commands are verbose and don't enforce any directory structure, making it easy to scatter worktrees everywhere.

**This script:** Provides a simple `wt` command that creates worktrees in a predictable location next to your base.

## License

MIT
