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

#### E. Extract helper functions to eliminate duplication

Two pieces of logic are duplicated (pattern loading appears twice in current code; symlink checking appears twice in the new code). Extract them as model-layer helpers:

```bash
# Read patterns from a file, filtering comments and blank lines
# Output: one pattern per line (portable — no nameref needed)
_sw_read_patterns() {
    local file="$1"
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        printf '%s\n' "$line"
    done < "$file"
}

# Check if an item matches any symlink pattern
# Args: $1 = item path, remaining args = symlink patterns
# Returns: 0 if should symlink, 1 otherwise
_sw_should_symlink() {
    local item="${1%/}"
    shift
    local p
    for p in "$@"; do
        [[ "$item" == ${p%/} ]] && return 0
    done
    return 1
}
```

**Why these helpers:**
- `_sw_read_patterns`: Centralizes comment/blank-line filtering. Currently copy-pasted for `.swcopy` and `.swsymlink` loading. Uses `printf` output + process substitution (portable bash/zsh — avoids `local -n` nameref which is bash-only).
- `_sw_should_symlink`: Eliminates the duplicated symlink-check loop from both directory and file branches of the main loop. Normalizes trailing slashes via `${1%/}` and `${p%/}`, then uses unquoted RHS for glob matching (works in both bash and zsh `[[ ]]`).

**Pattern loading now becomes:**
```bash
local swcopy_patterns=()
while IFS= read -r p; do
    swcopy_patterns+=("$p")
done < <(_sw_read_patterns "$swcopy_file")

local swsymlink_patterns=()
if [[ -f "$swsymlink_file" ]]; then
    while IFS= read -r p; do
        swsymlink_patterns+=("$p")
    done < <(_sw_read_patterns "$swsymlink_file")
fi
```

### 2. Pattern Matching Logic Using Hybrid Approach

**Key insight:** Directory patterns like `logs/` don't auto-expand to files - they just match the directory itself. So we should:
- Keep fast `cp -R` for directory patterns (preserves current behavior)
- Use glob expansion for wildcard patterns (fixes the bug)

```bash
# Change to base directory so glob expansion works on correct paths
local original_dir="$PWD"
cd "$base_dir" || return 1

# Enable shell options for proper glob behavior (portable bash/zsh)
if [[ -n "$BASH_VERSION" ]]; then
    local original_nullglob=$(shopt -p nullglob)
    local original_dotglob=$(shopt -p dotglob)
    shopt -s nullglob dotglob
elif [[ -n "$ZSH_VERSION" ]]; then
    local had_nullglob=false had_dotglob=false
    [[ -o nullglob ]] && had_nullglob=true
    [[ -o globdots ]] && had_dotglob=true
    setopt NULL_GLOB GLOB_DOTS
fi

# Track processed items to avoid duplicates across overlapping patterns
local processed=""

for pattern in "${swcopy_patterns[@]}"; do
    if [[ "$pattern" == */ ]]; then
        # Directory pattern (e.g., "logs/", "backend_app/config/")
        local dir="${pattern%/}"

        # Skip if already processed
        case "$processed" in *"|$dir/|"*) continue ;; esac

        # Verify directory exists and is gitignored (or contains gitignored files).
        # git check-ignore on a directory only succeeds if the directory itself is
        # matched by a gitignore rule. Fall back to checking for any gitignored
        # files inside the directory (handles cases like *.db rules).
        if [[ -d "$dir" ]] && \
           { git check-ignore -q "$dir" 2>/dev/null || \
             [[ -n "$(git ls-files --others --ignored --exclude-standard "$dir" 2>/dev/null | head -1)" ]]; }; then

            processed="$processed|$dir/|"

            # Create parent directories for nested paths (e.g., backend_app/config/)
            mkdir -p "$(dirname "$wt_path/$dir")"

            if _sw_should_symlink "$dir" "${swsymlink_patterns[@]}"; then
                ln -s "$base_dir/$dir" "$wt_path/$dir" 2>/dev/null && symlinked+=("$dir/")
            else
                # cp -R src dst: when dst doesn't exist, copies src AS dst (preserves nesting)
                cp -R "$dir" "$wt_path/$dir" 2>/dev/null && copied+=("$dir/")
            fi
        fi
    else
        # File pattern with potential wildcards (e.g., "logs/*.txt", ".env")
        # Shell expands glob relative to CWD (which is now $base_dir)
        local expanded_files=()
        local f
        for f in $pattern; do
            [[ -f "$f" ]] && expanded_files+=("$f")
        done

        # Skip if no files matched (nullglob ensures no literal pattern)
        [[ ${#expanded_files[@]} -eq 0 ]] && continue

        # Batch-verify which files are gitignored (single git subprocess
        # instead of one per file — important when patterns match many files)
        local gitignored_files
        gitignored_files=$(printf '%s\n' "${expanded_files[@]}" | git check-ignore --stdin 2>/dev/null)

        # Process each gitignored file
        local file
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue

            # Skip if already processed (deduplication across patterns)
            case "$processed" in *"|$file|"*) continue ;; esac
            processed="$processed|$file|"

            # Create parent directories for nested paths
            mkdir -p "$(dirname "$wt_path/$file")"

            if _sw_should_symlink "$file" "${swsymlink_patterns[@]}"; then
                ln -s "$base_dir/$file" "$wt_path/$file" 2>/dev/null && symlinked+=("$file")
            else
                cp "$file" "$wt_path/$file" 2>/dev/null && copied+=("$file")
            fi
        done <<< "$gitignored_files"
    fi
done

# Restore shell options (portable bash/zsh)
if [[ -n "$BASH_VERSION" ]]; then
    $original_nullglob
    $original_dotglob
elif [[ -n "$ZSH_VERSION" ]]; then
    $had_nullglob || unsetopt NULL_GLOB
    $had_dotglob || unsetopt GLOB_DOTS
fi

# Restore original directory
cd "$original_dir" || true
```

**Key features:**
- **Portable bash/zsh**: Detects shell and uses appropriate glob options (`shopt` vs `setopt`)
- **Correct CWD**: `cd`s to `$base_dir` before glob expansion, restores afterward
- **Directory patterns** (`logs/`): Use fast `cp -R` or `ln -s` for entire directory, with `mkdir -p` for nested parents
- **Directory gitignore check**: Falls back to checking for gitignored files *inside* the directory if the directory itself isn't a gitignore entry
- **File patterns** (`logs/*.txt`, `.env`): Use glob expansion, batch `git check-ignore --stdin` (single subprocess)
- **Deduplication**: Tracks processed items to avoid double-copying from overlapping patterns
- **Symlink checking**: `_sw_should_symlink` helper eliminates duplicated loop (one call per item instead of inlined loop in both branches)
- **Pattern loading**: `_sw_read_patterns` helper centralizes comment/blank-line filtering for both `.swcopy` and `.swsymlink`
- **No argument limits**: Directory patterns don't expand to thousands of files

### 3. Shell Options and Working Directory (Portable bash/zsh)

The function must work when sourced by either bash or zsh. Set these at the start of `_sw_copy_gitignored()`:

```bash
# Change to base directory so glob patterns expand against the right files.
# The function receives $base_dir as a parameter, but glob expansion is
# relative to CWD — so we must cd there explicitly.
local original_dir="$PWD"
cd "$base_dir" || return 1

# Enable glob options — detect shell for portability
if [[ -n "$BASH_VERSION" ]]; then
    # shopt -p outputs restore commands like "shopt -s nullglob" or "shopt -u nullglob"
    local original_nullglob=$(shopt -p nullglob)
    local original_dotglob=$(shopt -p dotglob)
    shopt -s nullglob dotglob
elif [[ -n "$ZSH_VERSION" ]]; then
    # [[ -o option ]] tests whether a zsh option is currently set
    local had_nullglob=false had_dotglob=false
    [[ -o nullglob ]] && had_nullglob=true
    [[ -o globdots ]] && had_dotglob=true
    setopt NULL_GLOB GLOB_DOTS
fi

# ... do work ...

# Restore shell options
if [[ -n "$BASH_VERSION" ]]; then
    $original_nullglob
    $original_dotglob
elif [[ -n "$ZSH_VERSION" ]]; then
    $had_nullglob || unsetopt NULL_GLOB
    $had_dotglob || unsetopt GLOB_DOTS
fi

# Restore original directory
cd "$original_dir" || true
```

**Why these options:**
- `nullglob` (bash) / `NULL_GLOB` (zsh): If pattern `backend_app/db/store/*.db` matches nothing, loop doesn't execute (graceful)
- `dotglob` (bash) / `GLOB_DOTS` (zsh): Pattern `*` includes `.env` and other hidden files

**Why cd to `$base_dir`:**
- Glob patterns like `backend_app/db/store/*.db` expand relative to CWD
- The function receives `$base_dir` as a parameter, but doesn't control CWD
- Although `sw add` guards against running from non-base directories, the function shouldn't silently depend on CWD matching `$base_dir`
- Explicit `cd` makes the contract clear and avoids subtle breakage

**Note:** We don't need `globstar` / `GLOB_STAR_SHORT` because we use `cp -R` for directories, not `**/*` expansion. The `**` glob syntax is explicitly unsupported — document this limitation for users.

### 4. Parent Directory Creation

Parent directory creation is now handled inline in the main loop for both directory and file patterns:

```bash
# For directory patterns (e.g., backend_app/config/):
mkdir -p "$(dirname "$wt_path/$dir")"
# Creates: $wt_path/backend_app/ so that config/ can be placed inside it

# For file patterns (e.g., backend_app/db/store/test.db):
mkdir -p "$(dirname "$wt_path/$file")"
# Creates: $wt_path/backend_app/db/store/
```

This ensures correct nesting. For the directory `cp -R` case, we must handle two scenarios:
- **Target doesn't exist**: `cp -R "$dir" "$wt_path/$dir"` copies source AS target (correct)
- **Target already exists** (e.g., git created it for tracked files): `cp -R "$dir" "$wt_path/$dir"` would create `$wt_path/$dir/$dir_basename/` (nested incorrectly!). Fix: use `cp -R "$dir/." "$wt_path/$dir/"` to merge contents into the existing directory.

```bash
if [[ -d "$wt_path/$dir" ]]; then
    # Target exists — merge contents
    cp -R "$dir/." "$wt_path/$dir/" 2>/dev/null && copied+=("$dir/")
else
    cp -R "$dir" "$wt_path/$dir" 2>/dev/null && copied+=("$dir/")
fi
```

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

7. **Duplicate patterns** (`.env` in both `*.env` and `.env` patterns)
   - Verify file is only copied once, not duplicated

8. **Directory where only contents are gitignored** (e.g., `*.db` rule causes files inside `backend_app/db/store/` to be gitignored, but the directory itself isn't a gitignore entry)
   - Verify directory pattern still triggers copy via `git ls-files` fallback

9. **Nested directory cp destination** (`backend_app/config/`)
   - Verify resulting path is `$wt/backend_app/config/`, NOT `$wt/config/`

Also update **zsh integration tests** (`tests/zsh-integration.zsh`):

10. **Zsh glob options** - Verify `NULL_GLOB` and `GLOB_DOTS` are correctly set/restored
11. **Zsh nested pattern expansion** - Verify nested patterns work under zsh (catches any `setopt` issues)

### 7. Critical Files

**To modify:**
- `worktrees.sh`: `_sw_copy_gitignored()` function (lines 58-151)
  - Remove line 76 entirely (the `git ls-files | cut` approach)
  - Replace lines 71-126 with new glob expansion logic
  - Update variable names (`item` → `file`)
  - Replace pattern-loading loops (lines 79-95) with `_sw_read_patterns` calls

**To add (model layer):**
- `worktrees.sh`: Add `_sw_read_patterns()` and `_sw_should_symlink()` helpers in the model section (before `_sw_copy_gitignored`)

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
   - Batch `git check-ignore --stdin` verifies all expanded files in a **single subprocess** (not one per file)

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
4. **Patterns with no matches** - `nullglob`/`NULL_GLOB` option makes loop body not execute (graceful)
5. **Hidden files** - `dotglob`/`GLOB_DOTS` option ensures `.env` matches `*` patterns
6. **Spaces in filenames** - glob expansion handles spaces correctly; quote variables in commands
7. **Symlink targets** - use absolute paths in `ln -s "$base_dir/$file"` for reliability
8. **Files that aren't actually gitignored** - `git check-ignore --stdin` batch-verifies before copying/symlinking
9. **Directory vs file** - Check `[[ -d ]]` and `[[ -f ]]` to distinguish properly
10. **Duplicate matches across patterns** - tracked via `$processed` string; `case` check skips already-handled items
11. **Directory not itself gitignored** - falls back to `git ls-files --others --ignored` to check for gitignored *contents* (handles cases where `*.db` rules cause files inside a directory to be ignored without the directory itself being a gitignore entry)
12. **Nested directory cp destination** - use `cp -R "$dir" "$wt_path/$dir"` (not `"$wt_path/"`) to preserve nesting; `mkdir -p` parent first
13. **`**` recursive globs** - explicitly unsupported; `globstar`/`GLOB_STAR_SHORT` is not enabled to avoid unpredictable expansion in large repos. Users should use directory patterns (`backend_app/`) for recursive copying or list specific nested glob paths
14. **CWD dependency** - function `cd`s to `$base_dir` before glob expansion and restores CWD afterward, so it doesn't silently depend on the caller's working directory
15. **Bash vs zsh portability** - shell detection via `$BASH_VERSION`/`$ZSH_VERSION` selects correct glob option commands (`shopt` vs `setopt`)

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
- ✅ Work in both bash and zsh (portable shell option detection)
- ✅ Correctly handle nested directory destinations (`backend_app/config/` preserves full path)
- ✅ Batch `git check-ignore --stdin` for file patterns (single subprocess, not one per file)
- ✅ Deduplicate files matched by overlapping patterns
- ✅ Handle directories where only contents (not the dir itself) are gitignored

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
- Shell globs don't support all gitignore features (e.g., `!` negation)
- `**` recursive globs are explicitly unsupported — not enabling `globstar`/`GLOB_STAR_SHORT` avoids runaway expansion in large repos. Users should use directory patterns (`logs/`) for recursive copy, or spell out specific nested paths (`backend_app/db/store/*.db`)
- Document supported pattern syntax in README with examples

**Spaces in patterns:**
- Patterns with spaces (e.g., `my logs/*.txt`) may not work as expected with the unquoted `$pattern` expansion in `for f in $pattern`
- This is rare in `.swcopy` usage but worth documenting

**Symlink pattern matching:**
- Symlink matching uses `[[ "$file" == $symlink_pattern ]]` (shell pattern matching), which is string-based, while copy matching uses filesystem glob expansion. These are subtly different engines — shell pattern matching doesn't resolve against real files. For the `.swsymlink` use case this is acceptable since patterns are user-specified and matched against already-resolved file paths. But worth noting if patterns with character classes or complex globs are used in `.swsymlink`.

**Directory gitignore edge case:**
- A directory pattern like `backend_app/config/` where the directory itself isn't in `.gitignore` but contains gitignored files (e.g., matched by a `*.secret` rule) will still be copied via the `git ls-files` fallback. However, `cp -R` will copy the *entire* directory (including tracked files). If users need to copy only the gitignored files within a directory, they should use a file glob pattern like `backend_app/config/*.secret` instead.

**Overall:** The hybrid approach fixes the bug with correct CWD handling, portable bash/zsh support, batch gitignore verification, deduplication, and proper nested path handling.
