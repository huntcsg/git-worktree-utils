# Git Worktree Utils

Shell utilities for managing git worktrees using the **bare repo + worktree pattern**. This pattern enables parallel feature development where each feature branch lives in its own directory.

## Features

- Create/remove worktrees with simple commands
- Tab completion for repos, branches, and tasks
- Cross-repo task management with symlinks
- Configurable default branches per repo
- Works with any set of repositories

## Installation

### Homebrew (recommended)

```bash
brew tap huntcsg/git-worktree-utils https://github.com/huntcsg/git-worktree-utils
brew install git-worktree-utils
git-worktree-utils-setup
```

### From Source

```bash
git clone https://github.com/huntcsg/git-worktree-utils.git
cd git-worktree-utils
./setup.sh
```

The setup script will:
1. Ask for your worktree directory (default: `~/worktrees`)
2. Ask for your cross-repo tasks directory (default: `~/cross-repo-tasks`)
3. Ask for any default branch overrides (e.g., `myrepo=master`)
4. Ask where to install scripts (default: `~/.local/share/git-worktree-utils`)
5. Add the configuration to your shell rc file

#### Updating

```bash
# If installed via Homebrew:
brew upgrade git-worktree-utils
git-worktree-utils-setup --update

# If installed from source (and using stable location):
cd /path/to/git-worktree-utils
git pull
./setup.sh --update

# If installed from source (in-place):
cd /path/to/git-worktree-utils
git pull
# Scripts are sourced directly, so no update needed
```

### Manual Setup

#### Zsh

Add to `~/.zshrc`:

```bash
export WORKTREE_BASE="$HOME/worktrees"
export CROSS_REPO_BASE="$HOME/cross-repo-tasks"
export CROSS_REPO_ARCHIVE="$HOME/cross-repo-tasks/wt-archive"

# Optional: Override default branch for specific repos
declare -A WT_DEFAULT_BRANCH_OVERRIDES=([myrepo]=master [legacy]=develop)
export WT_DEFAULT_BRANCH_OVERRIDES

source /path/to/git-worktree-utils/worktree.sh
source /path/to/git-worktree-utils/completions.zsh
```

#### Bash

Add to `~/.bashrc`:

```bash
export WORKTREE_BASE="$HOME/worktrees"
export CROSS_REPO_BASE="$HOME/cross-repo-tasks"
export CROSS_REPO_ARCHIVE="$HOME/cross-repo-tasks/wt-archive"

# Optional: Override default branch for specific repos
declare -A WT_DEFAULT_BRANCH_OVERRIDES=([myrepo]=master [legacy]=develop)
export WT_DEFAULT_BRANCH_OVERRIDES

source /path/to/git-worktree-utils/worktree.sh
source /path/to/git-worktree-utils/completions.bash
```

#### Fish

Add to `~/.config/fish/config.fish`:

```fish
set -gx WORKTREE_BASE "$HOME/worktrees"
set -gx CROSS_REPO_BASE "$HOME/cross-repo-tasks"
set -gx CROSS_REPO_ARCHIVE "$HOME/cross-repo-tasks/wt-archive"

# Optional: Override default branch for specific repos
set -gx WT_DEFAULT_BRANCH_myrepo master
set -gx WT_DEFAULT_BRANCH_legacy develop

source /path/to/git-worktree-utils/worktree.fish
source /path/to/git-worktree-utils/completions.fish
```

#### PowerShell (Windows)

Run the interactive setup:

```powershell
git clone https://github.com/huntcsg/git-worktree-utils.git
cd git-worktree-utils
.\setup.ps1
```

Or manually add to your `$PROFILE`:

```powershell
$env:WORKTREE_BASE = "$HOME\worktrees"
$env:CROSS_REPO_BASE = "$HOME\cross-repo-tasks"
$env:CROSS_REPO_ARCHIVE = "$HOME\cross-repo-tasks\wt-archive"

. "C:\path\to\git-worktree-utils\worktree.ps1"
. "C:\path\to\git-worktree-utils\completions.ps1"

# Optional: Override default branch for specific repos
Set-WtConfig -DefaultBranchOverrides @{
    myrepo = 'master'
    legacy = 'develop'
}
```

The PowerShell implementation provides both idiomatic cmdlet names (e.g., `New-Worktree`, `Remove-Worktree`) and CLI-compatible aliases (e.g., `wt-new`, `wt-rm`) for cross-platform consistency.

**Note:** Cross-repo symlinks (`wt-multi-*` commands) require either Developer Mode enabled or running PowerShell as Administrator.

## Directory Structure

```
$WORKTREE_BASE/
├── repo-a/
│   ├── .bare/           # bare git repo (all git data)
│   ├── .git             # pointer file: "gitdir: ./.bare"
│   ├── main/            # worktree tracking main branch
│   └── my-feature/      # feature branch worktree
│
├── repo-b/
│   ├── .bare/
│   ├── .git
│   └── main/
│
└── repo-c/
    ├── .bare/
    ├── .git
    └── main/            # tracks 'master' if configured

$CROSS_REPO_BASE/
└── auth-fix/            # cross-repo task
    ├── repo-a -> $WORKTREE_BASE/repo-a/auth-fix
    └── repo-b -> $WORKTREE_BASE/repo-b/auth-fix
```

## Commands

### Single-Repo Commands

| Command | Description |
|---------|-------------|
| `wt-clone <url> [name]` | Clone a remote repo into the worktree structure |
| `wt-init <name> [branch]` | Initialize a new local repo from scratch |
| `wt-new <repo> <branch>` | Create a new feature worktree branched from main |
| `wt-continue <repo> <branch>` | Create worktree from existing remote branch |
| `wt-rm <repo> <branch>` | Remove a worktree (optionally delete branch) |
| `wt-rm .` | Remove current worktree (auto-detect repo/branch) |
| `wt-ls <repo>` | List all worktrees for a repo |
| `wt-cd <repo> [branch]` | cd into a worktree (or repo root) |
| `wt-update <repo>` | Fetch and reset main to origin |
| `wt-rebase` | Rebase current feature branch onto updated main |

### Cross-Repo Commands

| Command | Description |
|---------|-------------|
| `wt-multi-new <branch> <repos...>` | Create worktrees in multiple repos with symlinks |
| `wt-multi-add <branch> <repos...>` | Add repos to an existing cross-repo task |
| `wt-multi-rm <branch>` | Archive a cross-repo task (removes worktrees, archives remaining files) |
| `wt-multi-ls` | List all cross-repo tasks |
| `wt-multi-cd <branch>` | cd into a task directory |

## Workflow Examples

### Clone a repo

```bash
wt-clone git@github.com:user/myrepo.git
# Clones into $WORKTREE_BASE/myrepo/
# Auto-detects default branch and creates worktree

wt-clone git@github.com:user/myrepo.git custom-name
# Clones into $WORKTREE_BASE/custom-name/
```

### Create a new local repo

```bash
wt-init my-project
# Creates $WORKTREE_BASE/my-project/ with 'main' as default

wt-init my-project develop
# Creates with 'develop' as default branch
```

### Start a new feature

```bash
wt-new myrepo add-billing-page
# Creates $WORKTREE_BASE/myrepo/add-billing-page/
# You're now in that directory, ready to code
```

### Continue work on an existing remote branch

```bash
wt-continue myrepo feature-from-coworker
# Creates worktree tracking origin/feature-from-coworker
```

### Switch between features

```bash
wt-cd myrepo add-billing-page
wt-cd frontend main
```

### Rebase before pushing

```bash
cd $WORKTREE_BASE/myrepo/my-feature
wt-rebase
git push --force-with-lease
```

### Clean up after merge

```bash
wt-rm myrepo add-billing-page
# Prompts to delete the branch too

wt-rm .
# Auto-detects repo and branch from current directory

wt-rm myrepo add-billing-page --yes
# Removes worktree and deletes branch without prompting
```

### Cross-repo feature

```bash
wt-multi-new auth-fix backend frontend api
# Creates:
#   $WORKTREE_BASE/backend/auth-fix/
#   $WORKTREE_BASE/frontend/auth-fix/
#   $WORKTREE_BASE/api/auth-fix/
# And symlinks them under:
#   $CROSS_REPO_BASE/auth-fix/
```

## Adding a New Repository

Use `wt-clone` to add a remote repository:

```bash
wt-clone git@github.com:user/repo.git
wt-clone git@github.com:user/repo.git custom-name  # optional custom name
```

Or `wt-init` for a new local repository:

```bash
wt-init my-new-project
wt-init my-new-project develop  # optional custom default branch
```

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `WORKTREE_BASE` | Yes | Directory containing bare repos |
| `CROSS_REPO_BASE` | Yes | Directory for cross-repo task symlinks |
| `CROSS_REPO_ARCHIVE` | Yes | Directory where archived tasks are moved by `wt-multi-rm` |
| `WT_DEFAULT_BRANCH_OVERRIDES` | No | Associative array of repo→branch overrides (usually not needed) |

### Default Branch Detection

The default branch is **automatically detected** from `refs/remotes/origin/HEAD` in the bare repo. This is set when you clone, so most repos just work.

If auto-detection fails (e.g., origin/HEAD not set), you can manually override:

```bash
declare -A WT_DEFAULT_BRANCH_OVERRIDES=(
    [legacy-app]=master
    [old-service]=develop
)
export WT_DEFAULT_BRANCH_OVERRIDES
```

## Notes

- The `.bare` directory contains all git objects, refs, etc.
- Worktrees share the object store — creating new ones is fast
- Each worktree has its own index, so you can have uncommitted changes in multiple features
- Run `git worktree prune` to clean up references to manually deleted directories
- Tab completion dynamically discovers repos from `$WORKTREE_BASE`

## License

[The Unlicense](UNLICENSE) - Public Domain
