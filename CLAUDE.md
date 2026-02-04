# Sideways - Git Worktree Shortcuts

## Shell Function: sw

**Source:** `worktrees.sh` (add to `~/.zshrc`)
**Status:** Complete

### Usage Summary

**From base directory only:**

| Command               | Description                                 |
| --------------------- | ------------------------------------------- |
| `sw add <branch>`     | Create worktree (new or existing branch)    |
| `sw add -s <branch>`  | Create worktree and cd into it              |
| `sw rm <branch>`      | Remove worktree (keep branch)               |
| `sw rm -d <branch>`   | Remove worktree + delete branch (if merged) |
| `sw rm -D <branch>`   | Remove worktree + force delete branch       |
| `sw prune`            | Remove stale worktree references            |

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

### Testing

39 tests using bats-core:

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

- `sw diff` - Show diff against main branch
- `sw push` - Push current branch (`git push -u origin HEAD`)
- `sw open` - Open current worktree in IDE/editor

### Other ideas

- Claude command for interactive workflows (issue #, branch naming conventions)
- Bulk cleanup command
