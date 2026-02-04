# wt - Git Worktree Helper

A shell function for managing git worktrees with sensible defaults.

## Opinionated Defaults

This tool makes deliberate choices to keep worktree management simple:

| Decision | Convention | Rationale |
| -------- | ---------- | --------- |
| **Worktree location** | `../<project>-worktrees/<branch>` | Keeps worktrees alongside the main repo, namespaced per project to avoid collisions |
| **Branch handling** | Auto-detect | `wt add` uses an existing branch if present, creates a new one otherwise |
| **Branch base** | Current HEAD | New branches start from wherever you are |
| **Branch naming** | Direct | No prefixes or conventions enforced—use whatever branch name you want |

Example directory structure:

```text
~/code/
  my-app/                      # main repo
  my-app-worktrees/
    feature-login/             # wt add feature-login
    bugfix-header/             # wt add bugfix-header
  other-project/
  other-project-worktrees/
    experiment/
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

## License

MIT
