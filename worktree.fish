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

# Find a mirror for a repo name in WORKTREE_MIRROR_BASE
# Checks common bare repo layouts; prints path on success
function _wt_find_mirror
    set -l name $argv[1]
    if not set -q WORKTREE_MIRROR_BASE; or test -z "$WORKTREE_MIRROR_BASE"
        return 1
    end

    for candidate in "$WORKTREE_MIRROR_BASE/$name.git" "$WORKTREE_MIRROR_BASE/$name" "$WORKTREE_MIRROR_BASE/$name/.bare"
        if test -d "$candidate/objects"
            echo "$candidate"
            return 0
        end
    end
    return 1
end

# Clone a repo into the worktree structure
# Usage: wt-clone <git-url> [local-name]
#        wt-clone <name> [origin-url]   (from mirror, requires WORKTREE_MIRROR_BASE)
function wt-clone
    set -l url ""
    set -l name ""

    # Detect whether the first arg is a URL or a plain repo name
    if string match -q '*://*' -- $argv[1]; or string match -q '*@*:*' -- $argv[1]
        set url $argv[1]
        if test -n "$argv[2]"
            set name $argv[2]
        else
            set name (basename "$url" .git)
        end
    else
        set name $argv[1]
        if test -n "$argv[2]"
            set url $argv[2]
        end
    end

    # Try to find a local mirror
    set -l mirror_path ""
    if test -n "$name"
        set mirror_path (_wt_find_mirror "$name" 2>/dev/null); or set mirror_path ""
    end

    if test -z "$name"; or begin; test -z "$url"; and test -z "$mirror_path"; end
        echo "Usage: wt-clone <git-url> [local-name]"
        echo "       wt-clone <name> [origin-url]   (from mirror, requires WORKTREE_MIRROR_BASE)"
        echo "Example: wt-clone git@github.com:user/repo.git"
        echo "Example: wt-clone git@github.com:user/repo.git my-repo"
        if set -q WORKTREE_MIRROR_BASE; and test -n "$WORKTREE_MIRROR_BASE"
            echo "Example: wt-clone my-repo              (from mirror)"
        end
        return 1
    end

    set -l repo_path "$WORKTREE_BASE/$name"

    if test -d "$repo_path"
        echo "Error: $repo_path already exists"
        return 1
    end

    mkdir -p "$repo_path"
    cd "$repo_path"

    if test -n "$mirror_path"
        echo "Cloning $name from mirror ($mirror_path)..."
        # --shared sets up alternates to read objects from the mirror (no copy)
        git clone --bare --shared "$mirror_path" .bare
        echo "gitdir: ./.bare" > .git
        git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
        if test -n "$url"
            git remote set-url origin "$url" 2>/dev/null; or git remote add origin "$url"
        end
        # Fetch to sync remote tracking refs (fast — objects read via alternates)
        git fetch origin
    else
        echo "Cloning $url into $repo_path..."
        git clone --bare "$url" .bare
        echo "gitdir: ./.bare" > .git
        git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
        git fetch origin
    end

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

# Bootstrap repos from mirrors in parallel
# Usage: wt-mirror-setup [repo1] [repo2] ...
#        wt-mirror-setup               (discover all mirrors)
function wt-mirror-setup
    if not set -q WORKTREE_MIRROR_BASE; or test -z "$WORKTREE_MIRROR_BASE"
        echo "Error: WORKTREE_MIRROR_BASE must be set"
        return 1
    end

    if not test -d "$WORKTREE_MIRROR_BASE"
        echo "Error: WORKTREE_MIRROR_BASE ($WORKTREE_MIRROR_BASE) does not exist"
        return 1
    end

    set -l repos $argv

    # Auto-discover mirrors if none specified
    if test (count $repos) -eq 0
        set -l seen
        for entry in $WORKTREE_MIRROR_BASE/*
            test -d "$entry"; or continue
            set -l n (basename "$entry" .git)
            if not contains "$n" $seen; and _wt_find_mirror "$n" >/dev/null 2>&1
                set -a seen "$n"
                set -a repos "$n"
            end
        end
    end

    if test (count $repos) -eq 0
        echo "No mirrors found in $WORKTREE_MIRROR_BASE"
        return 1
    end

    echo "Setting up "(count $repos)" repo(s) from mirrors..."
    echo ""

    set -l tmpdir (mktemp -d)
    set -l pids
    set -l names

    for name in $repos
        if test -d "$WORKTREE_BASE/$name"
            echo "  ⊘ $name (already exists, skipping)"
            continue
        end
        begin; wt-clone "$name" > $tmpdir/$name.log 2>&1; end &
        set -a pids $last_pid
        set -a names "$name"
    end

    set -l failed 0
    for i in (seq (count $pids))
        if wait $pids[$i] 2>/dev/null
            echo "  ✓ $names[$i]"
        else
            echo "  ✗ $names[$i]"
            sed 's/^/    /' $tmpdir/$names[$i].log
            set failed (math $failed + 1)
        end
    end

    rm -rf $tmpdir
    echo ""
    if test $failed -eq 0
        echo "✓ All repos set up from mirrors"
    else
        echo "⚠ $failed repo(s) failed"
        return 1
    end
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
    set -l branch_dir (_wt_branch_to_dir "$branch")

    # Auto-setup from mirror if repo doesn't exist yet
    if not test -d "$repo_path/.bare"; and _wt_find_mirror "$repo" >/dev/null 2>&1
        echo "Auto-initializing $repo from mirror..."
        set -l _prev_dir (pwd)
        wt-clone "$repo"; or return 1
        cd "$_prev_dir"
    end

    if not test -d "$repo_path/.bare"
        echo "Error: Repository '$repo' not found at $repo_path"
        return 1
    end

    set -l default_branch (_wt_default_branch "$repo")

    cd "$repo_path"

    # Fetch latest and branch directly off origin — avoids touching the
    # default-branch worktree (which may be detached or have local changes)
    git fetch origin "$default_branch"

    # Create worktree from origin's default branch
    git worktree add "$branch_dir" -b "$branch" "origin/$default_branch"

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
    set -l branch_dir (_wt_branch_to_dir "$branch")

    # Auto-setup from mirror if repo doesn't exist yet
    if not test -d "$repo_path/.bare"; and _wt_find_mirror "$repo" >/dev/null 2>&1
        echo "Auto-initializing $repo from mirror..."
        set -l _prev_dir (pwd)
        wt-clone "$repo"; or return 1
        cd "$_prev_dir"
    end

    if not test -d "$repo_path/.bare"
        echo "Error: Repository '$repo' not found at $repo_path"
        return 1
    end

    set -l default_branch (_wt_default_branch "$repo")
    set -l default_branch_dir (_wt_branch_to_dir "$default_branch")

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

        # Create the worktree (save/restore cwd since wt-new changes directory)
        set -l _prev_dir (pwd)
        if not wt-new "$repo" "$branch" >/dev/null 2>&1
            # If it already exists, that's fine
            if test -d "$WORKTREE_BASE/$repo/$branch_dir"
                echo "  Worktree already exists"
            else
                echo "  Failed to create worktree for $repo"
                cd "$_prev_dir"
                continue
            end
        end
        cd "$_prev_dir"

        # Create symlink in task directory
        ln -sf "$WORKTREE_BASE/$repo/$branch_dir" "$task_dir/$repo"
        echo "  ✓ $repo"
    end

    # Create AGENTS.md and CLAUDE.md to help AI agents stay oriented
    _wt_write_agent_files "$task_dir" "$branch" $repos

    echo ""
    echo "Task directory: $task_dir"
    ls -la "$task_dir"
    cd "$task_dir"
end

# Write AGENTS.md and CLAUDE.md files for a cross-repo task directory
function _wt_write_agent_files
    set -l task_dir $argv[1]
    set -l branch $argv[2]
    set -l repos $argv[3..-1]

    # If no repos passed, gather from existing symlinks
    if test (count $repos) -eq 0
        set repos
        for link in $task_dir/*
            if test -L "$link"
                set -a repos (basename "$link")
            end
        end
    end

    set -l repo_list ""
    for repo in $repos
        set repo_list "$repo_list- $repo
"
    end

    set -l content "# Cross-Repo Task: $branch

This is a cross-repo task directory. Each subdirectory is a symlinked repository worktree.

**Important:** Always use this directory ($task_dir) as your workspace root.
Do NOT navigate to or use the resolved symlink target paths under ~/worktree.
Stay in this directory when running commands.

## Repositories

$repo_list"

    echo "$content" > "$task_dir/AGENTS.md"
    echo "$content" > "$task_dir/CLAUDE.md"
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

    # Update AGENTS.md and CLAUDE.md with new repo list
    _wt_write_agent_files "$task_dir" "$branch"

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
