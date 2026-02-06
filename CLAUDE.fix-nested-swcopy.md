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

#### A. Use direct glob expansion instead of listing all gitignored files

**Current approach (broken and inefficient):**
```bash
# Gets only top-level gitignored items
git ls-files --others --ignored --exclude-standard | cut -d'/' -f1 | sort -u
```

**New approach (efficient and supports nested paths):**
```bash
# Let shell expand patterns directly, then verify they're gitignored
for pattern in "${swcopy_patterns[@]}"; do
    for file in $pattern; do
        if git check-ignore -q "$file"; then
            # Copy or symlink this file
        fi
    done
done
```

**Why this is better:**
- Shell glob expansion is extremely fast (implemented in C)
- Only processes files that match patterns (not all gitignored files)
- Pattern `backend_app/db/store/*.db` expands to just matching .db files (maybe 2-3), not all 50,000 files in `node_modules/`
- Naturally supports all glob features (`*`, `?`, `[...]`, etc.)

#### B. Change matching algorithm from "iterate items" to "expand patterns"

**Current approach (broken for nested paths):**
1. Get top-level gitignored items only
2. For each item, check if it matches any pattern
3. If matches, copy/symlink that item

**New approach (works for all paths, much faster):**
1. For each pattern in `.swcopy`, let the shell expand it to matching files
2. Verify each file is gitignored using `git check-ignore`
3. Check if file should be symlinked (via `.swsymlink` patterns)
4. Copy or symlink the file, creating parent directories as needed

#### C. Handle both file and directory patterns

- **File patterns** (`backend_app/db/store/*.db`): Match individual files, copy each one
- **Directory patterns** (`logs/`, `backend_app/`): Match all files under that directory
- **Glob patterns** (`*.log`, `backend_app/**/*.db`): Use shell pattern matching

#### D. Preserve existing behavior for top-level patterns

Ensure patterns like `.env`, `logs/`, `*.log` still work exactly as before.

### 2. Pattern Matching Logic Using Direct Glob Expansion

Use shell glob expansion to let the shell find matching files:

```bash
# Enable shell options for proper glob behavior
shopt -s nullglob  # Pattern with no matches expands to nothing
shopt -s dotglob   # Include hidden files like .env in globs

for pattern in "${swcopy_patterns[@]}"; do
    # Handle directory patterns (with trailing slash)
    if [[ "$pattern" == */ ]]; then
        # Expand to all files under directory
        pattern="${pattern%/}/**/*"
        shopt -s globstar  # Enable ** for recursive matching
    fi

    # Let shell expand the glob pattern
    for file in $pattern; do
        # Skip if it's a directory (we only copy files)
        [[ -d "$base_dir/$file" ]] && continue

        # Verify file exists and is actually gitignored
        if [[ -f "$base_dir/$file" ]] && git check-ignore -q "$file" 2>/dev/null; then
            # Check if should be symlinked instead of copied
            should_symlink=false
            for symlink_pattern in "${swsymlink_patterns[@]}"; do
                # Use same glob expansion for symlink patterns
                if [[ "$file" == $symlink_pattern ]]; then
                    should_symlink=true
                    break
                fi
            done

            # Copy or symlink the file
            if $should_symlink; then
                ln -s "$base_dir/$file" "$wt_path/$file"
                symlinked+=("$file")
            else
                # Ensure parent directory exists
                mkdir -p "$(dirname "$wt_path/$file")"
                cp "$file" "$wt_path/$file"
                copied+=("$file")
            fi
        fi
    done
done
```

**Key features:**
- `nullglob`: If pattern doesn't match anything, loop body doesn't execute (no error)
- `dotglob`: Hidden files like `.env` are included in `*` patterns
- `globstar`: Makes `**` work for recursive directory matching (optional)
- `git check-ignore -q`: Fast, accurate way to verify file is gitignored

### 3. Shell Options Required

Set these options at the start of `_sw_copy_gitignored()`:

```bash
# Enable glob options for correct behavior
shopt -s nullglob   # Patterns with no matches expand to nothing (not themselves)
shopt -s dotglob    # Include hidden files (like .env) in * patterns
shopt -s globstar   # Enable ** for recursive directory matching (optional)
```

**Important:** Save and restore original shell options to avoid side effects:
```bash
# Save original state
local original_nullglob=$(shopt -p nullglob)
local original_dotglob=$(shopt -p dotglob)
local original_globstar=$(shopt -p globstar)

# Set options
shopt -s nullglob dotglob globstar

# ... do work ...

# Restore original state
$original_nullglob
$original_dotglob
$original_globstar
```

### 4. Parent Directory Creation

Update existing code (lines 134-136) to use full file path:
```bash
# OLD: local parent_dir=$(dirname "$wt_path/$item")
# NEW:
local parent_dir=$(dirname "$wt_path/$file")
[[ ! -d "$parent_dir" ]] && mkdir -p "$parent_dir"
```

This ensures parent directories are created for nested paths like `backend_app/db/store/test.db`.

### 5. Output Formatting

The existing output at lines 143-150 should work without changes:
```bash
if [[ ${#copied[@]} -gt 0 ]]; then
    echo "Copied: ${copied[*]}"
fi
if [[ ${#symlinked[@]} -gt 0 ]]; then
    echo "Symlinked: ${symlinked[*]}"
fi
```

Now it will show nested paths:
```
Copied: backend_app/db/store/test.db backend_app/db/store/cache.db .env
Symlinked: CLAUDE.local.md
```

No changes needed - output naturally handles nested paths.

### 6. Add Comprehensive Tests

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

### 7. Critical Files

**To modify:**
- `worktrees.sh`: `_sw_copy_gitignored()` function (lines 58-151)
  - Remove line 76 entirely (the `git ls-files | cut` approach)
  - Replace lines 71-126 with new glob expansion logic
  - Update variable names (`item` → `file`)

**To extend:**
- `tests/worktrees.bats`: Add nested pattern test cases (after line 829)

**To reference for patterns:**
- Existing tests at lines 596-829 show test structure
- Current pattern matching logic at lines 104-126 (to be replaced)

### 8. Verification Steps

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

- **Before:** Processed only unique top-level items (fast, but broken for nested paths)
- **After:** Uses direct glob expansion (equally fast OR faster, and correct)

**Why this approach is performant:**
- Shell glob expansion is implemented in C and highly optimized
- Only processes files that match patterns (not all gitignored files)
- Example: Pattern `backend_app/db/store/*.db` might match 3 files
  - Old approach would have failed entirely
  - Alternative "get all files" approach would process 50,000+ files
  - This approach processes exactly 3 files ✅

**Performance comparison scenarios:**

| Scenario | Pattern | Old Approach | This Approach |
|----------|---------|--------------|---------------|
| Simple top-level | `.env` | Process 1 item ✅ | Process 1 file ✅ |
| Top-level directory | `logs/` | Process 1 item (copy with `cp -R`) ✅ | Process ~10 files (glob expansion) ✅ |
| Nested pattern | `backend_app/db/store/*.db` | Fails entirely ❌ | Process ~3 matching files ✅ |
| Large repo with node_modules | Any pattern | Process 1-10 top-level items | Process only matching files, ignores node_modules/ |

**Conclusion:** This approach is both correct AND performant. No optimization needed.

## Edge Cases to Handle

1. **Empty patterns** - skip blank lines (already handled by existing code)
2. **Comment lines** - skip `#` lines (already handled by existing code)
3. **Trailing slashes** - convert `logs/` to `logs/**/*` for directory recursion
4. **Patterns with no matches** - `nullglob` option makes loop body not execute (graceful)
5. **Hidden files** - `dotglob` option ensures `.env` matches `*` patterns
6. **Spaces in filenames** - properly quote variables (`"$file"`, not `$file`)
7. **Symlinks** - verify target exists before creating symlink
8. **Files that aren't actually gitignored** - `git check-ignore` verifies before copying
9. **Pattern vs file ambiguity** - Check if file exists (`[[ -f "$base_dir/$file" ]]`) to distinguish between no-match and is-directory

## Summary

This fix will:
- ✅ Make nested patterns like `backend_app/db/store/*.db` work
- ✅ Preserve existing behavior for top-level patterns
- ✅ Intelligently copy only matching files (not entire parent directories)
- ✅ Support glob patterns at any nesting level
- ✅ Work with both `.swcopy` and `.swsymlink`
- ✅ Maintain backward compatibility with existing `.swcopy` files
