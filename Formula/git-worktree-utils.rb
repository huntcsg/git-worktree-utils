# Homebrew formula for git-worktree-utils
#
# Users install with:
#   brew tap huntcsg/git-worktree-utils
#   brew install git-worktree-utils
#
# To release:
#   1. Create a git tag (e.g., v0.1.0)
#   2. Update the url below with the new tag
#   3. Update sha256: curl -sL <tarball-url> | shasum -a 256

class GitWorktreeUtils < Formula
  desc "Shell utilities for managing git worktrees with bare repo structure"
  homepage "https://github.com/huntcsg/git-worktree-utils"
  url "https://github.com/huntcsg/git-worktree-utils/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "395ec3fb4815166d7d9ff8b796769549fe57ee1aab099aad0eafffea60271e50"
  license "Unlicense"

  def install
    # Install scripts to share directory
    (share/"git-worktree-utils").install "worktree.sh"
    (share/"git-worktree-utils").install "worktree.fish"
    (share/"git-worktree-utils").install "completions.bash"
    (share/"git-worktree-utils").install "completions.zsh"
    (share/"git-worktree-utils").install "completions.fish"
    
    # Install setup script as a command
    (share/"git-worktree-utils").install "setup.sh"
    bin.install_symlink share/"git-worktree-utils/setup.sh" => "git-worktree-utils-setup"
  end

  def caveats
    <<~EOS
      To complete installation, run:
        git-worktree-utils-setup

      This will interactively configure your shell.

      Or manually add to your shell config:

      For zsh (~/.zshrc):
        export WORKTREE_BASE="$HOME/worktrees"
        export CROSS_REPO_BASE="$HOME/cross-repo-tasks"
        export CROSS_REPO_ARCHIVE="$HOME/cross-repo-tasks/wt-archive"
        source "$(brew --prefix)/share/git-worktree-utils/worktree.sh"
        source "$(brew --prefix)/share/git-worktree-utils/completions.zsh"

      For bash (~/.bashrc):
        export WORKTREE_BASE="$HOME/worktrees"
        export CROSS_REPO_BASE="$HOME/cross-repo-tasks"
        export CROSS_REPO_ARCHIVE="$HOME/cross-repo-tasks/wt-archive"
        source "$(brew --prefix)/share/git-worktree-utils/worktree.sh"
        source "$(brew --prefix)/share/git-worktree-utils/completions.bash"

      For fish (~/.config/fish/config.fish):
        set -gx WORKTREE_BASE "$HOME/worktrees"
        set -gx CROSS_REPO_BASE "$HOME/cross-repo-tasks"
        set -gx CROSS_REPO_ARCHIVE "$HOME/cross-repo-tasks/wt-archive"
        source "$(brew --prefix)/share/git-worktree-utils/worktree.fish"
        source "$(brew --prefix)/share/git-worktree-utils/completions.fish"
    EOS
  end

  test do
    # Verify scripts are installed
    assert_predicate share/"git-worktree-utils/worktree.sh", :exist?
    assert_predicate share/"git-worktree-utils/worktree.fish", :exist?
  end
end
