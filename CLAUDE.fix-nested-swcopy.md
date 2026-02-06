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

### 2. Pattern Matching Logic Using Hybrid Approach

**Key insight:** Directory patterns like `logs/` don't auto-expand to files - they just match the directory itself. So we should:
- Keep fast `cp -R` for directory patterns (preserves current behavior)
- Use glob expansion for wildcard patterns (fixes the bug)

```bash
# Enable shell options for proper glob behavior
shopt -s nullglob  # Pattern with no matches expands to nothing
shopt -s dotglob   # Include hidden files like .env in globs

for pattern in "${swcopy_patterns[@]}"; do
    if [[ "$pattern" == */ ]]; then
        # Directory pattern (e.g., "logs/")
        dir="${pattern%/}"

        # Verify directory exists and is gitignored
        if [[ -d "$base_dir/$dir" ]] && git check-ignore -q "$dir" 2>/dev/null; then
            # Check if this directory should be symlinked
            should_symlink=false
            for symlink_pattern in "${swsymlink_patterns[@]}"; do
                if [[ "${dir}" == "${symlink_pattern%/}" ]] || [[ "${dir}/" == "${symlink_pattern%/}/" ]]; then
                    should_symlink=true
                    break
                fi
            done

            if $should_symlink; then
                # Symlink entire directory
                ln -s "$base_dir/$dir" "$wt_path/$dir" 2>/dev/null && symlinked+=("$dir/")
            else
                # Copy entire directory (fast, preserves current behavior)
                cp -R "$dir" "$wt_path/" 2>/dev/null && copied+=("$dir/")
            fi
        fi
    else
        # File pattern with potential wildcards (e.g., "logs/*.txt", ".env")
        # Let shell expand the glob pattern
        for file in $pattern; do
            # Skip if it's a directory
            [[ -d "$base_dir/$file" ]] && continue

            # Verify file exists and is gitignored
            if [[ -f "$base_dir/$file" ]] && git check-ignore -q "$file" 2>/dev/null; then
                # Check if this file should be symlinked
                should_symlink=false
                for symlink_pattern in "${swsymlink_patterns[@]}"; do
                    # Match against symlink patterns (support globs)
                    if [[ "$file" == $symlink_pattern ]]; then
                        should_symlink=true
                        break
                    fi
                done

                if $should_symlink; then
                    # Symlink individual file
                    mkdir -p "$(dirname "$wt_path/$file")"
                    ln -s "$base_dir/$file" "$wt_path/$file" 2>/dev/null && symlinked+=("$file")
                else
                    # Copy individual file
                    mkdir -p "$(dirname "$wt_path/$file")"
                    cp "$file" "$wt_path/$file" 2>/dev/null && copied+=("$file")
                fi
            fi
        done
    fi
done
```

**Key features:**
- **Directory patterns** (`logs/`): Use fast `cp -R` or `ln -s` for entire directory
- **File patterns** (`logs/*.txt`, `.env`): Use glob expansion, process each file
- **Symlink checking**: Check each item (directory or file) against `.swsymlink` patterns
- **No argument limits**: Directory patterns don't expand to thousands of files
- **Fast**: Preserves current `cp -R` performance for directories

### 3. Shell Options Required

Set these options at the start of `_sw_copy_gitignored()`:

```bash
# Save original state
local original_nullglob=$(shopt -p nullglob)
local original_dotglob=$(shopt -p dotglob)

# Enable glob options for correct behavior
shopt -s nullglob   # Patterns with no matches expand to nothing (not themselves)
shopt -s dotglob    # Include hidden files (like .env) in * patterns

# ... do work ...

# Restore original state at end of function
$original_nullglob
$original_dotglob
```

**Why these options:**
- `nullglob`: If pattern `backend_app/db/store/*.db` matches nothing, loop doesn't execute (graceful)
- `dotglob`: Pattern `*` includes `.env` and other hidden files

**Note:** We don't need `globstar` because we use `cp -R` for directories, not `**/*` expansion

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
- **After:** Hybrid approach (equally fast for directories, fixes nested patterns)

**Why the hybrid approach is optimal:**

1. **Directory patterns** (`logs/`): Keep fast `cp -R` behavior
   - Pattern `logs/` doesn't expand to files - just matches the directory itself
   - Use `cp -R logs/` same as current code (very fast)
   - No change in performance ✅

2. **File patterns with wildcards** (`backend_app/db/store/*.db`): Use glob expansion
   - Shell glob expansion is implemented in C and highly optimized
   - Only processes files that match the pattern
   - Pattern `backend_app/db/store/*.db` expands to 2-3 matching files, not 50,000

3. **Simple file patterns** (`.env`): Use glob expansion
   - Pattern `.env` expands to just that one file
   - Essentially same as current behavior

**Performance comparison:**

| Scenario | Pattern | Old Approach | Hybrid Approach |
|----------|---------|--------------|-----------------|
| Top-level file | `.env` | ✅ Fast (1 item) | ✅ Fast (1 file) |
| Top-level directory | `logs/` | ✅ Fast (`cp -R`) | ✅ Fast (`cp -R`, unchanged) |
| Nested directory | `backend_app/config/` | ❌ Fails | ✅ Fast (`cp -R`) |
| Nested file pattern | `backend_app/db/store/*.db` | ❌ Fails | ✅ Fast (glob → 3 files) |
| Large repo with node_modules | `logs/*.txt` | ❌ Fails for nested | ✅ Fast (only .txt files in logs/) |

**Key advantage:** No argument list limits or performance degradation because:
- Directories use `cp -R` (don't expand to individual files)
- Wildcards only expand to matching files (not entire repo)

**Conclusion:** This approach fixes the bug with **zero performance penalty** for existing patterns.

## Edge Cases to Handle

1. **Empty patterns** - skip blank lines (already handled by existing code)
2. **Comment lines** - skip `#` lines (already handled by existing code)
3. **Trailing slashes** - patterns ending with `/` are treated as directory patterns
4. **Patterns with no matches** - `nullglob` option makes loop body not execute (graceful)
5. **Hidden files** - `dotglob` option ensures `.env` matches `*` patterns
6. **Spaces in filenames** - glob expansion handles spaces correctly; quote variables in commands
7. **Symlink targets** - use absolute paths in `ln -s "$base_dir/$file"` for reliability
8. **Files that aren't actually gitignored** - `git check-ignore` verifies before copying/symlinking
9. **Directory vs file** - Check `[[ -d ]]` and `[[ -f ]]` to distinguish properly

## Symlink Behavior Examples

**Example 1: Symlink entire directory**
```bash
# .swcopy
backend_app/config/

# .swsymlink
backend_app/config/

# Result: backend_app/config/ is symlinked as a whole directory
```

**Example 2: Symlink individual files**
```bash
# .swcopy
*.md
backend_app/db/store/*.db

# .swsymlink
CLAUDE.local.md

# Result:
# - CLAUDE.local.md is symlinked
# - README.md is copied (not in .swsymlink)
# - backend_app/db/store/*.db files are copied (not in .swsymlink)
```

**Example 3: Mixed - copy directory but symlink specific files**
```bash
# .swcopy
backend_app/config/
CLAUDE.local.md

# .swsymlink
CLAUDE.local.md

# Result:
# - backend_app/config/ is copied as directory (not in .swsymlink)
# - CLAUDE.local.md is symlinked
```

**Note:** Symlink patterns must match items from `.swcopy` patterns:
- If `.swcopy` has `logs/`, `.swsymlink` needs `logs/` to symlink the directory
- If `.swcopy` has `logs/*.txt`, `.swsymlink` needs `logs/*.txt` or specific files to symlink them

## Summary

This fix will:
- ✅ Make nested patterns like `backend_app/db/store/*.db` work (fixes the bug)
- ✅ Preserve existing behavior for directory patterns (still uses fast `cp -R`)
- ✅ Intelligently copy only matching files (not entire parent directories)
- ✅ Support glob patterns at any nesting level
- ✅ Work with both `.swcopy` and `.swsymlink` for both directories and files
- ✅ Maintain backward compatibility with existing `.swcopy` files
- ✅ Zero performance penalty for existing patterns

## Advantages of Hybrid Approach

1. **Best of both worlds:**
   - Fast `cp -R` for directories (preserves current behavior)
   - Glob expansion for wildcards (fixes the bug)

2. **No argument list limits:**
   - Directory patterns like `logs/` don't expand to thousands of files
   - They just match the directory itself, then `cp -R`

3. **Correct and performant:**
   - Pattern `backend_app/db/store/*.db` expands to only matching files
   - Not all 50,000 files in the repo

4. **Symlink flexibility:**
   - Can symlink entire directories: `logs/` in `.swsymlink`
   - Can symlink individual files: `logs/*.txt` in `.swsymlink`
   - Natural behavior that mirrors copy logic

## Remaining Considerations

**Pattern syntax limitations:**
- Shell globs don't support all gitignore features (e.g., `!` negation, `**` without globstar)
- Users should test patterns to ensure they work as expected
- Document common patterns in README

**Spaces in patterns:**
- Patterns with spaces (e.g., `my logs/*.txt`) may not work as expected
- This is rare in `.swcopy` usage but worth documenting

**Overall:** The hybrid approach eliminates all major downsides while fixing the bug. It's the optimal solution.
