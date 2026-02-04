# Git Worktree Shortcuts - Planning Document

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

- Branch prefix: none (use branch name directly)
- Base branch: current HEAD
- Path convention: `../<project>-worktrees/<branch>`
- Auto-detect: `wt add` uses existing branch if present, creates new otherwise

### Testing

```bash
bats tests/worktrees.bats
```

Requires [bats-core](https://github.com/bats-core/bats-core): `brew install bats-core`

---

## Later Reference

### Claude Command (optional, for interactive workflows)

For complex scenarios where you want Claude to help pick the base branch, validate naming, or set up related items. Create in `~/.claude/commands/`.

### Use Case Summary

| Operation                 | Best Tool      | Why                                           |
| ------------------------- | -------------- | --------------------------------------------- |
| Quick list/prune          | Git alias      | Fast, no overhead                             |
| Create with conventions   | Shell function | Needs logic for naming/base branch            |
| Interactive creation      | Claude command | Can prompt for issue #, validate branch names |
| Bulk cleanup              | Shell function | Needs iteration logic                         |
