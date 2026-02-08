# Sideways - Git Worktree Helper
#
# Source this file in ~/.zshrc or ~/.bashrc:
#
#   # Sideways - git worktree helper
#   source ~/path/to/worktrees.sh

SW_VERSION="0.6.2"

# =============================================================================
# MODEL LAYER - Core business logic and state queries
# =============================================================================

# Get base directory (first worktree is always the main one)
_sw_get_base_dir() {
    git worktree list --porcelain | head -1 | sed 's/^worktree //'
}

# Check if worktree has uncommitted changes
# Args: $1 = worktree path (optional, defaults to current directory)
_sw_has_uncommitted_changes() {
    local wt_path="${1:-.}"
    [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]
}

# Check if current path is the base directory
# Args: $1 = current path, $2 = base directory
_sw_is_in_base() {
    [[ "$1" == "$2" ]]
}

# Choose editor based on flag, then $VISUAL, then $EDITOR
# Args: $1 = editor from flag (optional)
# Returns: editor command or empty string
_sw_choose_editor() {
    local flag_editor="$1"
    if [[ -n "$flag_editor" ]]; then
        echo "$flag_editor"
    elif [[ -n "$VISUAL" ]]; then
        echo "$VISUAL"
    elif [[ -n "$EDITOR" ]]; then
        echo "$EDITOR"
    fi
}

# Guard: ensure command is run from base directory
# Args: $1 = repo_root, $2 = base_dir, $3 = command name, $4+ = original args
_sw_guard_base_dir() {
    local repo_root="$1" base_dir="$2" cmd_name="$3"
    shift 3
    if [[ "$repo_root" != "$base_dir" ]]; then
        _sw_error "$cmd_name must be run from base directory"
        echo "Run 'sw base' first, then 'sw $cmd_name $*'" >&2
        return 1
    fi
}

# Read patterns from a file, filtering comments and blank lines
# Output: one pattern per line
_sw_read_patterns() {
    local file="$1"
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        printf '%s\n' "$line"
    done < "$file"
}

# Resolve patterns to actual gitignored files/dirs
# Must be called from base_dir with glob shell options already set
# Args: patterns (one per arg)
# Result: populates _sw_resolved array (dirs end with /)
_sw_resolve_patterns() {
    [[ -n "$ZSH_VERSION" ]] && setopt LOCAL_OPTIONS NO_XTRACE NO_VERBOSE
    _sw_resolved=()
    local seen="" pattern dir f gitignored_files file
    local -a expanded_files
    for pattern in "$@"; do
        if [[ "$pattern" == */ ]]; then
            dir="${pattern%/}"
            case "$seen" in *"|$dir/|"*) continue ;; esac
            if [[ -d "$dir" ]] && \
               { git check-ignore -q "$dir" 2>/dev/null || \
                 [[ -n "$(git ls-files --others --ignored --exclude-standard "$dir" 2>/dev/null | head -1)" ]]; }; then
                seen="$seen|$dir/|"
                _sw_resolved+=("$dir/")
            fi
        else
            expanded_files=()
            for f in $pattern; do
                [[ -f "$f" ]] && expanded_files+=("$f")
            done
            [[ ${#expanded_files[@]} -eq 0 ]] && continue
            gitignored_files=$(printf '%s\n' "${expanded_files[@]}" | git check-ignore --stdin 2>/dev/null)
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                case "$seen" in *"|$file|"*) continue ;; esac
                seen="$seen|$file|"
                _sw_resolved+=("$file")
            done <<< "$gitignored_files"
        fi
    done
}

# Copy and symlink gitignored files from base to new worktree
# .swcopy patterns are copied, .swsymlink patterns are symlinked (independently)
# Args: $1 = base_dir, $2 = worktree_path
_sw_copy_gitignored() {
    local base_dir="$1"
    local wt_path="$2"
    local swcopy_file="$base_dir/.swcopy"
    local swsymlink_file="$base_dir/.swsymlink"

    # If neither config file exists, nothing to do
    [[ ! -f "$swcopy_file" ]] && [[ ! -f "$swsymlink_file" ]] && return 0

    # Load .swcopy patterns
    local swcopy_patterns=()
    local p
    if [[ -f "$swcopy_file" ]]; then
        while IFS= read -r p; do
            swcopy_patterns+=("$p")
        done < <(_sw_read_patterns "$swcopy_file")
    fi

    # Load .swsymlink patterns
    local swsymlink_patterns=()
    if [[ -f "$swsymlink_file" ]]; then
        while IFS= read -r p; do
            swsymlink_patterns+=("$p")
        done < <(_sw_read_patterns "$swsymlink_file")
    fi

    # Change to base directory so glob expansion works on correct paths
    local original_dir="$PWD"
    cd "$base_dir" || return 1

    # Enable shell options for proper glob behavior (portable bash/zsh)
    if [[ -n "$BASH_VERSION" ]]; then
        local original_nullglob=$(shopt -p nullglob)
        local original_dotglob=$(shopt -p dotglob)
        local original_globstar=$(shopt -p globstar 2>/dev/null || true)
        shopt -s nullglob dotglob
        shopt -s globstar 2>/dev/null || true  # bash 4+ only; ** falls back to * on bash 3
    elif [[ -n "$ZSH_VERSION" ]]; then
        setopt LOCAL_OPTIONS NO_XTRACE NO_VERBOSE NULL_GLOB GLOB_DOTS GLOB_SUBST
        setopt GLOB_STAR_SHORT 2>/dev/null || true  # zsh 5.2+ only
    fi

    # --- Resolve patterns to actual gitignored items ---
    # Call _sw_resolve_patterns directly (no subshell) to avoid zsh XTRACE leaks
    local copy_items=() symlink_items=()
    if [[ ${#swcopy_patterns[@]} -gt 0 ]]; then
        _sw_resolve_patterns "${swcopy_patterns[@]}"
        copy_items=("${_sw_resolved[@]}")
    fi
    if [[ ${#swsymlink_patterns[@]} -gt 0 ]]; then
        _sw_resolve_patterns "${swsymlink_patterns[@]}"
        symlink_items=("${_sw_resolved[@]}")
    fi

    # --- Check for overlap between resolved items ---
    local conflicts=()
    local ci si
    for si in "${symlink_items[@]}"; do
        for ci in "${copy_items[@]}"; do
            [[ "${si%/}" == "${ci%/}" ]] && conflicts+=("${si%/}")
        done
    done
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        local c
        for c in "${conflicts[@]}"; do
            _sw_error "'$c' is in both .swcopy and .swsymlink (pick one)"
        done
        if [[ -n "$BASH_VERSION" ]]; then
            $original_nullglob
            $original_dotglob
            [[ -n "$original_globstar" ]] && $original_globstar
        fi
        cd "$original_dir" || true
        return 1
    fi

    # --- Execute copies ---
    local copied=()
    local item
    for item in "${copy_items[@]}"; do
        if [[ "$item" == */ ]]; then
            local dir="${item%/}"
            mkdir -p "$(dirname "$wt_path/$dir")"
            if [[ -d "$wt_path/$dir" ]]; then
                # Target exists (e.g., git created it for tracked files) — merge contents
                cp -R "$dir/." "$wt_path/$dir/" 2>/dev/null && copied+=("$item")
            else
                cp -R "$dir" "$wt_path/$dir" 2>/dev/null && copied+=("$item")
            fi
        else
            mkdir -p "$(dirname "$wt_path/$item")"
            cp "$item" "$wt_path/$item" 2>/dev/null && copied+=("$item")
        fi
    done

    # --- Execute symlinks ---
    local symlinked=()
    for item in "${symlink_items[@]}"; do
        if [[ "$item" == */ ]]; then
            local dir="${item%/}"
            mkdir -p "$(dirname "$wt_path/$dir")"
            ln -s "$base_dir/$dir" "$wt_path/$dir" 2>/dev/null && symlinked+=("$item")
        else
            mkdir -p "$(dirname "$wt_path/$item")"
            ln -s "$base_dir/$item" "$wt_path/$item" 2>/dev/null && symlinked+=("$item")
        fi
    done

    # Restore shell options (zsh restores automatically via LOCAL_OPTIONS)
    if [[ -n "$BASH_VERSION" ]]; then
        $original_nullglob
        $original_dotglob
        [[ -n "$original_globstar" ]] && $original_globstar
    fi

    # Restore original directory
    cd "$original_dir" || true

    # Output per-line list of copied and symlinked items
    for item in "${copied[@]}"; do
        echo "  copy  $item"
    done
    for item in "${symlinked[@]}"; do
        echo "  link  $item"
    done
}

# =============================================================================
# VIEW LAYER - Output formatting
# =============================================================================

# Standardized error output
_sw_error() {
    echo "sw: $*" >&2
}

# Suggest installing fzf for interactive mode
_sw_no_fzf_error() {
    echo "Interactive mode requires fzf. Install it with:" >&2
    echo "  brew install fzf    # macOS" >&2
    echo "  apt install fzf     # Debian/Ubuntu" >&2
    echo "  winget install fzf  # Windows" >&2
    if [[ -n "$1" ]]; then
        echo "Or provide a branch name: $1" >&2
    fi
    return 1
}

# Format worktree list for fzf with short display paths, output selected full path
_sw_fzf_pick() {
    while IFS= read -r line; do
        local wt_path="${line%% *}"
        local rest="${line#* }"
        local short="../$(basename "$wt_path")"
        printf '%s|%s %s\n' "$wt_path" "$short" "$rest"
    done | fzf --delimiter='|' --with-nth=2 | cut -d'|' -f1
}

# =============================================================================
# CONTROLLER LAYER - Command handlers
# =============================================================================

# sw add: Create a new worktree
# Args: $1=repo_root, $2=base_dir, $3=worktrees_dir_rel, $4=worktrees_dir_abs, $5+=command args
_sw_cmd_add() {
    local repo_root="$1" base_dir="$2" worktrees_dir_rel="$3" worktrees_dir_abs="$4"
    shift 4

    # Guard: must be in base directory
    _sw_guard_base_dir "$repo_root" "$base_dir" "add" "$@" || return 1

    local switch=false
    local open_after=false
    while [[ "$1" == -* ]]; do
        case "$1" in
            -s|--switch) switch=true; shift ;;
            -o|--open) open_after=true; shift ;;
            -so|-os) switch=true; open_after=true; shift ;;
            *) _sw_error "Unknown option: $1"; return 1 ;;
        esac
    done

    local branch="$1"
    if [[ -z "$branch" ]]; then
        _sw_error "Usage: sw add [-s|--switch] <branch-name>"
        return 1
    fi

    local wt_path="$worktrees_dir_rel/$branch"
    local wt_abs_path="$worktrees_dir_abs/$branch"
    local git_output
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        # Branch exists, use it
        if ! git_output=$(git worktree add "$wt_path" "$branch" 2>&1); then
            echo "$git_output" >&2
            return 1
        fi
        echo "Created: $wt_path (existing branch $branch)"
    else
        # Create new branch
        if ! git_output=$(git worktree add "$wt_path" -b "$branch" 2>&1); then
            echo "$git_output" >&2
            return 1
        fi
        echo "Created: $wt_path (new branch $branch)"
    fi

    # Copy/symlink gitignored files to new worktree
    _sw_copy_gitignored "$base_dir" "$wt_abs_path" || return 1

    if $switch; then
        cd "$wt_path"
    fi

    if $open_after; then
        local editor
        editor=$(_sw_choose_editor "")
        if [[ -z "$editor" ]]; then
            echo "Warning: cannot open - no editor configured (\$VISUAL or \$EDITOR)" >&2
        else
            "$editor" "$wt_abs_path"
        fi
    fi
}

# sw cd: Change to a worktree directory
# Args: $1=worktrees_dir_abs, $2+=command args
_sw_cmd_cd() {
    local worktrees_dir_abs="$1"
    shift

    local branch="$1"
    if [[ -n "$branch" ]]; then
        cd "$worktrees_dir_abs/$branch"
    elif command -v fzf &>/dev/null; then
        local selected
        selected=$(git worktree list | _sw_fzf_pick)
        [[ -n "$selected" ]] && cd "$selected"
    else
        _sw_no_fzf_error "sw cd <branch-name>"
        return 1
    fi
}

# sw rm: Remove a worktree
# Args: $1=repo_root, $2=base_dir, $3=worktrees_dir_rel, $4=worktrees_dir_abs, $5+=command args
_sw_cmd_rm() {
    local repo_root="$1" base_dir="$2" worktrees_dir_rel="$3" worktrees_dir_abs="$4"
    shift 4

    # Guard: must be in base directory
    _sw_guard_base_dir "$repo_root" "$base_dir" "rm" "$@" || return 1

    local delete_flag=""
    while [[ "$1" == -* ]]; do
        case "$1" in
            -d) delete_flag="-d"; shift ;;
            -D) delete_flag="-D"; shift ;;
            *) _sw_error "Unknown option: $1"; return 1 ;;
        esac
    done

    local branch="$1"
    if [[ -z "$branch" ]]; then
        if command -v fzf &>/dev/null; then
            local selected
            selected=$(git worktree list | awk -v base="$base_dir" '$1 != base' | _sw_fzf_pick)
            [[ -z "$selected" ]] && return 0
            branch=$(basename "$selected")
        else
            _sw_no_fzf_error "sw rm [-d|-D] <branch-name>"
            return 1
        fi
    fi

    local wt_path="$worktrees_dir_rel/$branch"
    local wt_abs_path="$worktrees_dir_abs/$branch"

    # Guard: check for uncommitted changes
    if _sw_has_uncommitted_changes "$wt_abs_path"; then
        _sw_error "worktree '$branch' has uncommitted changes"
        echo "Commit or stash changes before removing" >&2
        return 1
    fi

    if ! git worktree remove "$wt_path"; then
        return 1
    fi
    echo "Removed worktree: $wt_path"

    if [[ -n "$delete_flag" ]]; then
        if git branch "$delete_flag" "$branch" 2>/dev/null; then
            echo "Deleted branch: $branch"
        else
            echo "Branch $branch not fully merged. Use -D to force delete." >&2
        fi
    fi
}

# sw list: List all worktrees
# Args: $1=repo_root, $2=base_dir
_sw_cmd_list() {
    local repo_root="$1" base_dir="$2"

    local wt_path wt_commit wt_branch location marker dirty
    local current_path="$repo_root"
    while IFS= read -r line; do
        case "$line" in
            worktree\ *)
                wt_path="${line#worktree }"
                ;;
            HEAD\ *)
                wt_commit="${line#HEAD }"
                wt_commit="${wt_commit:0:7}"  # Short hash
                ;;
            branch\ *)
                wt_branch="${line#branch refs/heads/}"
                ;;
            detached)
                wt_branch="(detached)"
                ;;
            "")
                # End of entry, output it
                if [[ -n "$wt_path" ]]; then
                    # Determine location type
                    if [[ "$wt_path" == "$base_dir" ]]; then
                        location="base"
                    else
                        location="worktree"
                    fi

                    # Current worktree indicator
                    if [[ "$wt_path" == "$current_path" ]]; then
                        marker="*"
                    else
                        marker=" "
                    fi

                    # Check for uncommitted changes
                    if _sw_has_uncommitted_changes "$wt_path"; then
                        dirty="[modified]"
                    else
                        dirty=""
                    fi

                    printf "%s %s %-8s %s%s\n" "$marker" "$wt_commit" "$location" "$wt_branch" "${dirty:+ $dirty}"
                fi
                wt_path="" wt_commit="" wt_branch=""
                ;;
        esac
    done < <(git worktree list --porcelain; echo)
}

# sw prune: Prune stale worktree references
_sw_cmd_prune() {
    git worktree prune
    echo "Pruned stale worktree references"
}

# sw base: Jump back to base directory
# Args: $1=repo_root, $2=base_dir
_sw_cmd_base() {
    local repo_root="$1" base_dir="$2"

    if _sw_is_in_base "$repo_root" "$base_dir"; then
        echo "Already in base directory: $base_dir"
        return 0
    fi
    cd "$base_dir"
}

# sw info: Show current worktree info
_sw_cmd_info() {
    local current_path current_branch info_base_dir location
    current_path=$(git rev-parse --show-toplevel)
    current_branch=$(git branch --show-current)
    info_base_dir=$(_sw_get_base_dir)

    if _sw_is_in_base "$current_path" "$info_base_dir"; then
        location="base"
    else
        location="worktree"
    fi

    echo "Branch:   $current_branch"
    echo "Path:     $current_path"
    echo "Location: $location"
}

# sw rebase: Fetch and rebase onto a branch
# Args: $1+=command args
_sw_cmd_rebase() {
    local target_branch="$1"
    if [[ -z "$target_branch" ]]; then
        echo "Usage: sw rebase <branch>" >&2
        echo "Example: sw rebase main" >&2
        return 1
    fi

    echo "Fetching from origin..."
    if ! git fetch; then
        return 1
    fi
    echo "Rebasing onto origin/$target_branch..."
    git rebase "origin/$target_branch"
}

# sw done: Remove current worktree and return to base
_sw_cmd_done() {
    local current_path done_base_dir
    current_path=$(git rev-parse --show-toplevel)
    done_base_dir=$(_sw_get_base_dir)

    if _sw_is_in_base "$current_path" "$done_base_dir"; then
        _sw_error "not in a worktree (already in base directory)"
        return 1
    fi

    # Guard: check for uncommitted changes
    if _sw_has_uncommitted_changes; then
        _sw_error "current worktree has uncommitted changes"
        echo "Commit or stash changes before removing" >&2
        return 1
    fi

    # Move to base first, then remove worktree
    cd "$done_base_dir" || return 1
    if ! git worktree remove "$current_path"; then
        return 1
    fi
    echo "Removed worktree: $current_path"
    echo "Branch preserved. Now in base directory: $done_base_dir"
}

# sw open: Open worktree in editor
# Args: $1=base_dir, $2=worktrees_dir_abs, $3+=command args
_sw_cmd_open() {
    local base_dir="$1" worktrees_dir_abs="$2"
    shift 2

    # Parse options
    local editor_flag=""
    while [[ "$1" == -* ]]; do
        case "$1" in
            -e) editor_flag="$2"; shift 2 ;;
            --editor) editor_flag="$2"; shift 2 ;;
            --editor=*) editor_flag="${1#--editor=}"; shift ;;
            *) _sw_error "Unknown option: $1"; return 1 ;;
        esac
    done

    local target="$1"
    local target_dir

    # Resolve target directory
    if [[ -z "$target" || "$target" == "." ]]; then
        if command -v fzf &>/dev/null; then
            local selected
            selected=$(git worktree list | _sw_fzf_pick)
            [[ -z "$selected" ]] && return 0
            target_dir="$selected"
        else
            _sw_no_fzf_error "sw open [-e <editor>] <branch-name>"
            return 1
        fi
    else
        # First check if it matches the base branch
        local base_branch
        base_branch=$(git -C "$base_dir" branch --show-current 2>/dev/null)
        if [[ "$target" == "$base_branch" ]]; then
            target_dir="$base_dir"
        elif [[ -d "$worktrees_dir_abs/$target" ]]; then
            # Worktree exists
            target_dir="$worktrees_dir_abs/$target"
        elif git show-ref --verify --quiet "refs/heads/$target"; then
            # Branch exists but no worktree
            _sw_error "'$target' is a branch but has no worktree"
            echo "Hint: sw add $target && sw open $target" >&2
            return 1
        else
            _sw_error "worktree '$target' not found"
            return 1
        fi
    fi

    # Get editor
    local editor
    editor=$(_sw_choose_editor "$editor_flag")
    if [[ -z "$editor" ]]; then
        _sw_error "no editor configured"
        echo "Set \$VISUAL or \$EDITOR, or use: sw open -e <editor>" >&2
        return 1
    fi

    # Open directory
    "$editor" "$target_dir"
}

# sw help: Show help message
_sw_cmd_help() {
    cat <<'EOF'
Sideways - Git Worktree Helper

Usage: sw <command> [options]

From base directory only:
  add [-s] [-o] <branch>       Create worktree at ../<project>-worktrees/<branch>
                               Uses existing branch or creates new one
                               -s, --switch: cd into worktree after creation
                               -o, --open: open worktree in editor
                               Copies/symlinks gitignored files (see below)
  rm [-d|-D] [branch]          Remove worktree (branch kept by default)
                               -d: also delete branch (if merged)
                               -D: also delete branch (force)
                               No branch: interactive selection via fzf
  prune                        Remove stale worktree references

From worktree subdirectory only:
  base                         Jump back to base
  rebase <branch>              Fetch and rebase onto origin/<branch>
  done                         Remove worktree (keep branch), cd to base

Anywhere:
  cd [branch]                  Switch to worktree (or interactive via fzf)
  list, ls                     List all worktrees
  info                         Show current branch, path, location
  open [-e <editor>] [branch]  Open worktree in editor (or interactive via fzf)
  --help, -h                   Show this help message
  --version, -V                Show version

Config files (each works independently):
  .swcopy                      Gitignored file patterns to copy to worktrees
                               (e.g., .env, node_modules/)
  .swsymlink                   Gitignored file patterns to symlink to worktrees
                               (e.g., CLAUDE.local.md)
                               Same item in both files is an error
EOF
}

# =============================================================================
# ROUTER - Main entry point
# =============================================================================

sw() {
    local cmd="$1"
    shift 2>/dev/null

    # Compute project-specific worktrees directory
    local repo_root base_dir proj_name worktrees_dir_rel worktrees_dir_abs
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        _sw_error "not in a git repository"
        return 1
    }

    # Get base directory (first worktree is always the main one)
    base_dir=$(_sw_get_base_dir)

    # Compute paths relative to base (works from anywhere)
    proj_name=$(basename "$base_dir")
    worktrees_dir_rel="../${proj_name}-worktrees"                    # relative (for add/rm from base)
    worktrees_dir_abs="$(dirname "$base_dir")/${proj_name}-worktrees" # absolute (for cd from anywhere)

    # Route to command handler
    case "$cmd" in
        add)      _sw_cmd_add "$repo_root" "$base_dir" "$worktrees_dir_rel" "$worktrees_dir_abs" "$@" ;;
        cd)       _sw_cmd_cd "$worktrees_dir_abs" "$@" ;;
        rm)       _sw_cmd_rm "$repo_root" "$base_dir" "$worktrees_dir_rel" "$worktrees_dir_abs" "$@" ;;
        list|ls)  _sw_cmd_list "$repo_root" "$base_dir" ;;
        prune)    _sw_cmd_prune ;;
        base)     _sw_cmd_base "$repo_root" "$base_dir" ;;
        info)     _sw_cmd_info ;;
        rebase)   _sw_cmd_rebase "$@" ;;
        done)     _sw_cmd_done ;;
        open)     _sw_cmd_open "$base_dir" "$worktrees_dir_abs" "$@" ;;
        help|-h|--help|"")
                  _sw_cmd_help ;;
        -V|--version)
                  echo "sideways $SW_VERSION" ;;
        *)
            echo "Unknown command: $cmd" >&2
            echo "Run 'sw help' for usage" >&2
            return 1
            ;;
    esac
}
