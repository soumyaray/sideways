# wt - Git Worktree Helper

A shell function for managing git [worktrees](#background) with sensible defaults.

## Quick Example

```bash
# You're in ~/code/myapp on the main branch, debugging an issue
# Suddenly you need to review a PR on a different branch

wt add -s pr-review        # Creates worktree and switches to it
# Now you're in ~/code/myapp-worktrees/pr-review

# Review the PR, then go back to your debugging
wt cd main                 # Back to ~/code/myapp
# Your debug session is exactly where you left it
```

Resulting directory structure:

```text
~/code/
  myapp/                    # Your main checkout (on main branch)
  myapp-worktrees/
    pr-review/               # The new worktree (on pr-review branch)
```

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

| Command              | Description                              |
| -------------------- | ---------------------------------------- |
| `wt add <branch>`    | Create worktree (new or existing branch) |
| `wt add -s <branch>` | Create worktree and cd into it           |
| `wt cd <branch>`     | Switch to worktree                       |
| `wt cd`              | Interactive selection via fzf            |
| `wt rm <branch>`     | Remove worktree and delete branch        |
| `wt list` / `wt ls`  | List all worktrees                       |
| `wt prune`           | Remove stale worktree references         |
| `wt --help`          | Show help                                |

## Examples

```bash
# Start working on a new feature
wt add -s feature-login

# Switch between worktrees
wt cd main
wt cd feature-login

# Interactive picker (requires fzf)
wt cd

# Clean up when done
wt rm feature-login
```

## Opinionated Defaults

This tool makes deliberate choices to keep worktree management simple:

| Decision | Convention | Rationale |
| -------- | ---------- | --------- |
| **Worktree location** | `../<project>-worktrees/<branch>` | Keeps worktrees alongside the main repo, namespaced per project to avoid collisions |
| **Branch handling** | Auto-detect | `wt add` uses an existing branch if present, creates a new one otherwise |
| **Branch base** | Current HEAD | New branches start from wherever you are |
| **Branch naming** | Direct | No prefixes or conventions enforced—use whatever branch name you want |

Example with multiple projects:

```text
~/code/
  myapp/                      # main repo
  myapp-worktrees/
    feature-login/             # wt add feature-login
    bugfix-header/             # wt add bugfix-header
  other-project/
  other-project-worktrees/
    experiment/
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

Git worktrees let you have multiple branches checked out simultaneously in separate directories. Instead of stashing or committing work-in-progress to switch branches, you just `cd` to another folder.

**The problem:** Git's built-in worktree commands are verbose and don't enforce any directory structure, making it easy to scatter worktrees everywhere.

**This script:** Provides a simple `wt` command that creates worktrees in a predictable location next to your repo.

## License

MIT
