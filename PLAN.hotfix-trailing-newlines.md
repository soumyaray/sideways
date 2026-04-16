# Fix: .swcopy/.swsymlink files without trailing newline silently ignored

> **IMPORTANT**: This plan must be kept up-to-date at all times. Assume context can be cleared at any time — this file is the single source of truth for the current state of this work. Update this plan before and after task and subtask implementations.

## Branch

`hotfix-trailing-newlines`

## Goal

Fix `_sw_read_patterns` so that `.swcopy` and `.swsymlink` files work correctly even without a trailing newline. Currently the last line is silently dropped because `read` returns false at EOF without newline.

## Strategy: Vertical Slice

This is a small bugfix — one function change plus tests.

1. **Test** — Add failing test for pattern file without trailing newline
2. **Fix** — Update `_sw_read_patterns` to handle missing trailing newline
3. **Verify** — Run full test suite plus zsh integration tests

## Current State

- [x] Plan created
- [x] Bug confirmed and root cause identified
- [x] Failing tests written (3 tests)
- [x] Fix applied
- [x] Full test suite passes (131 bats + 46 zsh integration)
- [ ] Manual verification

## Key Findings

- `_sw_read_patterns` (worktrees.sh:122-129) uses `while IFS= read -r line` to iterate lines from the config file
- In bash/zsh, `read` returns false (exit 1) when it reaches EOF without a trailing newline, causing the loop to exit before processing the final line — even though `$line` contains the data
- The fix is the standard idiom: `while IFS= read -r line || [[ -n "$line" ]]; do`
- This affects both `.swcopy` and `.swsymlink` since they share `_sw_read_patterns`

## Questions

(none)

## Scope

**In scope**: Fix `_sw_read_patterns` and add test coverage for missing trailing newlines.

**Out of scope**: Any other `.swcopy`/`.swsymlink` changes.

## Tasks

- [x] 1a FAILING test: `.swcopy` file without trailing newline should still copy the file
- [x] 1b FAILING test: `.swsymlink` file without trailing newline should still symlink the directory
- [x] 1c FAILING test: multiple lines with no trailing newline copies all entries
- [x] 2 Fix `_sw_read_patterns` with `|| [[ -n "$line" ]]` idiom
- [x] 3 Run full test suite (`bats -j 10 tests/worktrees.bats`) and zsh integration tests
- [ ] 4 Manual verification

## Completed

- 1a-1c: Three failing tests added (confirmed red), then passing after fix (green)
- 2: One-line fix in `_sw_read_patterns` (worktrees.sh:124)
- 3: All 131 bats tests + 46 zsh integration tests pass

---

Last updated: 2026-04-16
