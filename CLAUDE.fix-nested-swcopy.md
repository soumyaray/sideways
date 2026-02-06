# Fix Nested Path Patterns in .swcopy and .swsymlink

## Context

The `sw add` command copies gitignored files from the base directory to new worktrees based on patterns in `.swcopy` and `.swsymlink` files. However, there's a bug where **nested path patterns don't work**.

**Current behavior:**
- Pattern `.env` ✅ works (top-level file)
- Pattern `logs/` ✅ works (top-level directory)
- Pattern `backend_app/db/store/*.db` ❌ fails (nested pattern)

**Root cause:** In `_sw_copy_gitignored()` at line 76 of `worktrees.sh`:
```bash
git ls-files --others --ignored --exclude-standard | cut -d'/' -f1 | sort -u
```

The `cut -d'/' -f1` extracts only the first path component, so nested files are reduced to their top-level parent directory. When matching patterns, `backend_app` doesn't match `backend_app/db/store/*.db`, so nothing gets copied.

**User's requirement:** Intelligently find and copy/symlink only the exact files that match patterns in `.swcopy` and `.swsymlink`, without copying entire parent directories.

## Implementation Plan

### 1. Refactor `_sw_copy_gitignored()` Function

**File:** `worktrees.sh`, lines 58-151

**Changes:**

#### A. Get ALL gitignored files (not just top-level)
Replace line 76:
```bash
# OLD (top-level only):
git ls-files --others --ignored --exclude-standard | cut -d'/' -f1 | sort -u

# NEW (all files with full paths):
git ls-files --others --ignored --exclude-standard
```

#### B. Change matching algorithm from "iterate items" to "iterate patterns"

**Current approach (broken for nested paths):**
1. Get top-level gitignored items
2. For each item, check if it matches any pattern
3. If matches, copy/symlink that item

**New approach (works for all paths):**
1. Get ALL gitignored files
2. For each pattern in `.swcopy`, find all files that match it
3. For matching files, check if they should be symlinked (via `.swsymlink`)
4. Copy or symlink each file, creating parent directories as needed

#### C. Handle both file and directory patterns

- **File patterns** (`backend_app/db/store/*.db`): Match individual files, copy each one
- **Directory patterns** (`logs/`, `backend_app/`): Match all files under that directory
- **Glob patterns** (`*.log`, `backend_app/**/*.db`): Use shell pattern matching

#### D. Preserve existing behavior for top-level patterns

Ensure patterns like `.env`, `logs/`, `*.log` still work exactly as before.

### 2. Pattern Matching Logic

Use shell's pattern matching with `[[ path == pattern ]]` or directory prefix matching:

```bash
for pattern in "${swcopy_patterns[@]}"; do
    # Handle directory patterns (with trailing slash)
    if [[ "$pattern" == */ ]]; then
        # Match all files under this directory
        if [[ "$file" == "${pattern%/}/"* ]]; then
            should_copy=true
            break
        fi
    else
        # Match file pattern (supports globs)
        if [[ "$file" == $pattern ]]; then
            should_copy=true
            break
        fi
    fi
done
```

### 3. Parent Directory Creation

The code already handles this at lines 134-136:
```bash
local parent_dir=$(dirname "$wt_path/$item")
[[ ! -d "$parent_dir" ]] && mkdir -p "$parent_dir"
```

Ensure this works correctly for nested paths by using the full file path, not just the top-level item.

### 4. Output Formatting

Update the "Copied:" and "Symlinked:" output to handle nested paths gracefully:
- Show relative paths from worktree root
- Group by type (files vs. directories) if helpful
- Keep output concise even with many nested files

### 5. Add Comprehensive Tests

**File:** `tests/worktrees.bats`

Add test cases for:

1. **Nested directory patterns** (`backend_app/db/store/`)
   - Verify all files under the nested directory are copied
   - Verify directory structure is preserved

2. **Nested glob patterns** (`backend_app/db/store/*.db`)
   - Verify only matching files are copied
   - Verify non-matching files in same directory are NOT copied

3. **Multi-level nesting** (`a/b/c/d/file.txt`)
   - Verify deeply nested paths work

4. **Mixed patterns** (`.env`, `logs/`, `backend_app/db/store/*.db`)
   - Verify top-level and nested patterns work together

5. **Nested symlinks** (`backend_app/config/` in `.swsymlink`)
   - Verify symlinks work for nested paths

6. **Nested patterns with no matches**
   - Verify graceful handling when pattern doesn't match any files

### 6. Critical Files

**To modify:**
- `worktrees.sh`: `_sw_copy_gitignored()` function (lines 58-151)

**To extend:**
- `tests/worktrees.bats`: Add nested pattern test cases (after line 829)

**To reference for patterns:**
- Existing tests at lines 596-829 show test structure
- Lines 104-126 show current pattern matching logic

### 7. Verification Steps

After implementation:

1. **Run existing tests** to ensure no regressions:
   ```bash
   bats tests/worktrees.bats
   ```

2. **Run new nested pattern tests**:
   ```bash
   bats tests/worktrees.bats -f "nested"
   ```

3. **Manual testing**:
   ```bash
   # Create test structure
   mkdir -p backend_app/db/store
   echo "data" > backend_app/db/store/test.db
   echo "cache" > backend_app/db/store/cache.db
   echo "backend_app/db/store/" > .gitignore
   echo "backend_app/db/store/*.db" > .swcopy

   # Test
   sw add test-nested
   ls -la ../sideways-worktrees/test-nested/backend_app/db/store/
   # Should see test.db and cache.db
   ```

4. **Run zsh integration tests**:
   ```bash
   zsh tests/zsh-integration.zsh
   ```

## Performance Considerations

- **Before:** Processed only unique top-level items (very fast, typically <10 items)
- **After:** Processes all gitignored files (potentially slower with 100s of files)

**Mitigation:**
- Shell pattern matching is fast even with many files
- Most projects have <100 gitignored files
- If performance becomes an issue, can optimize later with early-exit conditions

## Edge Cases to Handle

1. **Empty patterns** - skip blank lines (already handled)
2. **Comment lines** - skip `#` lines (already handled)
3. **Trailing slashes** - normalize directory patterns
4. **Glob special characters** - ensure they work in shell pattern matching
5. **Symlinks pointing to non-existent targets** - handle gracefully
6. **Files deleted after git ls-files ran** - check existence before copying

## Summary

This fix will:
- ✅ Make nested patterns like `backend_app/db/store/*.db` work
- ✅ Preserve existing behavior for top-level patterns
- ✅ Intelligently copy only matching files (not entire parent directories)
- ✅ Support glob patterns at any nesting level
- ✅ Work with both `.swcopy` and `.swsymlink`
- ✅ Maintain backward compatibility with existing `.swcopy` files
