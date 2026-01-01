# Fish completions for git-worktree-utils
# Save to ~/.config/fish/completions/wt.fish or source after worktree.fish

# Helper: convert directory name back to branch name (feature__foo -> feature/foo)
function __wt_dir_to_branch
    string replace -a '__' '/' $argv[1]
end

# Helper: list repos
function __wt_repos
    for dir in $WORKTREE_BASE/*/
        if test -d "$dir.bare"
            basename $dir
        end
    end
end

# Helper: list branches for a repo (returns branch names, not dir names)
function __wt_branches
    set -l repo $argv[1]
    set -l repo_path "$WORKTREE_BASE/$repo"
    if test -d "$repo_path"
        for dir_name in (ls -1 "$repo_path" 2>/dev/null | grep -v '^\.' | grep -v '^\.bare$')
            __wt_dir_to_branch "$dir_name"
        end
    end
end

# Helper: list tasks (returns branch names, not dir names)
function __wt_tasks
    if test -d "$CROSS_REPO_BASE"
        for dir_name in (ls -1 "$CROSS_REPO_BASE" 2>/dev/null)
            __wt_dir_to_branch "$dir_name"
        end
    end
end

# Helper: list remote branches
function __wt_remote_branches
    set -l repo $argv[1]
    set -l repo_path "$WORKTREE_BASE/$repo"
    set -l default_branch (_wt_default_branch "$repo")
    set -l default_branch_dir (_wt_branch_to_dir "$default_branch")
    if test -d "$repo_path/$default_branch_dir"
        git -C "$repo_path/$default_branch_dir" branch -r 2>/dev/null | grep -v HEAD | sed 's|origin/||' | string trim
    end
end

# wt-cd: repo [branch]
complete -c wt-cd -f
complete -c wt-cd -n "test (count (commandline -opc)) -eq 1" -a "(__wt_repos)"
complete -c wt-cd -n "test (count (commandline -opc)) -eq 2" -a "(__wt_branches (commandline -opc)[2])"

# wt-new: repo branch
complete -c wt-new -f
complete -c wt-new -n "test (count (commandline -opc)) -eq 1" -a "(__wt_repos)"

# wt-continue: repo remote-branch
complete -c wt-continue -f
complete -c wt-continue -n "test (count (commandline -opc)) -eq 1" -a "(__wt_repos)"
complete -c wt-continue -n "test (count (commandline -opc)) -eq 2" -a "(__wt_remote_branches (commandline -opc)[2])"

# wt-rm: repo branch
complete -c wt-rm -f
complete -c wt-rm -n "test (count (commandline -opc)) -eq 1" -a "(__wt_repos)"
complete -c wt-rm -n "test (count (commandline -opc)) -eq 2" -a "(__wt_branches (commandline -opc)[2])"

# wt-ls: repo
complete -c wt-ls -f
complete -c wt-ls -n "test (count (commandline -opc)) -eq 1" -a "(__wt_repos)"

# wt-update: repo
complete -c wt-update -f
complete -c wt-update -n "test (count (commandline -opc)) -eq 1" -a "(__wt_repos)"

# wt-rebase: no args
complete -c wt-rebase -f

# wt-multi-new: branch repos...
complete -c wt-multi-new -f
complete -c wt-multi-new -n "test (count (commandline -opc)) -ge 2" -a "(__wt_repos)"

# wt-multi-cd: task
complete -c wt-multi-cd -f
complete -c wt-multi-cd -n "test (count (commandline -opc)) -eq 1" -a "(__wt_tasks)"

# wt-multi-rm: task
complete -c wt-multi-rm -f
complete -c wt-multi-rm -n "test (count (commandline -opc)) -eq 1" -a "(__wt_tasks)"

# wt-multi-ls: no args
complete -c wt-multi-ls -f
