#!/usr/bin/env bash
# Git Worktree Utilities
# Source this file in your shell config to enable worktree commands.
#
# Required environment variables:
#   WORKTREE_BASE       - Directory containing bare repos (e.g., ~/worktrees)
#   CROSS_REPO_BASE     - Directory for cross-repo task symlinks (e.g., ~/cross-repo-tasks)
#
# Optional:
#   WT_DEFAULT_BRANCH_OVERRIDES - Associative array of repo->branch overrides
#     Example: declare -A WT_DEFAULT_BRANCH_OVERRIDES=([comfyui]=master)

# Ensure required vars are set
: "${WORKTREE_BASE:?WORKTREE_BASE must be set}"
: "${CROSS_REPO_BASE:?CROSS_REPO_BASE must be set}"

# Convert branch name to safe directory name (feature/foo -> feature__foo)
_wt_branch_to_dir() {
    echo "${1//\//__}"
}

# Convert directory name back to branch name (feature__foo -> feature/foo)
_wt_dir_to_branch() {
    echo "${1//__//}"
}

# Helper to get default branch for a repo
_wt_default_branch() {
    local repo
    repo=$(echo "$1" | tr '[:upper:]' '[:lower:]')  # lowercase (zsh/bash compatible)
    local repo_path="$WORKTREE_BASE/$repo"
    
    # Check for manual override first
    if [[ -n "${WT_DEFAULT_BRANCH_OVERRIDES[$repo]:-}" ]]; then
        echo "${WT_DEFAULT_BRANCH_OVERRIDES[$repo]}"
        return
    fi
    
    # Try to auto-detect from origin/HEAD
    if [[ -d "$repo_path/.bare" ]]; then
        local detected
        detected=$(git -C "$repo_path/.bare" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
        if [[ -n "$detected" ]]; then
            echo "$detected"
            return
        fi
    fi
    
    # Fallback to main
    echo "main"
}

# Clone a remote repo into the worktree structure
# Usage: wt-clone <git-url> [local-name]
wt-clone() {
    local url="$1"
    local name="$2"

    if [[ -z "$url" ]]; then
        echo "Usage: wt-clone <git-url> [local-name]"
        echo "Example: wt-clone git@github.com:user/repo.git"
        echo "Example: wt-clone git@github.com:user/repo.git my-repo"
        return 1
    fi

    # Extract repo name from URL if not provided
    if [[ -z "$name" ]]; then
        name=$(basename "$url" .git)
    fi

    local repo_path="$WORKTREE_BASE/$name"

    if [[ -d "$repo_path" ]]; then
        echo "Error: $repo_path already exists"
        return 1
    fi

    echo "Cloning $url into $repo_path..."
    mkdir -p "$repo_path"
    cd "$repo_path" || return 1

    # Clone as bare repo
    git clone --bare "$url" .bare

    # Create .git pointer
    echo "gitdir: ./.bare" > .git

    # Configure fetch to get all branches
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    # Fetch all branches
    git fetch origin

    # Detect default branch
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    if [[ -z "$default_branch" ]]; then
        # Try to detect from remote
        default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
    fi
    if [[ -z "$default_branch" ]]; then
        default_branch="main"
    fi

    # Create default branch worktree
    git worktree add "$default_branch" "$default_branch"

    cd "$default_branch" || return 1
    echo ""
    echo "✓ Cloned $name (default branch: $default_branch)"
    echo "  Repo path: $repo_path"
    echo "  Worktree:  $repo_path/$default_branch"
}

# Initialize a new local repo in the worktree structure
# Usage: wt-init <name> [default-branch]
wt-init() {
    local name="$1"
    local default_branch="${2:-main}"

    if [[ -z "$name" ]]; then
        echo "Usage: wt-init <name> [default-branch]"
        echo "Example: wt-init my-project"
        echo "Example: wt-init my-project develop"
        return 1
    fi

    local repo_path="$WORKTREE_BASE/$name"

    if [[ -d "$repo_path" ]]; then
        echo "Error: $repo_path already exists"
        return 1
    fi

    echo "Initializing new repo at $repo_path..."
    mkdir -p "$repo_path"
    cd "$repo_path" || return 1

    # Initialize bare repo
    git init --bare .bare

    # Create .git pointer
    echo "gitdir: ./.bare" > .git

    # Set default branch
    git symbolic-ref HEAD "refs/heads/$default_branch"

    # Create initial worktree with first commit
    git worktree add "$default_branch"
    cd "$default_branch" || return 1

    # Create initial commit so the branch exists
    git commit --allow-empty -m "Initial commit"

    echo ""
    echo "✓ Initialized $name (default branch: $default_branch)"
    echo "  Repo path: $repo_path"
    echo "  Worktree:  $repo_path/$default_branch"
    echo ""
    echo "Next: Add a remote with 'git remote add origin <url>'"
}

# List available repos (directories with .bare inside)
_wt_list_repos() {
    local dir
    for dir in "$WORKTREE_BASE"/*/; do
        if [[ -d "${dir}.bare" ]]; then
            basename "$dir"
        fi
    done
}

# Create a new feature worktree
# Usage: wt-new <repo> <branch-name>
wt-new() {
    local repo="$1"
    local branch="$2"

    if [[ -z "$repo" || -z "$branch" ]]; then
        echo "Usage: wt-new <repo> <branch-name>"
        echo "Available repos: $(_wt_list_repos | tr '\n' ' ')"
        return 1
    fi

    local repo_path="$WORKTREE_BASE/$repo"
    local default_branch
    default_branch=$(_wt_default_branch "$repo")
    local branch_dir
    branch_dir=$(_wt_branch_to_dir "$branch")

    if [[ ! -d "$repo_path/.bare" ]]; then
        echo "Error: Repository '$repo' not found at $repo_path"
        return 1
    fi

    cd "$repo_path" || return 1

    # Update default branch first (worktree dir matches branch name)
    local default_branch_dir
    default_branch_dir=$(_wt_branch_to_dir "$default_branch")
    git -C "$default_branch_dir" fetch origin && git -C "$default_branch_dir" reset --hard origin/"$default_branch"

    # Create worktree from default branch
    git worktree add "$branch_dir" -b "$branch" "$default_branch"

    cd "$branch_dir" || return 1
    echo "Created worktree: $repo_path/$branch_dir (branch: $branch)"
}

# Continue work on an existing remote branch
# Usage: wt-continue <repo> <branch-name>
wt-continue() {
    local repo="$1"
    local branch="$2"

    if [[ -z "$repo" || -z "$branch" ]]; then
        echo "Usage: wt-continue <repo> <branch-name>"
        echo "Creates a worktree tracking origin/<branch-name>"
        return 1
    fi

    local repo_path="$WORKTREE_BASE/$repo"
    local branch_dir
    branch_dir=$(_wt_branch_to_dir "$branch")

    if [[ ! -d "$repo_path/.bare" ]]; then
        echo "Error: Repository '$repo' not found at $repo_path"
        return 1
    fi

    local default_branch
    default_branch=$(_wt_default_branch "$repo")
    local default_branch_dir
    default_branch_dir=$(_wt_branch_to_dir "$default_branch")

    cd "$repo_path" || return 1

    # Fetch to ensure we have the latest
    git -C "$default_branch_dir" fetch origin

    # Check if remote branch exists
    if ! git show-ref --verify --quiet refs/remotes/origin/"$branch"; then
        echo "Error: Remote branch 'origin/$branch' does not exist"
        echo "Available remote branches:"
        git branch -r | grep -v HEAD | head -10
        return 1
    fi

    # Delete stale local branch if it exists (orphaned from previous worktree)
    if git show-ref --verify --quiet refs/heads/"$branch"; then
        echo "Deleting stale local branch '$branch'..."
        git branch -D "$branch"
    fi

    # Create worktree with a local branch tracking the remote
    git worktree add -b "$branch" "$branch_dir" "origin/$branch"

    cd "$branch_dir" || return 1
    echo "Created worktree: $repo_path/$branch_dir (tracking origin/$branch)"
}

# Remove a feature worktree
# Usage: wt-rm <repo> <branch-name> [--yes]
#        wt-rm . [--yes]             (auto-detect from current directory)
wt-rm() {
    local repo=""
    local branch=""
    local delete_branch=false

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --yes|-y)
                delete_branch=true
                ;;
            *)
                if [[ -z "$repo" ]]; then
                    repo="$arg"
                elif [[ -z "$branch" ]]; then
                    branch="$arg"
                fi
                ;;
        esac
    done

    # Auto-detect repo and branch if "." is passed
    if [[ "$repo" == "." ]]; then
        local current_dir
        current_dir=$(pwd)
        if [[ "$current_dir" != "$WORKTREE_BASE/"* ]]; then
            echo "Error: Not in a worktree directory"
            return 1
        fi
        # Strip WORKTREE_BASE prefix and parse repo/branch_dir
        local rel_path="${current_dir#"$WORKTREE_BASE"/}"
        repo="${rel_path%%/*}"
        local branch_dir="${rel_path#*/}"
        # Handle being in repo root (no branch)
        if [[ "$branch_dir" == "$repo" || -z "$branch_dir" ]]; then
            echo "Error: Not in a worktree (in repo root)"
            return 1
        fi
        # Convert dir name back to branch name
        branch=$(_wt_dir_to_branch "$branch_dir")
        echo "Detected: $repo / $branch"
    fi

    if [[ -z "$repo" || -z "$branch" ]]; then
        echo "Usage: wt-rm <repo> <branch-name>"
        echo "       wt-rm .  (auto-detect from current directory)"
        return 1
    fi

    local default_branch
    default_branch=$(_wt_default_branch "$repo")
    if [[ "$branch" == "$default_branch" || "$branch" == "main" || "$branch" == "master" ]]; then
        echo "Error: Cannot remove the default branch worktree"
        return 1
    fi

    local repo_path="$WORKTREE_BASE/$repo"
    local branch_dir
    branch_dir=$(_wt_branch_to_dir "$branch")
    local worktree_path="$repo_path/$branch_dir"
    local default_branch_dir
    default_branch_dir=$(_wt_branch_to_dir "$default_branch")

    # Check if we're inside the worktree we're trying to remove
    local current_dir
    current_dir=$(pwd)
    if [[ "$current_dir" == "$worktree_path" || "$current_dir" == "$worktree_path/"* ]]; then
        echo "Currently in worktree, moving to $repo/..."
    fi

    cd "$repo_path" || return 1
    git worktree remove "$branch_dir"

    # Optionally delete the branch too
    if [[ "$delete_branch" == true ]]; then
        git branch -D "$branch"
    elif [[ -t 0 ]]; then
        # Interactive mode: prompt user
        printf "Delete branch '%s' as well? [y/N] " "$branch"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            git branch -D "$branch"
        fi
    else
        # Non-interactive without --yes: skip branch deletion
        echo "Skipping branch deletion (non-interactive mode, use --yes to delete)"
    fi
}

# List all worktrees for a repo
# Usage: wt-ls <repo>
wt-ls() {
    local repo="$1"

    if [[ -z "$repo" ]]; then
        echo "Usage: wt-ls <repo>"
        echo "Available repos: $(_wt_list_repos | tr '\n' ' ')"
        return 1
    fi

    local repo_path="$WORKTREE_BASE/$repo"

    cd "$repo_path" || return 1
    git worktree list
}

# Quick cd into a worktree
# Usage: wt-cd <repo> [branch]
wt-cd() {
    local repo="$1"
    local branch="${2:-}"

    if [[ -z "$repo" ]]; then
        echo "Usage: wt-cd <repo> [branch]"
        return 1
    fi

    if [[ -n "$branch" ]]; then
        local branch_dir
        branch_dir=$(_wt_branch_to_dir "$branch")
        cd "$WORKTREE_BASE/$repo/$branch_dir" || return 1
    else
        cd "$WORKTREE_BASE/$repo" || return 1
    fi
}

# Update main branch for a repo
# Usage: wt-update <repo>
wt-update() {
    local repo="$1"

    if [[ -z "$repo" ]]; then
        echo "Usage: wt-update <repo>"
        return 1
    fi

    local repo_path="$WORKTREE_BASE/$repo"
    local default_branch
    default_branch=$(_wt_default_branch "$repo")
    local default_branch_dir
    default_branch_dir=$(_wt_branch_to_dir "$default_branch")

    cd "$repo_path/$default_branch_dir" || return 1
    git fetch origin
    git reset --hard origin/"$default_branch"
    echo "Updated $repo/$default_branch to origin/$default_branch"
}

# Rebase current feature branch onto main
# Run from within a feature worktree
# Usage: wt-rebase
wt-rebase() {
    local current_dir
    current_dir=$(pwd)
    local repo_root
    repo_root=$(dirname "$current_dir")
    local repo_name
    repo_name=$(basename "$repo_root")
    local default_branch
    default_branch=$(_wt_default_branch "$repo_name")
    local default_branch_dir
    default_branch_dir=$(_wt_branch_to_dir "$default_branch")

    cd "$repo_root/$default_branch_dir" || return 1
    git fetch origin
    git reset --hard origin/"$default_branch"

    cd "$current_dir" || return 1
    git rebase -i "$default_branch"
}

# ===========================
# Cross-repo task helpers
# ===========================

# Create worktrees across multiple repos for a single task
# Usage: wt-multi-new <branch-name> <repo1> <repo2> ...
wt-multi-new() {
    local branch="$1"
    shift
    local repos=("$@")

    if [[ -z "$branch" || ${#repos[@]} -eq 0 ]]; then
        echo "Usage: wt-multi-new <branch-name> <repo1> <repo2> ..."
        echo "Example: wt-multi-new auth-fix cloud frontend api"
        return 1
    fi

    local branch_dir
    branch_dir=$(_wt_branch_to_dir "$branch")
    local task_dir="$CROSS_REPO_BASE/$branch_dir"
    mkdir -p "$task_dir"

    for repo in "${repos[@]}"; do
        echo "Creating worktree for $repo..."

        # Create the worktree
        (cd "$WORKTREE_BASE/$repo" && wt-new "$repo" "$branch" >/dev/null 2>&1) || {
            # If it already exists, that's fine
            if [[ -d "$WORKTREE_BASE/$repo/$branch_dir" ]]; then
                echo "  Worktree already exists"
            else
                echo "  Failed to create worktree for $repo"
                continue
            fi
        }

        # Create symlink in task directory
        ln -sf "$WORKTREE_BASE/$repo/$branch_dir" "$task_dir/$repo"
        echo "  ✓ $repo"
    done

    echo ""
    echo "Task directory: $task_dir"
    ls -la "$task_dir"
    cd "$task_dir" || return 1
}

# Remove a multi-repo task (archives instead of deleting)
# Usage: wt-multi-rm <branch-name>
wt-multi-rm() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        echo "Usage: wt-multi-rm <branch-name>"
        return 1
    fi

    local branch_dir
    branch_dir=$(_wt_branch_to_dir "$branch")
    local task_dir="$CROSS_REPO_BASE/$branch_dir"

    if [[ ! -d "$task_dir" ]]; then
        echo "Task '$branch' not found at $task_dir"
        return 1
    fi

    echo "Archiving task: $branch"

    # Remove symlinks and their corresponding worktrees
    for link in "$task_dir"/*; do
        if [[ -L "$link" ]]; then
            local repo
            repo=$(basename "$link")
            echo "Removing worktree: $repo/$branch"
            # Remove symlink first
            rm "$link"
            # Remove the actual worktree
            wt-rm "$repo" "$branch" <<< "n"  # Don't delete branch by default
        fi
    done

    # Check if there are any real files left (excluding .DS_Store)
    local has_files=false
    for f in "$task_dir"/*; do
        if [[ -e "$f" && "$(basename "$f")" != ".DS_Store" ]]; then
            has_files=true
            break
        fi
    done
    
    if [[ "$has_files" == true ]]; then
        # Archive the task directory (contains non-symlink files like notes)
        mkdir -p "$CROSS_REPO_ARCHIVE"
        local archive_dest="$CROSS_REPO_ARCHIVE/$branch_dir"
        
        # Handle naming collision by appending .N suffix
        if [[ -e "$archive_dest" ]]; then
            local n=1
            while [[ -e "${archive_dest}.${n}" ]]; do
                ((n++))
            done
            archive_dest="${archive_dest}.${n}"
        fi
        
        mv "$task_dir" "$archive_dest"
        echo "✓ Task archived to: $archive_dest"
    else
        # No meaningful files, just remove the directory
        rm -rf "$task_dir"
        echo "✓ Task removed"
    fi
}

# List all cross-repo tasks
# Usage: wt-multi-ls
wt-multi-ls() {
    if [[ ! -d "$CROSS_REPO_BASE" ]]; then
        echo "No cross-repo tasks found"
        return
    fi

    echo "Cross-repo tasks:"
    for task_dir in "$CROSS_REPO_BASE"/*/; do
        if [[ -d "$task_dir" ]]; then
            local task
            task=$(basename "$task_dir")
            local repos
            # shellcheck disable=SC2012
            repos=$(ls "$task_dir" 2>/dev/null | tr '\n' ' ')
            echo "  $task: $repos"
        fi
    done
}

# cd into a cross-repo task directory
# Usage: wt-multi-cd <branch-name>
wt-multi-cd() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        echo "Usage: wt-multi-cd <branch-name>"
        return 1
    fi

    local branch_dir
    branch_dir=$(_wt_branch_to_dir "$branch")
    cd "$CROSS_REPO_BASE/$branch_dir" || return 1
}
