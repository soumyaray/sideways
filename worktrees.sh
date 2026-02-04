# Git Worktree Helper Functions
#
# Source this file in ~/.zshrc or ~/.bashrc:
#
#   # Git worktree helper
#   source ~/path/to/worktrees.sh

wt() {
    local cmd="$1"
    shift 2>/dev/null

    # Compute project-specific worktrees directory
    local repo_root proj_name wt_base
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "wt: not in a git repository" >&2
        return 1
    }
    proj_name=$(basename "$repo_root")
    wt_base="../${proj_name}-worktrees"

    case "$cmd" in
        add)
            local switch=false
            while [[ "$1" == -* ]]; do
                case "$1" in
                    -s|--switch) switch=true; shift ;;
                    *) echo "Unknown option: $1" >&2; return 1 ;;
                esac
            done

            local branch="$1"
            if [[ -z "$branch" ]]; then
                echo "Usage: wt add [-s|--switch] <branch-name>" >&2
                return 1
            fi

            local path="$wt_base/$branch"
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
                cd "$wt_base/$branch"
            elif command -v fzf &>/dev/null; then
                local path
                path=$(git worktree list | fzf | awk '{print $1}')
                [[ -n "$path" ]] && cd "$path"
            else
                echo "Interactive mode requires fzf. Install it with:" >&2
                echo "  brew install fzf    # macOS" >&2
                echo "  apt install fzf     # Debian/Ubuntu" >&2
                echo "  winget install fzf  # Windows" >&2
                echo "Or provide a branch name: wt cd <branch-name>" >&2
                return 1
            fi
            ;;

        rm)
            local branch="$1"
            if [[ -z "$branch" ]]; then
                echo "Usage: wt rm <branch-name>" >&2
                return 1
            fi

            local path="$wt_base/$branch"
            if ! git worktree remove "$path"; then
                return 1
            fi
            git branch -d "$branch" 2>/dev/null
            echo "Removed: $path and branch $branch"
            ;;

        list|ls)
            git worktree list
            ;;

        prune)
            git worktree prune
            echo "Pruned stale worktree references"
            ;;

        help|-h|--help|"")
            cat <<'EOF'
Git Worktree Helper

Usage: wt <command> [options]

Commands:
  add [-s|--switch] <branch>   Create worktree at ../<project>-worktrees/<branch>
                               Uses existing branch or creates new one
                               -s, --switch: cd into worktree after creation

  cd [branch]                  Switch to a worktree
                               With branch: cd to ../<project>-worktrees/<branch>
                               Without: interactive selection via fzf

  rm <branch>                  Remove worktree and delete branch

  list, ls                     List all worktrees

  prune                        Remove stale worktree references

  --help, -h                   Show this help message
EOF
            ;;

        *)
            echo "Unknown command: $cmd" >&2
            echo "Run 'wt help' for usage" >&2
            return 1
            ;;
    esac
}
