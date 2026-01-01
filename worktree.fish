# Git Worktree Utilities for Fish shell
# Source this file in your config.fish
#
# Required environment variables:
#   WORKTREE_BASE       - Directory containing bare repos (e.g., ~/worktrees)
#   CROSS_REPO_BASE     - Directory for cross-repo task symlinks (e.g., ~/cross-repo-tasks)

# Convert branch name to safe directory name (feature/foo -> feature__foo)
function _wt_branch_to_dir
    string replace -a '/' '__' $argv[1]
end

# Convert directory name back to branch name (feature__foo -> feature/foo)
function _wt_dir_to_branch
    string replace -a '__' '/' $argv[1]
end

# Helper to get default branch for a repo
function _wt_default_branch
    set -l repo (string lower $argv[1])
    set -l repo_path "$WORKTREE_BASE/$repo"
    
    # Check for manual override first
    # Fish doesn't have associative arrays, so we use a naming convention
    set -l override_var "WT_DEFAULT_BRANCH_$repo"
    if set -q $override_var
        echo $$override_var
        return
    end
    
    # Try to auto-detect from origin/HEAD
    if test -d "$repo_path/.bare"
        set -l detected (git -C "$repo_path/.bare" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
        if test -n "$detected"
            echo $detected
            return
        end
    end
    
    # Fallback to main
    echo "main"
end

# Clone a remote repo into the worktree structure
function wt-clone
    set -l url $argv[1]
    set -l name $argv[2]

    if test -z "$url"
        echo "Usage: wt-clone <git-url> [local-name]"
        echo "Example: wt-clone git@github.com:user/repo.git"
        echo "Example: wt-clone git@github.com:user/repo.git my-repo"
        return 1
    end

    # Extract repo name from URL if not provided
    if test -z "$name"
        set name (basename "$url" .git)
    end

    set -l repo_path "$WORKTREE_BASE/$name"

    if test -d "$repo_path"
        echo "Error: $repo_path already exists"
        return 1
    end

    echo "Cloning $url into $repo_path..."
    mkdir -p "$repo_path"
    cd "$repo_path"

    # Clone as bare repo
    git clone --bare "$url" .bare

    # Create .git pointer
    echo "gitdir: ./.bare" > .git

    # Configure fetch to get all branches
    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    # Fetch all branches
    git fetch origin

    # Detect default branch
    set -l default_branch (git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    if test -z "$default_branch"
        set default_branch (git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
    end
    if test -z "$default_branch"
        set default_branch "main"
    end

    # Create default branch worktree
    git worktree add "$default_branch" "$default_branch"

    cd "$default_branch"
    echo ""
    echo "✓ Cloned $name (default branch: $default_branch)"
    echo "  Repo path: $repo_path"
    echo "  Worktree:  $repo_path/$default_branch"
end

# Initialize a new local repo in the worktree structure
function wt-init
    set -l name $argv[1]
    set -l default_branch $argv[2]
    if test -z "$default_branch"
        set default_branch "main"
    end

    if test -z "$name"
        echo "Usage: wt-init <name> [default-branch]"
        echo "Example: wt-init my-project"
        echo "Example: wt-init my-project develop"
        return 1
    end

    set -l repo_path "$WORKTREE_BASE/$name"

    if test -d "$repo_path"
        echo "Error: $repo_path already exists"
        return 1
    end

    echo "Initializing new repo at $repo_path..."
    mkdir -p "$repo_path"
    cd "$repo_path"

    # Initialize bare repo
    git init --bare .bare

    # Create .git pointer
    echo "gitdir: ./.bare" > .git

    # Set default branch
    git symbolic-ref HEAD "refs/heads/$default_branch"

    # Create initial worktree with first commit
    git worktree add "$default_branch"
    cd "$default_branch"

    # Create initial commit so the branch exists
    git commit --allow-empty -m "Initial commit"

    echo ""
    echo "✓ Initialized $name (default branch: $default_branch)"
    echo "  Repo path: $repo_path"
    echo "  Worktree:  $repo_path/$default_branch"
    echo ""
    echo "Next: Add a remote with 'git remote add origin <url>'"
end

# List available repos
function _wt_list_repos
    for dir in $WORKTREE_BASE/*/
        if test -d "$dir.bare"
            basename $dir
        end
    end
end

# Create a new feature worktree
function wt-new
    set -l repo $argv[1]
    set -l branch $argv[2]

    if test -z "$repo" -o -z "$branch"
        echo "Usage: wt-new <repo> <branch-name>"
        echo "Available repos:" (_wt_list_repos | string join ' ')
        return 1
    end

    set -l repo_path "$WORKTREE_BASE/$repo"
    set -l default_branch (_wt_default_branch "$repo")
    set -l branch_dir (_wt_branch_to_dir "$branch")
    set -l default_branch_dir (_wt_branch_to_dir "$default_branch")

    if not test -d "$repo_path/.bare"
        echo "Error: Repository '$repo' not found at $repo_path"
        return 1
    end

    cd "$repo_path"

    # Update default branch first
    git -C "$default_branch_dir" fetch origin
    and git -C "$default_branch_dir" reset --hard origin/$default_branch

    # Create worktree from default branch
    git worktree add "$branch_dir" -b "$branch" $default_branch

    cd "$branch_dir"
    echo "Created worktree: $repo_path/$branch_dir (branch: $branch)"
end

# Continue work on an existing remote branch
function wt-continue
    set -l repo $argv[1]
    set -l branch $argv[2]

    if test -z "$repo" -o -z "$branch"
        echo "Usage: wt-continue <repo> <branch-name>"
        echo "Creates a worktree tracking origin/<branch-name>"
        return 1
    end

    set -l repo_path "$WORKTREE_BASE/$repo"
    set -l default_branch (_wt_default_branch "$repo")
    set -l branch_dir (_wt_branch_to_dir "$branch")
    set -l default_branch_dir (_wt_branch_to_dir "$default_branch")

    if not test -d "$repo_path/.bare"
        echo "Error: Repository '$repo' not found at $repo_path"
        return 1
    end

    cd "$repo_path"

    # Fetch to ensure we have the latest
    git -C "$default_branch_dir" fetch origin

    # Check if remote branch exists
    if not git show-ref --verify --quiet refs/remotes/origin/"$branch"
        echo "Error: Remote branch 'origin/$branch' does not exist"
        echo "Available remote branches:"
        git branch -r | grep -v HEAD | head -10
        return 1
    end

    # Delete stale local branch if it exists
    if git show-ref --verify --quiet refs/heads/"$branch"
        echo "Deleting stale local branch '$branch'..."
        git branch -D "$branch"
    end

    # Create worktree with a local branch tracking the remote
    git worktree add -b "$branch" "$branch_dir" "origin/$branch"

    cd "$branch_dir"
    echo "Created worktree: $repo_path/$branch_dir (tracking origin/$branch)"
end

# Remove a feature worktree
# Usage: wt-rm <repo> <branch-name> [--yes]
#        wt-rm . [--yes]             (auto-detect from current directory)
function wt-rm
    set -l repo ""
    set -l branch ""
    set -l delete_branch false

    # Parse arguments
    for arg in $argv
        switch $arg
            case --yes -y
                set delete_branch true
            case '*'
                if test -z "$repo"
                    set repo $arg
                else if test -z "$branch"
                    set branch $arg
                end
        end
    end

    # Auto-detect repo and branch if "." is passed
    if test "$repo" = "."
        set -l current_dir (pwd)
        if not string match -q "$WORKTREE_BASE/*" "$current_dir"
            echo "Error: Not in a worktree directory"
            return 1
        end
        # Strip WORKTREE_BASE prefix and parse repo/branch_dir
        set -l rel_path (string replace "$WORKTREE_BASE/" "" "$current_dir")
        set repo (string split -m1 '/' "$rel_path")[1]
        set -l branch_dir (string split -m1 '/' "$rel_path")[2]
        # Handle being in repo root (no branch)
        if test -z "$branch_dir"
            echo "Error: Not in a worktree (in repo root)"
            return 1
        end
        # Convert dir name back to branch name
        set branch (_wt_dir_to_branch "$branch_dir")
        echo "Detected: $repo / $branch"
    end

    if test -z "$repo" -o -z "$branch"
        echo "Usage: wt-rm <repo> <branch-name>"
        echo "       wt-rm .  (auto-detect from current directory)"
        return 1
    end

    set -l default_branch (_wt_default_branch "$repo")
    if test "$branch" = "$default_branch" -o "$branch" = "main" -o "$branch" = "master"
        echo "Error: Cannot remove the default branch worktree"
        return 1
    end

    set -l repo_path "$WORKTREE_BASE/$repo"
    set -l branch_dir (_wt_branch_to_dir "$branch")
    set -l worktree_path "$repo_path/$branch_dir"
    set -l default_branch_dir (_wt_branch_to_dir "$default_branch")

    # Check if we're inside the worktree we're trying to remove
    set -l current_dir (pwd)
    if string match -q "$worktree_path" "$current_dir"; or string match -q "$worktree_path/*" "$current_dir"
        echo "Currently in worktree, moving to $repo/..."
    end

    cd "$repo_path"
    git worktree remove "$branch_dir"

    # Optionally delete the branch too
    if test "$delete_branch" = true
        git branch -D "$branch"
    else if isatty stdin
        read -P "Delete branch '$branch' as well? [y/N] " confirm
        if string match -qi 'y' "$confirm"
            git branch -D "$branch"
        end
    else
        echo "Skipping branch deletion (non-interactive mode, use --yes to delete)"
    end
end

# List all worktrees for a repo
function wt-ls
    set -l repo $argv[1]

    if test -z "$repo"
        echo "Usage: wt-ls <repo>"
        echo "Available repos:" (_wt_list_repos | string join ' ')
        return 1
    end

    set -l repo_path "$WORKTREE_BASE/$repo"

    cd "$repo_path"
    git worktree list
end

# Quick cd into a worktree
function wt-cd
    set -l repo $argv[1]
    set -l branch $argv[2]

    if test -z "$repo"
        echo "Usage: wt-cd <repo> [branch]"
        return 1
    end

    if test -n "$branch"
        set -l branch_dir (_wt_branch_to_dir "$branch")
        cd "$WORKTREE_BASE/$repo/$branch_dir"
    else
        cd "$WORKTREE_BASE/$repo"
    end
end

# Update default branch for a repo
function wt-update
    set -l repo $argv[1]

    if test -z "$repo"
        echo "Usage: wt-update <repo>"
        return 1
    end

    set -l repo_path "$WORKTREE_BASE/$repo"
    set -l default_branch (_wt_default_branch "$repo")
    set -l default_branch_dir (_wt_branch_to_dir "$default_branch")

    cd "$repo_path/$default_branch_dir"
    git fetch origin
    git reset --hard origin/$default_branch
    echo "Updated $repo/$default_branch to origin/$default_branch"
end

# Rebase current feature branch onto default branch
function wt-rebase
    set -l current_dir (pwd)
    set -l repo_root (dirname "$current_dir")
    set -l repo_name (basename "$repo_root")
    set -l default_branch (_wt_default_branch "$repo_name")
    set -l default_branch_dir (_wt_branch_to_dir "$default_branch")

    cd "$repo_root/$default_branch_dir"
    git fetch origin
    git reset --hard origin/$default_branch

    cd "$current_dir"
    git rebase -i "$default_branch"
end

# ===========================
# Cross-repo task helpers
# ===========================

# Create worktrees across multiple repos for a single task
function wt-multi-new
    set -l branch $argv[1]
    set -l repos $argv[2..-1]

    if test -z "$branch" -o (count $repos) -eq 0
        echo "Usage: wt-multi-new <branch-name> <repo1> <repo2> ..."
        echo "Example: wt-multi-new auth-fix backend frontend api"
        return 1
    end

    set -l branch_dir (_wt_branch_to_dir "$branch")
    set -l task_dir "$CROSS_REPO_BASE/$branch_dir"
    mkdir -p "$task_dir"

    for repo in $repos
        echo "Creating worktree for $repo..."

        # Create the worktree
        if not begin
            cd "$WORKTREE_BASE/$repo"
            and wt-new "$repo" "$branch" >/dev/null 2>&1
        end
            # If it already exists, that's fine
            if test -d "$WORKTREE_BASE/$repo/$branch_dir"
                echo "  Worktree already exists"
            else
                echo "  Failed to create worktree for $repo"
                continue
            end
        end

        # Create symlink in task directory
        ln -sf "$WORKTREE_BASE/$repo/$branch_dir" "$task_dir/$repo"
        echo "  ✓ $repo"
    end

    echo ""
    echo "Task directory: $task_dir"
    ls -la "$task_dir"
    cd "$task_dir"
end

# Add repos to an existing cross-repo task
# Usage: wt-multi-add <branch-name> <repo1> <repo2> ...
function wt-multi-add
    set -l branch $argv[1]
    set -l repos $argv[2..-1]

    if test -z "$branch" -o (count $repos) -eq 0
        echo "Usage: wt-multi-add <branch-name> <repo1> <repo2> ..."
        echo "Example: wt-multi-add auth-fix api"
        return 1
    end

    set -l branch_dir (_wt_branch_to_dir "$branch")
    set -l task_dir "$CROSS_REPO_BASE/$branch_dir"

    if not test -d "$task_dir"
        echo "Task '$branch' not found at $task_dir"
        echo "Use wt-multi-new to create a new task"
        return 1
    end

    for repo in $repos
        echo "Adding $repo to task..."

        # Check if already in task
        if test -L "$task_dir/$repo"
            echo "  $repo already in task"
            continue
        end

        # Create the worktree
        if not wt-new "$repo" "$branch" >/dev/null 2>&1
            if test -d "$WORKTREE_BASE/$repo/$branch_dir"
                echo "  Worktree already exists"
            else
                echo "  Failed to create worktree for $repo"
                continue
            end
        end

        # Create symlink in task directory
        ln -sf "$WORKTREE_BASE/$repo/$branch_dir" "$task_dir/$repo"
        echo "  ✓ $repo"
    end

    echo ""
    echo "Task directory: $task_dir"
    ls -la "$task_dir"
end

# Remove a multi-repo task (archives instead of deleting)
function wt-multi-rm
    set -l branch $argv[1]

    if test -z "$branch"
        echo "Usage: wt-multi-rm <branch-name>"
        return 1
    end

    set -l branch_dir (_wt_branch_to_dir "$branch")
    set -l task_dir "$CROSS_REPO_BASE/$branch_dir"

    if not test -d "$task_dir"
        echo "Task '$branch' not found at $task_dir"
        return 1
    end

    echo "Archiving task: $branch"

    # Remove symlinks and their corresponding worktrees
    for link in $task_dir/*
        if test -L "$link"
            set -l repo (basename "$link")
            echo "Removing worktree: $repo/$branch"
            # Remove symlink first
            rm "$link"
            # Remove the actual worktree
            echo "n" | wt-rm "$repo" "$branch"
        end
    end

    # Check if there are any real files left (excluding .DS_Store)
    set -l has_files false
    for f in $task_dir/*
        if test -e "$f"; and test (basename "$f") != ".DS_Store"
            set has_files true
            break
        end
    end
    
    if test "$has_files" = true
        # Archive the task directory (contains non-symlink files like notes)
        mkdir -p "$CROSS_REPO_ARCHIVE"
        set -l archive_dest "$CROSS_REPO_ARCHIVE/$branch_dir"
        
        # Handle naming collision by appending .N suffix
        if test -e "$archive_dest"
            set -l n 1
            while test -e "$archive_dest.$n"
                set n (math $n + 1)
            end
            set archive_dest "$archive_dest.$n"
        end
        
        mv "$task_dir" "$archive_dest"
        echo "✓ Task archived to: $archive_dest"
    else
        # No meaningful files, just remove the directory
        rm -rf "$task_dir"
        echo "✓ Task removed"
    end
end

# List all cross-repo tasks
function wt-multi-ls
    if not test -d "$CROSS_REPO_BASE"
        echo "No cross-repo tasks found"
        return
    end

    echo "Cross-repo tasks:"
    for task_dir in $CROSS_REPO_BASE/*/
        if test -d "$task_dir"
            set -l task (basename "$task_dir")
            set -l repos (ls "$task_dir" 2>/dev/null | string join ' ')
            echo "  $task: $repos"
        end
    end
end

# cd into a cross-repo task directory
function wt-multi-cd
    set -l branch $argv[1]

    if test -z "$branch"
        echo "Usage: wt-multi-cd <branch-name>"
        return 1
    end

    set -l branch_dir (_wt_branch_to_dir "$branch")
    cd "$CROSS_REPO_BASE/$branch_dir"
end
