# Contributing to git-worktree-utils

Thanks for your interest in contributing! This project is released into the public domain under the Unlicense, and contributions are welcome.

## Public Domain Dedication

By contributing to this project, you agree to release your contributions into the public domain. When your first contribution is merged, please add your name to the [CONTRIBUTORS](CONTRIBUTORS) file to acknowledge this.

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone git@github.com:YOUR_USERNAME/git-worktree-utils.git
   cd git-worktree-utils
   ```
3. Test your changes by sourcing the scripts directly:
   ```bash
   export WORKTREE_BASE="/tmp/test-worktrees"
   export CROSS_REPO_BASE="/tmp/test-tasks"
   source ./worktree.sh
   source ./completions.bash  # or .zsh
   ```

## Project Structure

```
git-worktree-utils/
├── worktree.sh          # Main functions (bash/zsh)
├── worktree.fish        # Main functions (fish)
├── completions.bash     # Bash completions
├── completions.zsh      # Zsh completions
├── completions.fish     # Fish completions
├── setup.sh             # Interactive setup script
└── Formula/             # Homebrew formula
```

## Making Changes

### Shell Scripts

- Keep bash and fish implementations in sync
- Use the `_wt_` prefix for internal helper functions
- Use `_wt_branch_to_dir` / `_wt_dir_to_branch` for branch name ↔ directory conversions
- Test with branch names containing `/` (e.g., `feature/my-thing`)

### Completions

- Keep all three completion files (bash, zsh, fish) in sync
- Completions should show branch names, not directory names
- Use the `_wt_dir_to_branch` helper to convert directory names back to branch names

### Setup Script

- Maintain idempotency — running setup multiple times should work safely
- Use the block markers (`# >>> git-worktree-utils >>>`) for config sections
- Test the `--update` flag

## Testing

There's no formal test suite yet. Please manually test:

1. Fresh install with `./setup.sh`
2. Re-running `./setup.sh` (idempotency)
3. Running `./setup.sh --update`
4. All shells you have access to (bash, zsh, fish)
5. Tab completion for all commands
6. Branch names with slashes (e.g., `feature/foo`)

## Submitting Changes

1. Create a branch for your changes
2. Make your changes with clear commit messages
3. **Add yourself to the [CONTRIBUTORS](CONTRIBUTORS) file** (required)
4. Open a pull request

**Important:** All contributions require adding your name to CONTRIBUTORS. This attests that you release your contributions into the public domain under the Unlicense. Pull requests without this will not be accepted.

## Code Style

- No strict style guide, but match existing code
- Prefer clarity over cleverness
- Add comments only when the code isn't self-explanatory
- Keep functions focused and small

## Questions?

Open an issue if you have questions or want to discuss a change before implementing it.
