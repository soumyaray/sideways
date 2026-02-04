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
    local repo_root main_wt proj_name wt_base wt_dir
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "wt: not in a git repository" >&2
        return 1
    }

    # Get base folder (first worktree is always the main one)
    main_wt=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

    # Compute paths relative to base (works from anywhere)
    proj_name=$(basename "$main_wt")
    wt_base="../${proj_name}-worktrees"                              # relative (for add/rm from base)
    wt_dir="$(dirname "$main_wt")/${proj_name}-worktrees"            # absolute (for cd from anywhere)

    case "$cmd" in
        add)
            # Guard: must be in base folder
            if [[ "$repo_root" != "$main_wt" ]]; then
                echo "wt: add must be run from base folder" >&2
                echo "Run 'wt base' first, then 'wt add $*'" >&2
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
                cd "$wt_dir/$branch"
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
            # Guard: must be in base folder
            if [[ "$repo_root" != "$main_wt" ]]; then
                echo "wt: rm must be run from base folder" >&2
                echo "Run 'wt base' first, then 'wt rm $*'" >&2
                return 1
            fi

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

        base)
            # Jump back to base
            local main_wt
            main_wt=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
            if [[ -z "$main_wt" ]]; then
                echo "wt: could not find base" >&2
                return 1
            fi
            cd "$main_wt"
            ;;

        info)
            local current_path current_branch main_wt location
            current_path=$(git rev-parse --show-toplevel)
            current_branch=$(git branch --show-current)
            main_wt=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

            if [[ "$current_path" == "$main_wt" ]]; then
                location="base"
            else
                location="worktree"
            fi

            echo "Branch:   $current_branch"
            echo "Path:     $current_path"
            echo "Location: $location"
            ;;

        rebase)
            # Fetch and rebase current branch onto main
            local main_branch
            if git show-ref --verify --quiet refs/heads/main; then
                main_branch="main"
            elif git show-ref --verify --quiet refs/heads/master; then
                main_branch="master"
            else
                echo "wt: could not find main or master branch" >&2
                return 1
            fi

            echo "Fetching from origin..."
            if ! git fetch; then
                return 1
            fi
            echo "Rebasing onto origin/$main_branch..."
            git rebase "origin/$main_branch"
            ;;

        done)
            # Remove current worktree (keep branch), cd to base
            local current_path main_wt
            current_path=$(git rev-parse --show-toplevel)
            main_wt=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

            if [[ "$current_path" == "$main_wt" ]]; then
                echo "wt: not in a worktree (already in base)" >&2
                return 1
            fi

            # Move to base first, then remove worktree
            cd "$main_wt" || return 1
            if ! git worktree remove "$current_path"; then
                return 1
            fi
            echo "Removed worktree: $current_path"
            echo "Branch preserved. Now in base: $main_wt"
            ;;

        help|-h|--help|"")
            cat <<'EOF'
Git Worktree Helper

Usage: wt <command> [options]

From base folder only:
  add [-s|--switch] <branch>   Create worktree at ../<project>-worktrees/<branch>
                               Uses existing branch or creates new one
                               -s, --switch: cd into worktree after creation
  rm <branch>                  Remove worktree and delete branch
  prune                        Remove stale worktree references

From worktree subfolder only:
  base                         Jump back to base
  rebase                       Fetch and rebase onto main
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
            echo "Run 'wt help' for usage" >&2
            return 1
            ;;
    esac
}
