# Sideways - Git Worktree Helper

A shell function (`sw`) for managing git [worktrees](#background) with sensible defaults.

## Overview

### Quick Example

```bash
# You're in ~/code/myapp (base, on main branch) and need to fix an issue

sw add -s fix-issue        # Creates worktree and switches to it
# Now you're in ~/code/myapp-worktrees/fix-issue (on fix-issue branch)

# Work on the fix, then go back
sw base                    # Back to ~/code/myapp (base, on main branch)

sw list                    # See all worktrees
#   main                  base       a1b2c3d
# * fix-issue             worktree   e4f5g6h  [modified]
```

Resulting directory structure:

```text
~/code/
  myapp/                    # base (your main checkout)
  myapp-worktrees/
    fix-issue/              # worktree (on fix-issue branch)
```

### Why this over [other worktree tools](https://github.com/topics/git-worktree)?

- **Zero dependencies** — pure shell (~230 lines), optional fzf for interactive selection
- **Workflow commands** — `sw rebase <branch>` (sync with any branch), `sw done` (cleanup and return to base)
- **Editor integration** — `sw open` launches your editor directly in a worktree
- **Gitignored file handling** — `.swcopy`/`.swsymlink` to copy or symlink env files and local configs to new worktrees
- **Safety guards** — blocks `rm`/`done` if uncommitted changes exist, blocks `add`/`rm` from wrong directory

## Installation

### Quick install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/soumyaray/sideways/main/install.sh | bash
```

This clones to `~/.sideways` and adds it to your shell config. Restart your shell or run `source ~/.zshrc`.

### Homebrew (macOS)

```bash
brew tap soumyaray/sideways
brew install sideways
```

Then add this line to your `~/.zshrc` (or `~/.bashrc`):

```bash
source "/opt/homebrew/opt/sideways/libexec/worktrees.sh"
```

Restart your shell or run `source ~/.zshrc`.

### Manual install

Clone and source in your shell configuration:

```bash
git clone https://github.com/soumyaray/sideways.git ~/.sideways

# Add to ~/.zshrc or ~/.bashrc
source ~/.sideways/worktrees.sh
```

## Usage

```text
sw <command> [options]
```

**From base directory only:**

| Command               | Description                                        |
| --------------------- | -------------------------------------------------- |
| `sw add <branch>`     | Create worktree, copy gitignored files (see below) |
| `sw add -s <branch>`  | Create worktree and cd into it                     |
| `sw add -o <branch>`  | Create worktree and open in editor                 |
|                       |                                             |
| `sw rm <branch>`      | Remove worktree (keep branch)               |
| `sw rm -d <branch>`   | Remove worktree + delete branch (if merged) |
| `sw rm -D <branch>`   | Remove worktree + force delete branch       |
|                       |                                             |
| `sw prune`            | Remove stale worktree references            |

**From worktree subdirectory only:**

| Command              | Description                               |
| -------------------- | ----------------------------------------- |
| `sw base`            | Jump back to base                         |
|                      |                                           |
| `sw rebase <branch>` | Fetch and rebase onto origin/\<branch\>   |
| `sw done`            | Remove worktree (keep branch), cd to base |

**Anywhere:**

| Command                        | Description                              |
| ------------------------------ | ---------------------------------------- |
| `sw cd <branch>`               | Switch to worktree                       |
| `sw cd`                        | Interactive selection via fzf            |
|                                |                                          |
| `sw list` / `sw ls`            | List worktrees (* = current, [modified]) |
| `sw info`                      | Show current branch, path, location      |
| `sw open [-e <editor>] [branch]` | Open worktree in editor                |
| `sw --help`                    | Show help                                |
| `sw --version`                 | Show version                             |

## Examples

```bash
# From base: create and manage worktrees
sw add -s feature-login    # Create worktree and switch to it
sw cd feature-login        # Switch to existing worktree
sw cd                      # Interactive picker (requires fzf)
sw rm feature-login        # Remove worktree (keep branch)
sw rm -D feature-login     # Remove worktree and force delete branch

# From worktree: navigate and sync
sw info                    # See where you are
sw rebase main             # Fetch and rebase onto origin/main
sw base                    # Jump back to base
sw done                    # Remove worktree (keep branch), cd to base
```

## Opinionated Defaults

This tool makes deliberate choices to keep worktree management simple:

| Decision | Convention | Rationale |
| -------- | ---------- | --------- |
| **Worktree location** | `../<project>-worktrees/<branch>` | Keeps worktrees alongside base, namespaced per project to avoid collisions |
| **Branch handling** | Auto-detect | `sw add` uses an existing branch if present, creates a new one otherwise |
| **Branch base** | Current HEAD | New branches start from wherever you are |
| **Branch naming** | Direct | No prefixes or conventions enforced—use whatever branch name you want |

Example with multiple projects:

```text
~/code/
  myapp/                       # base
  myapp-worktrees/
    feature-login/             # worktree (sw add feature-login)
    bugfix-header/             # worktree (sw add bugfix-header)
  other-project/               # base
  other-project-worktrees/
    experiment/                # worktree
```

## Copying Gitignored Files

When you create a worktree with `sw add`, gitignored files can be copied from base to the new worktree. By default, nothing is copied — you opt-in via `.swcopy`.

### Specifying files to copy with `.swcopy`

Create a `.swcopy` file in your repo root to list gitignored files that should be copied:

```text
# .swcopy - gitignored files to copy to new worktrees
.env
CLAUDE.local.md
logs/
backend_app/db/store/*.db
**/*.sqlite
```

```bash
sw add feature-auth
# Created: ../myapp-worktrees/feature-auth (new branch feature-auth)
# Copied: .env CLAUDE.local.md logs/ backend_app/db/store/cache.db
```

If no `.swcopy` exists, no gitignored files are copied.

### Symlinking files with `.swsymlink`

For files you want shared across all worktrees (changes reflected everywhere), create a `.swsymlink` file:

```text
# .swsymlink - files to symlink instead of copy
CLAUDE.local.md
```

Files in both `.swcopy` and `.swsymlink` are symlinked to the base copy; others in `.swcopy` are copied. This is useful for config files that should stay in sync, while `.env` files (with port numbers, etc.) remain independent copies.

### Config file format

Both `.swcopy` and `.swsymlink` use the same format:

- One pattern per line
- Comments start with `#`
- Glob patterns supported (`*.log`, `CLAUDE*`, `backend_app/db/*.db`)
- `**` for recursive matching (`**/*.sqlite` matches at any depth; requires bash 4+ or zsh)
- Directories should have trailing `/` (`logs/`, `backend_app/config/`)
- Files must be in `.swcopy` to be copied or symlinked

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

**This script:** Provides a simple `sw` command that creates worktrees in a predictable location next to your base.

## Releasing

For maintainers, releases are automated via `scripts/release.sh`:

```bash
./scripts/release.sh --init          # First release (v0.1.0)
./scripts/release.sh 0.2.0           # Release v0.2.0
./scripts/release.sh --dry-run 0.2.0 # Preview first
```

This tags the repo, pushes to GitHub, and updates the [Homebrew tap](https://github.com/soumyaray/homebrew-sideways).

## License

MIT
