# Git Worktree Shortcuts

## Shell Function: wt

**Source:** `worktrees.sh` (add to `~/.zshrc`)
**Status:** Complete

### Usage Summary

| Command              | Description                              |
| -------------------- | ---------------------------------------- |
| `wt add <branch>`    | Create worktree (new or existing branch) |
| `wt add -s <branch>` | Create worktree and cd into it           |
| `wt cd <branch>`     | Switch to worktree                       |
| `wt cd`              | Interactive selection via fzf            |
| `wt rm <branch>`     | Remove worktree and delete branch        |
| `wt list` / `wt ls`  | List all worktrees                       |
| `wt prune`           | Remove stale worktree references         |
| `wt --help` / `wt`   | Show help                                |

### Design Decisions

- Path convention: `../<project>-worktrees/<branch>` (project name derived from git repo root)
- Auto-detect: `wt add` uses existing branch if present, creates new otherwise
- Base branch: current HEAD
- Branch naming: no prefixes enforced
- Error handling: git errors are propagated (wt add/rm fail properly)

### Testing

22 tests using bats-core:

```bash
brew install bats-core  # if needed
bats tests/worktrees.bats
```

Tests cover: add (new/existing branch), cd, rm, list, prune, help, and error cases.

### Key Files

- `worktrees.sh` - the shell function
- `tests/worktrees.bats` - test suite
- `README.md` - user documentation

---

## Future Ideas

- Claude command for interactive workflows (issue #, branch naming conventions)
- Bulk cleanup command
