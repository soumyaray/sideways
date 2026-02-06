# Sideways - Git Worktree Helper
#
# Source this file in ~/.zshrc or ~/.bashrc:
#
#   # Sideways - git worktree helper
#   source ~/path/to/worktrees.sh

SW_VERSION="0.5.0"

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

# Copy gitignored files from base to new worktree
# Args: $1 = base_dir, $2 = worktree_path
_sw_copy_gitignored() {
    local base_dir="$1"
    local wt_path="$2"
    local swcopy_file="$base_dir/.swcopy"
    local swsymlink_file="$base_dir/.swsymlink"
    local copied=()
    local symlinked=()

    # If no .swcopy file, don't copy anything
    [[ ! -f "$swcopy_file" ]] && return 0

    # Load .swcopy patterns
    local swcopy_patterns=()
    local p
    while IFS= read -r p; do
        swcopy_patterns+=("$p")
    done < <(_sw_read_patterns "$swcopy_file")

    # Load .swsymlink patterns if file exists
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
        shopt -s nullglob dotglob
    elif [[ -n "$ZSH_VERSION" ]]; then
        local had_nullglob=false had_dotglob=false
        [[ -o nullglob ]] && had_nullglob=true
        [[ -o globdots ]] && had_dotglob=true
        setopt NULL_GLOB GLOB_DOTS
    fi

    # Track processed items to avoid duplicates across overlapping patterns
    local processed=""

    local pattern
    for pattern in "${swcopy_patterns[@]}"; do
        if [[ "$pattern" == */ ]]; then
            # Directory pattern (e.g., "logs/", "backend_app/config/")
            local dir="${pattern%/}"

            # Skip if already processed
            case "$processed" in *"|$dir/|"*) continue ;; esac

            # Verify directory exists and is gitignored (or contains gitignored files)
            if [[ -d "$dir" ]] && \
               { git check-ignore -q "$dir" 2>/dev/null || \
                 [[ -n "$(git ls-files --others --ignored --exclude-standard "$dir" 2>/dev/null | head -1)" ]]; }; then

                processed="$processed|$dir/|"

                # Create parent directories for nested paths
                mkdir -p "$(dirname "$wt_path/$dir")"

                if _sw_should_symlink "$dir" "${swsymlink_patterns[@]}"; then
                    ln -s "$base_dir/$dir" "$wt_path/$dir" 2>/dev/null && symlinked+=("$dir/")
                elif [[ -d "$wt_path/$dir" ]]; then
                    # Target exists (e.g., git created it for tracked files) — merge contents
                    cp -R "$dir/." "$wt_path/$dir/" 2>/dev/null && copied+=("$dir/")
                else
                    cp -R "$dir" "$wt_path/$dir" 2>/dev/null && copied+=("$dir/")
                fi
            fi
        else
            # File pattern with potential wildcards (e.g., "logs/*.txt", ".env")
            local expanded_files=()
            local f
            for f in $pattern; do
                [[ -f "$f" ]] && expanded_files+=("$f")
            done

            # Skip if no files matched
            [[ ${#expanded_files[@]} -eq 0 ]] && continue

            # Batch-verify which files are gitignored (single git subprocess)
            local gitignored_files
            gitignored_files=$(printf '%s\n' "${expanded_files[@]}" | git check-ignore --stdin 2>/dev/null)

            # Process each gitignored file
            local file
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue

                # Skip if already processed (deduplication)
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

    # Output copied items
    if [[ ${#copied[@]} -gt 0 ]]; then
        echo "Copied: ${copied[*]}"
    fi

    # Output symlinked items
    if [[ ${#symlinked[@]} -gt 0 ]]; then
        echo "Symlinked: ${symlinked[*]}"
    fi
}

# =============================================================================
# VIEW LAYER - Output formatting
# =============================================================================

# Standardized error output
_sw_error() {
    echo "sw: $*" >&2
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
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        # Branch exists, use it
        if ! git worktree add "$wt_path" "$branch"; then
            return 1
        fi
        echo "Created: $wt_path (existing branch $branch)"
    else
        # Create new branch
        if ! git worktree add "$wt_path" -b "$branch"; then
            return 1
        fi
        echo "Created: $wt_path (new branch $branch)"
    fi

    # Copy gitignored files to new worktree
    _sw_copy_gitignored "$base_dir" "$wt_abs_path"

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
        selected=$(git worktree list | fzf | awk '{print $1}')
        [[ -n "$selected" ]] && cd "$selected"
    else
        echo "Interactive mode requires fzf. Install it with:" >&2
        echo "  brew install fzf    # macOS" >&2
        echo "  apt install fzf     # Debian/Ubuntu" >&2
        echo "  winget install fzf  # Windows" >&2
        echo "Or provide a branch name: sw cd <branch-name>" >&2
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
        _sw_error "Usage: sw rm [-d|-D] <branch-name>"
        return 1
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
        # Current directory
        target_dir=$(git rev-parse --show-toplevel)
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
                               Copies gitignored files (see .swcopy)
  rm [-d|-D] <branch>          Remove worktree (branch kept by default)
                               -d: also delete branch (if merged)
                               -D: also delete branch (force)
  prune                        Remove stale worktree references

From worktree subdirectory only:
  base                         Jump back to base
  rebase <branch>              Fetch and rebase onto origin/<branch>
  done                         Remove worktree (keep branch), cd to base

Anywhere:
  cd [branch]                  Switch to worktree (or interactive via fzf)
  list, ls                     List all worktrees
  info                         Show current branch, path, location
  open [-e <editor>] [branch]  Open worktree in editor ($VISUAL, $EDITOR, or -e)
  --help, -h                   Show this help message
  --version, -V                Show version

Config files:
  .swcopy                      Patterns for gitignored files to copy
                               (e.g., .env, CLAUDE.local.md)
  .swsymlink                   Patterns to symlink instead of copy
                               (e.g., CLAUDE.local.md)
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
