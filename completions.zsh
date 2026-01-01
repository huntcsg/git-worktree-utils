#!/usr/bin/env zsh
# Zsh completions for git-worktree-utils
# Source this file after worktree.sh in your .zshrc

# Convert directory name back to branch name (feature__foo -> feature/foo)
_wt_dir_to_branch() {
    echo "${1//__//}"
}

# List repos dynamically from WORKTREE_BASE
_wt_repos() {
    local repos=()
    local dir
    for dir in "$WORKTREE_BASE"/*/; do
        if [[ -d "${dir}.bare" ]]; then
            repos+=($(basename "$dir"))
        fi
    done
    _describe 'repository' repos
}

# List branches/worktrees for a given repo (returns branch names, not dir names)
_wt_branches() {
    local repo="$1"
    local repo_path="$WORKTREE_BASE/$repo"
    if [[ -d "$repo_path" ]]; then
        local branches=()
        local dir_name
        for dir_name in ${(f)"$(ls -1 "$repo_path" 2>/dev/null | grep -v '^\.' | grep -v '^\.bare$')"}; do
            branches+=($(_wt_dir_to_branch "$dir_name"))
        done
        _describe 'branch' branches
    fi
}

# List cross-repo tasks (returns branch names, not dir names)
_wt_tasks() {
    if [[ -d "$CROSS_REPO_BASE" ]]; then
        local tasks=()
        local dir_name
        for dir_name in ${(f)"$(ls -1 "$CROSS_REPO_BASE" 2>/dev/null)"}; do
            tasks+=($(_wt_dir_to_branch "$dir_name"))
        done
        _describe 'task' tasks
    fi
}

# Completion for wt-cd
_wt-cd() {
    case $CURRENT in
        2) _wt_repos ;;
        3) _wt_branches "${words[2]}" ;;
    esac
}

# Completion for wt-new
_wt-new() {
    case $CURRENT in
        2) _wt_repos ;;
    esac
}

# Completion for wt-continue
_wt-continue() {
    case $CURRENT in
        2) _wt_repos ;;
        3)
            # Complete with remote branches
            local repo="${words[2]}"
            local repo_path="$WORKTREE_BASE/$repo"
            local default_branch=$(_wt_default_branch "$repo")
            local default_branch_dir=$(_wt_branch_to_dir "$default_branch")
            if [[ -d "$repo_path/$default_branch_dir" ]]; then
                local branches=(${(f)"$(git -C "$repo_path/$default_branch_dir" branch -r 2>/dev/null | grep -v HEAD | sed 's|origin/||' | tr -d ' ')"})
                _describe 'remote branch' branches
            fi
            ;;
    esac
}

# Completion for wt-rm
_wt-rm() {
    case $CURRENT in
        2) _wt_repos ;;
        3) _wt_branches "${words[2]}" ;;
    esac
}

# Completion for wt-ls
_wt-ls() { _wt_repos; }

# Completion for wt-update
_wt-update() { _wt_repos; }

# Completion for wt-multi-new
_wt-multi-new() {
    case $CURRENT in
        2) ;; # branch name - no completion
        *) _wt_repos ;;
    esac
}

# Completion for wt-multi-add
_wt-multi-add() {
    case $CURRENT in
        2) _wt_tasks ;; # task name
        *) _wt_repos ;;
    esac
}

# Register completions
compdef _wt-cd wt-cd
compdef _wt-new wt-new
compdef _wt-continue wt-continue
compdef _wt-rm wt-rm
compdef _wt-ls wt-ls
compdef _wt-update wt-update
compdef _wt-multi-new wt-multi-new
compdef _wt-multi-add wt-multi-add
compdef _wt_tasks wt-multi-cd
compdef _wt_tasks wt-multi-rm
