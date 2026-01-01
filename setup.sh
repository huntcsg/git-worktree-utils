#!/usr/bin/env bash
# Setup script for git-worktree-utils
# Run this to configure your shell
#
# Usage:
#   ./setup.sh           # Interactive setup
#   ./setup.sh --update  # Update existing config (re-copy scripts if relocated)

set -e

# Configuration block markers (used for idempotent updates)
BLOCK_START="# >>> git-worktree-utils >>>"
BLOCK_END="# <<< git-worktree-utils <<<"

# Default install location for relocatable installs
DEFAULT_INSTALL_DIR="$HOME/.local/share/git-worktree-utils"

# Detect if running from brew prefix
if [[ "${BASH_SOURCE[0]}" == *"/Cellar/"* ]] || [[ "${BASH_SOURCE[0]}" == *"/homebrew/"* ]]; then
    BREW_INSTALL=true
    SCRIPT_DIR="$(brew --prefix)/share/git-worktree-utils"
else
    BREW_INSTALL=false
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Parse arguments
UPDATE_MODE=false
for arg in "$@"; do
    case $arg in
        --update)
            UPDATE_MODE=true
            ;;
    esac
done

echo "Git Worktree Utils Setup"
echo "========================"
echo ""

# Detect shell
SHELL_NAME=$(basename "$SHELL")
echo "Detected shell: $SHELL_NAME"

case "$SHELL_NAME" in
    zsh)
        RC_FILE="$HOME/.zshrc"
        ;;
    bash)
        RC_FILE="$HOME/.bashrc"
        ;;
    fish)
        RC_FILE="$HOME/.config/fish/config.fish"
        mkdir -p "$(dirname "$RC_FILE")"
        ;;
    *)
        echo "Unsupported shell: $SHELL_NAME"
        echo "Supported shells: zsh, bash, fish"
        exit 1
        ;;
esac

# Check for existing config
EXISTING_CONFIG=false
if grep -q "$BLOCK_START" "$RC_FILE" 2>/dev/null; then
    EXISTING_CONFIG=true
fi

# Helper function to extract current value from existing config
get_existing_value() {
    local pattern="$1"
    local default="$2"
    if [[ "$EXISTING_CONFIG" == true ]]; then
        local value
        value=$(sed -n "/$BLOCK_START/,/$BLOCK_END/p" "$RC_FILE" | grep -E "$pattern" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -n "$value" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# Get current install dir if exists
get_existing_install_dir() {
    if [[ "$EXISTING_CONFIG" == true ]]; then
        local source_line
        source_line=$(sed -n "/$BLOCK_START/,/$BLOCK_END/p" "$RC_FILE" | grep -E "source.*worktree\.(sh|fish)" | head -1)
        if [[ -n "$source_line" ]]; then
            # Extract directory from source line
            local dir
            dir=$(echo "$source_line" | sed -E 's|.*source "?([^"]+)/worktree\.(sh\|fish).*|\1|')
            # Expand brew prefix if present
            dir=$(eval echo "$dir" 2>/dev/null || echo "$dir")
            echo "$dir"
            return
        fi
    fi
    echo ""
}

if [[ "$EXISTING_CONFIG" == true ]]; then
    echo ""
    echo "Existing configuration found in $RC_FILE"
    if [[ "$UPDATE_MODE" == true ]]; then
        echo "Running in update mode..."
    else
        read -r -p "Update existing configuration? [Y/n] " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    # Get existing values as defaults
    DEFAULT_WORKTREE_BASE=$(get_existing_value "WORKTREE_BASE" "$HOME/worktrees")
    DEFAULT_CROSS_REPO_BASE=$(get_existing_value "CROSS_REPO_BASE" "$HOME/cross-repo-tasks")
    DEFAULT_CROSS_REPO_ARCHIVE=$(get_existing_value "CROSS_REPO_ARCHIVE" "")
    CURRENT_INSTALL_DIR=$(get_existing_install_dir)
else
    DEFAULT_WORKTREE_BASE="$HOME/worktrees"
    DEFAULT_CROSS_REPO_BASE="$HOME/cross-repo-tasks"
    DEFAULT_CROSS_REPO_ARCHIVE=""
    CURRENT_INSTALL_DIR=""
fi

echo ""

# In update mode with existing config, skip prompts and use existing values
if [[ "$UPDATE_MODE" == true && "$EXISTING_CONFIG" == true ]]; then
    WORKTREE_BASE="$DEFAULT_WORKTREE_BASE"
    CROSS_REPO_BASE="$DEFAULT_CROSS_REPO_BASE"
    CROSS_REPO_ARCHIVE="${DEFAULT_CROSS_REPO_ARCHIVE:-$CROSS_REPO_BASE/wt-archive}"
    INSTALL_DIR="${CURRENT_INSTALL_DIR:-$SCRIPT_DIR}"
    OVERRIDES=""  # TODO: could extract existing overrides
else
    # Get worktree base directory
    read -r -p "Worktree base directory [$DEFAULT_WORKTREE_BASE]: " WORKTREE_BASE
    WORKTREE_BASE="${WORKTREE_BASE:-$DEFAULT_WORKTREE_BASE}"
    WORKTREE_BASE="${WORKTREE_BASE/#\~/$HOME}"

    # Get cross-repo base directory
    read -r -p "Cross-repo tasks directory [$DEFAULT_CROSS_REPO_BASE]: " CROSS_REPO_BASE
    CROSS_REPO_BASE="${CROSS_REPO_BASE:-$DEFAULT_CROSS_REPO_BASE}"
    CROSS_REPO_BASE="${CROSS_REPO_BASE/#\~/$HOME}"

    # Ask about archive directory for wt-multi-rm
    echo ""
    echo "When removing cross-repo tasks, where should they be archived?"
    echo "  1) $CROSS_REPO_BASE/wt-archive (default)"
    echo "  2) ~/.local/share/git-worktree-utils/archive"
    echo "  3) Custom path"
    read -r -p "Choice [1]: " ARCHIVE_CHOICE
    ARCHIVE_CHOICE="${ARCHIVE_CHOICE:-1}"
    
    case "$ARCHIVE_CHOICE" in
        1)
            CROSS_REPO_ARCHIVE="$CROSS_REPO_BASE/wt-archive"
            ;;
        2)
            CROSS_REPO_ARCHIVE="$HOME/.local/share/git-worktree-utils/archive"
            ;;
        3)
            read -r -p "Archive directory: " CROSS_REPO_ARCHIVE
            CROSS_REPO_ARCHIVE="${CROSS_REPO_ARCHIVE/#\~/$HOME}"
            ;;
        *)
            CROSS_REPO_ARCHIVE="$CROSS_REPO_BASE/wt-archive"
            ;;
    esac

    # Ask about default branch overrides
    echo ""
    echo "Some repos may use a non-standard default branch (e.g., 'master' instead of 'main')."
    echo "Enter overrides as 'repo=branch' (comma-separated), or leave blank for none."
    echo "Example: comfyui=master,legacy-app=develop"
    read -r -p "Default branch overrides []: " OVERRIDES

    # Ask about installation location (skip for brew installs)
    echo ""
    if [[ "$BREW_INSTALL" == true ]]; then
        echo "Installed via Homebrew, using: $SCRIPT_DIR"
        INSTALL_DIR="$SCRIPT_DIR"
    else
        echo "Where should the scripts be installed?"
        echo "  1) Current location: $SCRIPT_DIR"
        echo "  2) Stable location:  $DEFAULT_INSTALL_DIR (recommended)"
        echo ""
        echo "Option 2 copies scripts to a stable location, so you can delete this checkout."
        read -r -p "Choice [2]: " INSTALL_CHOICE
        INSTALL_CHOICE="${INSTALL_CHOICE:-2}"
        
        if [[ "$INSTALL_CHOICE" == "1" ]]; then
            INSTALL_DIR="$SCRIPT_DIR"
        else
            read -r -p "Install directory [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
            INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
            INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
        fi
    fi
fi

# Create directories
mkdir -p "$WORKTREE_BASE"
mkdir -p "$CROSS_REPO_BASE"
mkdir -p "$CROSS_REPO_ARCHIVE"

# Copy scripts if using a different install location
if [[ "$INSTALL_DIR" != "$SCRIPT_DIR" ]]; then
    echo ""
    echo "Copying scripts to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_DIR/worktree.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/worktree.fish" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/completions.bash" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/completions.zsh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/completions.fish" "$INSTALL_DIR/"
    echo "✓ Scripts copied"
fi

# Build the config block based on shell
if [[ "$SHELL_NAME" == "fish" ]]; then
    # Fish shell config
    CONFIG="$BLOCK_START
# Installed: $(date -Iseconds)
set -gx WORKTREE_BASE \"$WORKTREE_BASE\"
set -gx CROSS_REPO_BASE \"$CROSS_REPO_BASE\"
set -gx CROSS_REPO_ARCHIVE \"$CROSS_REPO_ARCHIVE\"
"

    # Add overrides if any (fish uses individual variables)
    if [[ -n "$OVERRIDES" ]]; then
        CONFIG+="# Default branch overrides
"
        IFS=',' read -ra PAIRS <<< "$OVERRIDES"
        for pair in "${PAIRS[@]}"; do
            repo="${pair%%=*}"
            branch="${pair##*=}"
            CONFIG+="set -gx WT_DEFAULT_BRANCH_$repo \"$branch\"
"
        done
    fi

    CONFIG+="source \"$INSTALL_DIR/worktree.fish\"
source \"$INSTALL_DIR/completions.fish\"
$BLOCK_END"

else
    # Bash/Zsh config
    CONFIG="$BLOCK_START
# Installed: $(date -Iseconds)
export WORKTREE_BASE=\"$WORKTREE_BASE\"
export CROSS_REPO_BASE=\"$CROSS_REPO_BASE\"
export CROSS_REPO_ARCHIVE=\"$CROSS_REPO_ARCHIVE\"
"

    # Add overrides if any
    if [[ -n "$OVERRIDES" ]]; then
        CONFIG+="# Default branch overrides
declare -A WT_DEFAULT_BRANCH_OVERRIDES=("
        IFS=',' read -ra PAIRS <<< "$OVERRIDES"
        for pair in "${PAIRS[@]}"; do
            repo="${pair%%=*}"
            branch="${pair##*=}"
            CONFIG+="[$repo]=$branch "
        done
        CONFIG+=")
export WT_DEFAULT_BRANCH_OVERRIDES
"
    fi

    CONFIG+="source \"$INSTALL_DIR/worktree.sh\"
"

    if [[ "$SHELL_NAME" == "zsh" ]]; then
        CONFIG+="source \"$INSTALL_DIR/completions.zsh\"
"
    elif [[ "$SHELL_NAME" == "bash" ]]; then
        CONFIG+="source \"$INSTALL_DIR/completions.bash\"
"
    fi

    CONFIG+="$BLOCK_END"
fi

# Remove existing config block if present
if [[ "$EXISTING_CONFIG" == true ]]; then
    # Create backup
    cp "$RC_FILE" "$RC_FILE.bak"
    
    # Remove old block (works on both macOS and Linux)
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "/$BLOCK_START/,/$BLOCK_END/d" "$RC_FILE"
    else
        sed -i "/$BLOCK_START/,/$BLOCK_END/d" "$RC_FILE"
    fi
    echo "✓ Removed old configuration (backup: $RC_FILE.bak)"
fi

# Append new config
echo "$CONFIG" >> "$RC_FILE"

echo ""
echo "✓ Configuration added to $RC_FILE"
echo ""
echo "Run 'source $RC_FILE' or restart your shell to activate."
echo ""
echo "Commands available:"
echo "  wt-clone <url>           Clone a repo into worktree structure"
echo "  wt-new <repo> <branch>   Create a new feature worktree"
echo "  wt-cd <repo> [branch]    Navigate to a worktree"
echo "  wt-rm <repo> <branch>    Remove a worktree"
echo ""
echo "Run './setup.sh --update' to refresh scripts after git pull."
