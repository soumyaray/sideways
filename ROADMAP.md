# Sideways Roadmap

Future features, refactoring opportunities, and ideas for the project.

## New Features

### Nice-to-Have Commands

| Command | Description | Complexity |
|---------|-------------|------------|
| `sw diff` | Show diff against main branch | Low |
| `sw push` | Push current branch (`git push -u origin HEAD`) | Low |
| `sw open` | Open current worktree in IDE/editor | Medium |
| `sw status` | Quick status across all worktrees | Medium |

### Other Feature Ideas

- **Claude command integration** - Interactive workflows (issue #, branch naming conventions)
- **Bulk cleanup command** - Remove multiple stale worktrees at once
- **Worktree templates** - Pre-configure files/settings for new worktrees
- **Shell completions** - Tab completion for zsh/bash

---

## Refactoring Opportunities

### Medium Priority

#### 1. Refactor `_sw_copy_gitignored()` Pattern Loading

**Current state:** 92-line function with duplicated pattern loading logic.

**Suggested change:**
- Extract `_sw_load_patterns()` helper function
- Reduce ~18 lines of duplicated logic

**Consideration:** Nameref (`local -n`) requires bash 4.3+ or zsh. May need alternative approach for broader compatibility (bash 3.x on older macOS).

#### 2. Simplify File Copy/Symlink Logic

**Current state:** Deeply nested conditionals for handling copy vs symlink vs directory.

**Suggested change:**
- Extract `_sw_copy_item()` helper function
- Flatten nested conditionals

#### 3. Extract List Formatting

**Current state:** `_sw_cmd_list()` is 50+ lines parsing git porcelain output.

**Suggested change:**
- Extract `_sw_parse_worktree_entry()` for parsing
- Extract `_sw_format_worktree_line()` for output formatting
- Improves testability of list logic

#### 4. Add Input Validation

**Current state:** Minimal validation of branch names and paths.

**Suggested change:**
- Add `_sw_validate_branch_name()` helper
- Check for invalid characters (spaces, special chars)
- Validate paths don't escape expected directories

#### 5. Standardize All Error Messages

**Current state:** Most errors use `_sw_error()`, but some still use raw `echo ... >&2`.

**Suggested change:**
- Audit all error outputs
- Route through `_sw_error()` consistently
- Consider adding error codes for scripting

### Low Priority

#### 6. Performance Optimization in Pattern Matching

**Current state:** Pattern matching in `_sw_copy_gitignored()` is O(n*m).

**Suggested change:** Pre-build pattern lookup (associative array in zsh).

**Note:** Unlikely to matter in practice - typical repos have few gitignored files and patterns.

#### 7. Enhanced Testing

**Current state:** 58 unit tests + 11 integration tests (good coverage).

**Suggested additions:**
- Integration tests for multi-command workflows (add → modify → done)
- Stress tests for many worktrees
- Edge case tests for unusual branch names

#### 8. Extract Router Logic

**Current state:** Main `sw()` computes paths then routes.

**Suggested change:**
- Extract `_sw_compute_paths()` to return repo_root, base_dir, worktrees_dir_*
- Makes router even cleaner (~20 lines)

---

## Decided Against

Decisions made to avoid re-litigating in the future.

| Idea | Reason Against |
|------|----------------|
| Split into multiple files | Shell lacks module system; single file is easier to source, distribute, and install via Homebrew |
| Use nameref for pattern loading | Requires bash 4.3+; older macOS ships with bash 3.x |
| Add verbose/quiet flags | YAGNI - current output level is appropriate |
| Support non-git-worktree workflows | Out of scope - tool is specifically for git worktrees |

---

## Completed

### v0.2.0 (refactor-god-function branch)

- [x] Extract command handlers from main `sw()` function (298 → 39 lines)
- [x] Eliminate 4 duplicate code patterns
- [x] Apply MVC-like architecture (Model/View/Controller layers)
- [x] Add `_sw_error()` for standardized error output
- [x] Add model helpers: `_sw_get_base_dir()`, `_sw_has_uncommitted_changes()`, `_sw_is_in_base()`, `_sw_guard_base_dir()`
