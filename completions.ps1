# PowerShell completions for git-worktree-utils
# Dot-source this file after worktree.ps1 in your PowerShell profile

# Helper: convert directory name back to branch name (feature__foo -> feature/foo)
function script:ConvertFrom-WorktreeDirCompletion {
    param([string]$DirName)
    return $DirName -replace '__', '/'
}

# Helper: convert branch name to directory name (feature/foo -> feature__foo)
function script:ConvertTo-WorktreeDirCompletion {
    param([string]$Branch)
    return $Branch -replace '/', '__'
}

# Helper: list repos
function script:Get-WtRepoCompletion {
    if ($env:WORKTREE_BASE -and (Test-Path $env:WORKTREE_BASE)) {
        Get-ChildItem -Path $env:WORKTREE_BASE -Directory | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName '.bare') -PathType Container) {
                $_.Name
            }
        }
    }
}

# Helper: list branches for a repo
function script:Get-WtBranchCompletion {
    param([string]$Repo)
    $repoPath = Join-Path $env:WORKTREE_BASE $Repo
    if (Test-Path $repoPath) {
        Get-ChildItem -Path $repoPath -Directory | Where-Object { 
            $_.Name -ne '.bare' -and -not $_.Name.StartsWith('.')
        } | ForEach-Object {
            ConvertFrom-WorktreeDirCompletion $_.Name
        }
    }
}

# Helper: list tasks
function script:Get-WtTaskCompletion {
    if ($env:CROSS_REPO_BASE -and (Test-Path $env:CROSS_REPO_BASE)) {
        Get-ChildItem -Path $env:CROSS_REPO_BASE -Directory | ForEach-Object {
            ConvertFrom-WorktreeDirCompletion $_.Name
        }
    }
}

# Helper: list remote branches for a repo
function script:Get-WtRemoteBranchCompletion {
    param([string]$Repo)
    $repoPath = Join-Path $env:WORKTREE_BASE $Repo
    
    # Get default branch to find a worktree to run git from
    $defaultBranch = 'main'
    $barePath = Join-Path $repoPath '.bare'
    if (Test-Path $barePath -PathType Container) {
        $detected = git -C $barePath symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($detected) {
            $defaultBranch = $detected -replace 'refs/remotes/origin/', ''
        }
    }
    
    $defaultBranchDir = ConvertTo-WorktreeDirCompletion $defaultBranch
    $worktreePath = Join-Path $repoPath $defaultBranchDir
    
    if (Test-Path $worktreePath) {
        $remoteBranches = git -C $worktreePath branch -r 2>$null
        if ($remoteBranches) {
            $remoteBranches | Where-Object { $_ -notmatch 'HEAD' } | ForEach-Object {
                $branch = ($_ -replace 'origin/', '').Trim()
                if ($branch) { $branch }
            }
        }
    }
}

# Factory function to create completion scriptblocks
# This avoids repeating the unused parameter handling pattern
function script:New-RepoCompleter {
    return {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # Mark unused parameters as intentionally ignored (required signature)
        $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters
        
        Get-WtRepoCompletion | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

function script:New-BranchCompleter {
    return {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $null = $commandName, $parameterName, $commandAst
        
        $repo = $fakeBoundParameters['Repo']
        if ($repo) {
            Get-WtBranchCompletion $repo | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }
}

function script:New-TaskCompleter {
    return {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters
        
        Get-WtTaskCompletion | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# ===========================
# Set-WorktreeLocation / wt-cd: repo then branch
# ===========================
Register-ArgumentCompleter -CommandName 'Set-WorktreeLocation', 'wt-cd' -ParameterName 'Repo' -ScriptBlock (New-RepoCompleter)
Register-ArgumentCompleter -CommandName 'Set-WorktreeLocation', 'wt-cd' -ParameterName 'Branch' -ScriptBlock (New-BranchCompleter)

# ===========================
# New-Worktree / wt-new: repo only (branch is user-provided)
# ===========================
Register-ArgumentCompleter -CommandName 'New-Worktree', 'wt-new' -ParameterName 'Repo' -ScriptBlock (New-RepoCompleter)

# ===========================
# Resume-Worktree / wt-continue: repo then remote branch
# ===========================
Register-ArgumentCompleter -CommandName 'Resume-Worktree', 'wt-continue' -ParameterName 'Repo' -ScriptBlock (New-RepoCompleter)

Register-ArgumentCompleter -CommandName 'Resume-Worktree', 'wt-continue' -ParameterName 'Branch' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $null = $commandName, $parameterName, $commandAst
    
    $repo = $fakeBoundParameters['Repo']
    if ($repo) {
        Get-WtRemoteBranchCompletion $repo | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# ===========================
# Remove-Worktree / wt-rm: repo then branch
# ===========================
Register-ArgumentCompleter -CommandName 'Remove-Worktree', 'wt-rm' -ParameterName 'Repo' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters
    
    # Include "." as an option for current directory
    $options = @('.') + @(Get-WtRepoCompletion)
    $options | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName 'Remove-Worktree', 'wt-rm' -ParameterName 'Branch' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $null = $commandName, $parameterName, $commandAst
    
    $repo = $fakeBoundParameters['Repo']
    if ($repo -and $repo -ne '.') {
        Get-WtBranchCompletion $repo | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# ===========================
# Get-WorktreeList / wt-ls: repo only
# ===========================
Register-ArgumentCompleter -CommandName 'Get-WorktreeList', 'wt-ls' -ParameterName 'Repo' -ScriptBlock (New-RepoCompleter)

# ===========================
# Update-WorktreeDefault / wt-update: repo only
# ===========================
Register-ArgumentCompleter -CommandName 'Update-WorktreeDefault', 'wt-update' -ParameterName 'Repo' -ScriptBlock (New-RepoCompleter)

# ===========================
# Copy-WorktreeFromRemote / wt-clone: no completion (URL is user input)
# ===========================

# ===========================
# Initialize-WorktreeRepo / wt-init: no completion (name is user input)
# ===========================

# ===========================
# New-WorktreeTask / wt-multi-new: repos (branch is first arg, user-provided)
# ===========================
Register-ArgumentCompleter -CommandName 'New-WorktreeTask', 'wt-multi-new' -ParameterName 'Repos' -ScriptBlock (New-RepoCompleter)

# ===========================
# Add-WorktreeTaskRepo / wt-multi-add: task then repos
# ===========================
Register-ArgumentCompleter -CommandName 'Add-WorktreeTaskRepo', 'wt-multi-add' -ParameterName 'Branch' -ScriptBlock (New-TaskCompleter)
Register-ArgumentCompleter -CommandName 'Add-WorktreeTaskRepo', 'wt-multi-add' -ParameterName 'Repos' -ScriptBlock (New-RepoCompleter)

# ===========================
# Set-WorktreeTaskLocation / wt-multi-cd: task only
# ===========================
Register-ArgumentCompleter -CommandName 'Set-WorktreeTaskLocation', 'wt-multi-cd' -ParameterName 'Branch' -ScriptBlock (New-TaskCompleter)

# ===========================
# Remove-WorktreeTask / wt-multi-rm: task only
# ===========================
Register-ArgumentCompleter -CommandName 'Remove-WorktreeTask', 'wt-multi-rm' -ParameterName 'Branch' -ScriptBlock (New-TaskCompleter)
