#!/usr/bin/env bash
# Bash completions for git-worktree-utils
# Source this file after worktree.sh in your .bashrc

# Convert directory name back to branch name (feature__foo -> feature/foo)
_wt_dir_to_branch() {
    echo "${1//__//}"
}

# List repos dynamically from WORKTREE_BASE
_wt_list_repos() {
    local dir
    for dir in "$WORKTREE_BASE"/*/; do
        if [[ -d "${dir}.bare" ]]; then
            basename "$dir"
        fi
    done
}

# List branches/worktrees for a given repo (returns branch names, not dir names)
_wt_list_branches() {
    local repo="$1"
    local repo_path="$WORKTREE_BASE/$repo"
    if [[ -d "$repo_path" ]]; then
        local dir_name
        # shellcheck disable=SC2010
        for dir_name in $(ls -1 "$repo_path" 2>/dev/null | grep -v '^\.' | grep -v '^\.bare$'); do
            _wt_dir_to_branch "$dir_name"
        done
    fi
}

# List cross-repo tasks (returns branch names, not dir names)
_wt_list_tasks() {
    if [[ -d "$CROSS_REPO_BASE" ]]; then
        local dir_name
        # shellcheck disable=SC2045
        for dir_name in $(ls -1 "$CROSS_REPO_BASE" 2>/dev/null); do
            _wt_dir_to_branch "$dir_name"
        done
    fi
}

# List remote branches for a repo
_wt_list_remote_branches() {
    local repo="$1"
    local repo_path="$WORKTREE_BASE/$repo"
    local default_branch default_branch_dir
    default_branch=$(_wt_default_branch "$repo")
    default_branch_dir=$(_wt_branch_to_dir "$default_branch")
    if [[ -d "$repo_path/$default_branch_dir" ]]; then
        git -C "$repo_path/$default_branch_dir" branch -r 2>/dev/null | grep -v HEAD | sed 's|origin/||' | tr -d ' '
    fi
}

# Completion for wt-cd: repo then branch
_wt_cd_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    case $COMP_CWORD in
        1)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_repos)" -- "$cur"))
            ;;
        2)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_branches "$prev")" -- "$cur"))
            ;;
    esac
}

# Completion for wt-new: repo only
_wt_new_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    
    case $COMP_CWORD in
        1)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_repos)" -- "$cur"))
            ;;
    esac
}

# Completion for wt-continue: repo then remote branch
_wt_continue_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    case $COMP_CWORD in
        1)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_repos)" -- "$cur"))
            ;;
        2)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_remote_branches "$prev")" -- "$cur"))
            ;;
    esac
}

# Completion for wt-rm: repo then branch
_wt_rm_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    case $COMP_CWORD in
        1)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_repos)" -- "$cur"))
            ;;
        2)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_branches "$prev")" -- "$cur"))
            ;;
    esac
}

# Completion for wt-ls, wt-update: repo only
_wt_repo_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    
    case $COMP_CWORD in
        1)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_repos)" -- "$cur"))
            ;;
    esac
}

# Completion for wt-multi: branch then repos
_wt_multi_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    
    case $COMP_CWORD in
        1)
            # No completion for branch name
            ;;
        *)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_repos)" -- "$cur"))
            ;;
    esac
}

# Completion for wt-multi-cd, wt-multi-rm: task only
_wt_task_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    
    case $COMP_CWORD in
        1)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_wt_list_tasks)" -- "$cur"))
            ;;
    esac
}

# Register completions
complete -F _wt_cd_complete wt-cd
complete -F _wt_new_complete wt-new
complete -F _wt_continue_complete wt-continue
complete -F _wt_rm_complete wt-rm
complete -F _wt_repo_complete wt-ls
complete -F _wt_repo_complete wt-update
complete -F _wt_multi_complete wt-multi-new
complete -F _wt_task_complete wt-multi-cd
complete -F _wt_task_complete wt-multi-rm
