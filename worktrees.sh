# Sideways - Git Worktree Helper
#
# Source this file in ~/.zshrc or ~/.bashrc:
#
#   # Sideways - git worktree helper
#   source ~/path/to/worktrees.sh

sw() {
    local cmd="$1"
    shift 2>/dev/null

    # Compute project-specific worktrees directory
    local repo_root base_dir proj_name worktrees_dir_rel worktrees_dir_abs
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "sw: not in a git repository" >&2
        return 1
    }

    # Get base directory (first worktree is always the main one)
    base_dir=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

    # Compute paths relative to base (works from anywhere)
    proj_name=$(basename "$base_dir")
    worktrees_dir_rel="../${proj_name}-worktrees"                    # relative (for add/rm from base)
    worktrees_dir_abs="$(dirname "$base_dir")/${proj_name}-worktrees" # absolute (for cd from anywhere)

    case "$cmd" in
        add)
            # Guard: must be in base directory
            if [[ "$repo_root" != "$base_dir" ]]; then
                echo "sw: add must be run from base directory" >&2
                echo "Run 'sw base' first, then 'sw add $*'" >&2
                return 1
            fi

            local switch=false
            while [[ "$1" == -* ]]; do
                case "$1" in
                    -s|--switch) switch=true; shift ;;
                    *) echo "Unknown option: $1" >&2; return 1 ;;
                esac
            done

            local branch="$1"
            if [[ -z "$branch" ]]; then
                echo "Usage: sw add [-s|--switch] <branch-name>" >&2
                return 1
            fi

            local path="$worktrees_dir_rel/$branch"
            if git show-ref --verify --quiet "refs/heads/$branch"; then
                # Branch exists, use it
                if ! git worktree add "$path" "$branch"; then
                    return 1
                fi
                echo "Created: $path (existing branch $branch)"
            else
                # Create new branch
                if ! git worktree add "$path" -b "$branch"; then
                    return 1
                fi
                echo "Created: $path (new branch $branch)"
            fi

            if $switch; then
                cd "$path"
            fi
            ;;

        cd)
            local branch="$1"
            if [[ -n "$branch" ]]; then
                cd "$worktrees_dir_abs/$branch"
            elif command -v fzf &>/dev/null; then
                local path
                path=$(git worktree list | fzf | awk '{print $1}')
                [[ -n "$path" ]] && cd "$path"
            else
                echo "Interactive mode requires fzf. Install it with:" >&2
                echo "  brew install fzf    # macOS" >&2
                echo "  apt install fzf     # Debian/Ubuntu" >&2
                echo "  winget install fzf  # Windows" >&2
                echo "Or provide a branch name: sw cd <branch-name>" >&2
                return 1
            fi
            ;;

        rm)
            # Guard: must be in base directory
            if [[ "$repo_root" != "$base_dir" ]]; then
                echo "sw: rm must be run from base directory" >&2
                echo "Run 'sw base' first, then 'sw rm $*'" >&2
                return 1
            fi

            local delete_flag=""
            while [[ "$1" == -* ]]; do
                case "$1" in
                    -d) delete_flag="-d"; shift ;;
                    -D) delete_flag="-D"; shift ;;
                    *) echo "Unknown option: $1" >&2; return 1 ;;
                esac
            done

            local branch="$1"
            if [[ -z "$branch" ]]; then
                echo "Usage: sw rm [-d|-D] <branch-name>" >&2
                return 1
            fi

            local path="$worktrees_dir_rel/$branch"
            local abs_path="$worktrees_dir_abs/$branch"

            # Guard: check for uncommitted changes
            if [[ -n "$(git -C "$abs_path" status --porcelain 2>/dev/null)" ]]; then
                echo "sw: worktree '$branch' has uncommitted changes" >&2
                echo "Commit or stash changes before removing" >&2
                return 1
            fi

            if ! git worktree remove "$path"; then
                return 1
            fi
            echo "Removed worktree: $path"

            if [[ -n "$delete_flag" ]]; then
                if git branch "$delete_flag" "$branch" 2>/dev/null; then
                    echo "Deleted branch: $branch"
                else
                    echo "Branch $branch not fully merged. Use -D to force delete." >&2
                fi
            fi
            ;;

        list|ls)
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
                            if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
                                dirty="[modified]"
                            else
                                dirty=""
                            fi

                            printf "%s %-19s %-10s %s  %s\n" "$marker" "$wt_branch" "$location" "$wt_commit" "$dirty"
                        fi
                        wt_path="" wt_commit="" wt_branch=""
                        ;;
                esac
            done < <(git worktree list --porcelain; echo)
            ;;

        prune)
            git worktree prune
            echo "Pruned stale worktree references"
            ;;

        base)
            # Jump back to base
            if [[ "$repo_root" == "$base_dir" ]]; then
                echo "Already in base directory: $base_dir"
                return 0
            fi
            cd "$base_dir"
            ;;

        info)
            local current_path current_branch base_dir location
            current_path=$(git rev-parse --show-toplevel)
            current_branch=$(git branch --show-current)
            base_dir=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

            if [[ "$current_path" == "$base_dir" ]]; then
                location="base"
            else
                location="worktree"
            fi

            echo "Branch:   $current_branch"
            echo "Path:     $current_path"
            echo "Location: $location"
            ;;

        rebase)
            # Fetch and rebase current branch onto specified branch
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
            ;;

        done)
            # Remove current worktree (keep branch), cd to base
            local current_path base_dir
            current_path=$(git rev-parse --show-toplevel)
            base_dir=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

            if [[ "$current_path" == "$base_dir" ]]; then
                echo "sw: not in a worktree (already in base directory)" >&2
                return 1
            fi

            # Guard: check for uncommitted changes
            if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
                echo "sw: current worktree has uncommitted changes" >&2
                echo "Commit or stash changes before removing" >&2
                return 1
            fi

            # Move to base first, then remove worktree
            cd "$base_dir" || return 1
            if ! git worktree remove "$current_path"; then
                return 1
            fi
            echo "Removed worktree: $current_path"
            echo "Branch preserved. Now in base directory: $base_dir"
            ;;

        help|-h|--help|"")
            cat <<'EOF'
Sideways - Git Worktree Helper

Usage: sw <command> [options]

From base directory only:
  add [-s|--switch] <branch>   Create worktree at ../<project>-worktrees/<branch>
                               Uses existing branch or creates new one
                               -s, --switch: cd into worktree after creation
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
  --help, -h                   Show this help message
EOF
            ;;

        *)
            echo "Unknown command: $cmd" >&2
            echo "Run 'sw help' for usage" >&2
            return 1
            ;;
    esac
}
