# wt - Git Worktree Helper

A shell function for managing git worktrees with sensible defaults.

## Installation

Source the script in your shell configuration:

```bash
# Add to ~/.zshrc or ~/.bashrc
source /path/to/worktrees.sh
```

## Usage

```
wt <command> [options]
```

| Command              | Description                            |
| -------------------- | -------------------------------------- |
| `wt add <branch>`    | Create worktree at `../worktrees/<branch>` |
| `wt add -s <branch>` | Create worktree and cd into it         |
| `wt cd <branch>`     | Switch to worktree                     |
| `wt cd`              | Interactive selection via fzf          |
| `wt rm <branch>`     | Remove worktree and delete branch      |
| `wt list` / `wt ls`  | List all worktrees                     |
| `wt prune`           | Remove stale worktree references       |
| `wt --help`          | Show help                              |

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

## License

MIT
