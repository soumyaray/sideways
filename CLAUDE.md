# Git Worktree Shortcuts

## Shell Function: wt

**Source:** `worktrees.sh` (add to `~/.zshrc`)
**Status:** Complete

### Usage Summary

**From base directory only:**

| Command               | Description                                 |
| --------------------- | ------------------------------------------- |
| `wt add <branch>`     | Create worktree (new or existing branch)    |
| `wt add -s <branch>`  | Create worktree and cd into it              |
| `wt rm <branch>`      | Remove worktree (keep branch)               |
| `wt rm -d <branch>`   | Remove worktree + delete branch (if merged) |
| `wt rm -D <branch>`   | Remove worktree + force delete branch       |
| `wt prune`            | Remove stale worktree references            |

**From worktree subdirectory only:**

| Command              | Description                              |
| -------------------- | ---------------------------------------- |
| `wt base`            | Jump back to base                        |
| `wt rebase <branch>` | Fetch and rebase onto origin/\<branch\>  |
| `wt done`            | Remove worktree (keep branch), cd to base|

**Anywhere:**

| Command              | Description                              |
| -------------------- | ---------------------------------------- |
| `wt cd <branch>`     | Switch to worktree                       |
| `wt cd`              | Interactive selection via fzf            |
| `wt list` / `wt ls`  | List all worktrees                       |
| `wt info`            | Show current branch, path, location      |
| `wt --help` / `wt`   | Show help                                |

### Design Decisions

- Path convention: `../<project>-worktrees/<branch>` (project name derived from base's git repo root)
- Auto-detect: `wt add` uses existing branch if present, creates new otherwise
- New branches: start from current HEAD
- Branch naming: no prefixes enforced
- Error handling: git errors are propagated (wt add/rm fail properly)
- Terminology: "base" = main working directory, "worktree" = created via `wt add`
- Guards: `wt add` and `wt rm` blocked from worktree subdirectories (must run from base)

### Testing

36 tests using bats-core:

```bash
brew install bats-core  # if needed
bats tests/worktrees.bats
```

Tests cover: add, cd, rm, list, prune, base, info, rebase, done, help, and error cases.

### Key Files

- `worktrees.sh` - the shell function
- `tests/worktrees.bats` - test suite
- `README.md` - user documentation

---

## Future Ideas

### Nice-to-have commands

- `wt diff` - Show diff against main branch
- `wt push` - Push current branch (`git push -u origin HEAD`)
- `wt open` - Open current worktree in IDE/editor

### Other ideas

- Claude command for interactive workflows (issue #, branch naming conventions)
- Bulk cleanup command
