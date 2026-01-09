# Git Worktree Utilities for PowerShell
# Dot-source this file in your PowerShell profile to enable worktree commands.
#
# Required environment variables:
#   $env:WORKTREE_BASE       - Directory containing bare repos (e.g., ~/worktrees)
#   $env:CROSS_REPO_BASE     - Directory for cross-repo task symlinks (e.g., ~/cross-repo-tasks)
#   $env:CROSS_REPO_ARCHIVE  - Directory for archived tasks (e.g., ~/cross-repo-tasks/wt-archive)
#
# Optional configuration (in your $PROFILE after sourcing this file):
#   Set-WtConfig -DefaultBranchOverrides @{ myrepo = 'master'; legacy = 'develop' }

# Ensure required vars are set
if (-not $env:WORKTREE_BASE) {
    throw "WORKTREE_BASE must be set"
}
if (-not $env:CROSS_REPO_BASE) {
    throw "CROSS_REPO_BASE must be set"
}
if (-not $env:CROSS_REPO_ARCHIVE) {
    throw "CROSS_REPO_ARCHIVE must be set"
}

# ===========================
# Module-scoped configuration
# ===========================

$script:WtConfig = @{
    DefaultBranchOverrides = @{}
}

function Get-WtConfig {
    <#
    .SYNOPSIS
    Gets the current git-worktree-utils configuration.
    #>
    [CmdletBinding()]
    param()
    return $script:WtConfig.Clone()
}

function Set-WtConfig {
    <#
    .SYNOPSIS
    Sets git-worktree-utils configuration options.
    
    .DESCRIPTION
    This function only modifies in-memory configuration, not system state.
    
    .PARAMETER DefaultBranchOverrides
    Hashtable mapping repo names to their default branch (e.g., @{ myrepo = 'master' })
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only modifies in-memory configuration, not system state'
    )]
    [CmdletBinding()]
    param(
        [hashtable]$DefaultBranchOverrides
    )
    
    if ($PSBoundParameters.ContainsKey('DefaultBranchOverrides')) {
        $script:WtConfig.DefaultBranchOverrides = $DefaultBranchOverrides
    }
}

# ===========================
# Output helper (centralizes Write-Host usage)
# ===========================

function Write-WtStatus {
    <#
    .SYNOPSIS
    Writes a status message to the console with optional coloring.
    This is a CLI-oriented helper for user-facing status messages.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'CLI tool requires colored console output for user feedback'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    switch ($Level) {
        'Success' { Write-Host $Message -ForegroundColor Green }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        default   { Write-Host $Message }
    }
}

# ===========================
# Internal helper functions
# ===========================

function script:ConvertTo-WorktreeDir {
    param([string]$Branch)
    return $Branch -replace '/', '__'
}

function script:ConvertFrom-WorktreeDir {
    param([string]$DirName)
    return $DirName -replace '__', '/'
}

function script:Get-DefaultBranch {
    param([string]$Repo)
    
    $repoLower = $Repo.ToLower()
    $repoPath = Join-Path $env:WORKTREE_BASE $repoLower
    
    # Check for configured override first
    if ($script:WtConfig.DefaultBranchOverrides.ContainsKey($repoLower)) {
        return $script:WtConfig.DefaultBranchOverrides[$repoLower]
    }
    
    # Try to auto-detect from origin/HEAD
    $barePath = Join-Path $repoPath '.bare'
    if (Test-Path $barePath -PathType Container) {
        $detected = git -C $barePath symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($detected) {
            return ($detected -replace 'refs/remotes/origin/', '')
        }
    }
    
    # Fallback to main
    return 'main'
}

# ===========================
# Core functions with approved verbs
# ===========================

function Get-WorktreeRepo {
    <#
    .SYNOPSIS
    Lists available worktree repositories.
    
    .DESCRIPTION
    Returns repository names from WORKTREE_BASE that have the bare repo structure.
    #>
    [CmdletBinding()]
    param()
    
    $basePath = $env:WORKTREE_BASE
    if (Test-Path $basePath) {
        Get-ChildItem -Path $basePath -Directory | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName '.bare') -PathType Container) {
                $_.Name
            }
        }
    }
}

function Copy-WorktreeFromRemote {
    <#
    .SYNOPSIS
    Clones a remote repo into the worktree structure.
    
    .DESCRIPTION
    Creates a bare repo clone with worktree support at WORKTREE_BASE.
    
    .EXAMPLE
    Copy-WorktreeFromRemote -Url git@github.com:user/repo.git
    
    .EXAMPLE
    wt-clone git@github.com:user/repo.git my-custom-name
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Url,
        
        [Parameter(Position = 1)]
        [string]$Name
    )
    
    # Extract repo name from URL if not provided
    if (-not $Name) {
        $Name = [System.IO.Path]::GetFileNameWithoutExtension($Url) -replace '\.git$', ''
        if ($Name -eq '') {
            $Name = ($Url -split '/')[-1] -replace '\.git$', ''
        }
    }
    
    $repoPath = Join-Path $env:WORKTREE_BASE $Name
    
    if (Test-Path $repoPath) {
        Write-Error "Error: $repoPath already exists"
        return
    }
    
    Write-WtStatus "Cloning $Url into $repoPath..."
    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    Push-Location $repoPath
    
    try {
        # Clone as bare repo
        git clone --bare $Url .bare
        
        # Create .git pointer
        Set-Content -Path '.git' -Value 'gitdir: ./.bare'
        
        # Configure fetch to get all branches
        git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
        
        # Fetch all branches
        git fetch origin
        
        # Detect default branch
        $defaultBranch = git symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($defaultBranch) {
            $defaultBranch = $defaultBranch -replace 'refs/remotes/origin/', ''
        }
        if (-not $defaultBranch) {
            $remoteInfo = git remote show origin 2>$null
            $headLine = $remoteInfo | Where-Object { $_ -match 'HEAD branch' }
            if ($headLine) {
                $defaultBranch = ($headLine -split ':')[-1].Trim()
            }
        }
        if (-not $defaultBranch) {
            $defaultBranch = 'main'
        }
        
        # Create default branch worktree
        git worktree add $defaultBranch $defaultBranch
        
        Set-Location $defaultBranch
        Write-WtStatus "`n✓ Cloned $Name (default branch: $defaultBranch)" -Level Success
        Write-WtStatus "  Repo path: $repoPath"
        Write-WtStatus "  Worktree:  $repoPath\$defaultBranch"
    }
    finally {
        Pop-Location
        Set-Location (Join-Path $repoPath $defaultBranch)
    }
}

function Initialize-WorktreeRepo {
    <#
    .SYNOPSIS
    Initializes a new local repo in the worktree structure.
    
    .EXAMPLE
    Initialize-WorktreeRepo -Name my-project
    
    .EXAMPLE
    wt-init my-project develop
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        
        [Parameter(Position = 1)]
        [string]$DefaultBranch = 'main'
    )
    
    $repoPath = Join-Path $env:WORKTREE_BASE $Name
    
    if (Test-Path $repoPath) {
        Write-Error "Error: $repoPath already exists"
        return
    }
    
    Write-WtStatus "Initializing new repo at $repoPath..."
    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    Push-Location $repoPath
    
    try {
        git init --bare .bare
        Set-Content -Path '.git' -Value 'gitdir: ./.bare'
        git symbolic-ref HEAD "refs/heads/$DefaultBranch"
        git worktree add $DefaultBranch
        Set-Location $DefaultBranch
        git commit --allow-empty -m 'Initial commit'
        
        Write-WtStatus "`n✓ Initialized $Name (default branch: $DefaultBranch)" -Level Success
        Write-WtStatus "  Repo path: $repoPath"
        Write-WtStatus "  Worktree:  $repoPath\$DefaultBranch"
        Write-WtStatus "`nNext: Add a remote with 'git remote add origin <url>'"
    }
    finally {
        Pop-Location
        Set-Location (Join-Path $repoPath $DefaultBranch)
    }
}

function New-Worktree {
    <#
    .SYNOPSIS
    Creates a new feature worktree branched from the default branch.
    
    .EXAMPLE
    New-Worktree -Repo myrepo -Branch feature/new-thing
    
    .EXAMPLE
    wt-new myrepo feature/new-thing
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Repo,
        
        [Parameter(Mandatory, Position = 1)]
        [string]$Branch
    )
    
    $repoPath = Join-Path $env:WORKTREE_BASE $Repo
    $defaultBranch = Get-DefaultBranch $Repo
    $branchDir = ConvertTo-WorktreeDir $Branch
    $defaultBranchDir = ConvertTo-WorktreeDir $defaultBranch
    
    if (-not (Test-Path (Join-Path $repoPath '.bare') -PathType Container)) {
        Write-Error "Error: Repository '$Repo' not found at $repoPath"
        return
    }
    
    $worktreePath = Join-Path $repoPath $branchDir
    if (-not $PSCmdlet.ShouldProcess($worktreePath, "Create worktree for branch '$Branch'")) {
        return
    }
    
    Push-Location $repoPath
    
    try {
        $defaultWorktree = Join-Path $repoPath $defaultBranchDir
        git -C $defaultWorktree fetch origin
        git -C $defaultWorktree reset --hard "origin/$defaultBranch"
        git worktree add $branchDir -b $Branch $defaultBranch
        
        Set-Location $branchDir
        Write-WtStatus "Created worktree: $repoPath\$branchDir (branch: $Branch)"
    }
    finally {
        Pop-Location
        Set-Location (Join-Path $repoPath $branchDir)
    }
}

function Resume-Worktree {
    <#
    .SYNOPSIS
    Creates a worktree from an existing remote branch.
    
    .EXAMPLE
    Resume-Worktree -Repo myrepo -Branch feature/existing
    
    .EXAMPLE
    wt-continue myrepo feature/existing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Repo,
        
        [Parameter(Mandatory, Position = 1)]
        [string]$Branch
    )
    
    $repoPath = Join-Path $env:WORKTREE_BASE $Repo
    $branchDir = ConvertTo-WorktreeDir $Branch
    $defaultBranch = Get-DefaultBranch $Repo
    $defaultBranchDir = ConvertTo-WorktreeDir $defaultBranch
    
    if (-not (Test-Path (Join-Path $repoPath '.bare') -PathType Container)) {
        Write-Error "Error: Repository '$Repo' not found at $repoPath"
        return
    }
    
    Push-Location $repoPath
    
    try {
        $defaultWorktree = Join-Path $repoPath $defaultBranchDir
        git -C $defaultWorktree fetch origin
        
        $remoteRef = git show-ref --verify "refs/remotes/origin/$Branch" 2>$null
        if (-not $remoteRef) {
            Write-Error "Error: Remote branch 'origin/$Branch' does not exist"
            Write-WtStatus "Available remote branches:"
            git branch -r | Where-Object { $_ -notmatch 'HEAD' } | Select-Object -First 10
            return
        }
        
        $localRef = git show-ref --verify "refs/heads/$Branch" 2>$null
        if ($localRef) {
            Write-WtStatus "Deleting stale local branch '$Branch'..."
            git branch -D $Branch
        }
        
        git worktree add -b $Branch $branchDir "origin/$Branch"
        
        Set-Location $branchDir
        Write-WtStatus "Created worktree: $repoPath\$branchDir (tracking origin/$Branch)"
    }
    finally {
        Pop-Location
        Set-Location (Join-Path $repoPath $branchDir)
    }
}

function Remove-Worktree {
    <#
    .SYNOPSIS
    Removes a feature worktree.
    
    .EXAMPLE
    Remove-Worktree -Repo myrepo -Branch feature/done
    
    .EXAMPLE
    wt-rm myrepo feature/done -Yes
    
    .EXAMPLE
    wt-rm .  # Auto-detect from current directory
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Repo,
        
        [Parameter(Position = 1)]
        [string]$Branch,
        
        [switch]$Yes
    )
    
    # Handle "." for current directory
    if ($Repo -eq '.') {
        $currentPath = Get-Location
        $worktreeBase = $env:WORKTREE_BASE
        
        if ($currentPath.Path -notlike "$worktreeBase*") {
            Write-Error "Error: Not inside WORKTREE_BASE ($worktreeBase)"
            return
        }
        
        $relativePath = $currentPath.Path.Substring($worktreeBase.Length).TrimStart('\', '/')
        $parts = $relativePath -split '[\\/]', 2
        
        if ($parts.Count -lt 2) {
            Write-Error "Error: Cannot determine repo/branch from current directory"
            return
        }
        
        $Repo = $parts[0]
        $branchDir = $parts[1]
        $Branch = ConvertFrom-WorktreeDir $branchDir
        
        Write-WtStatus "Detected: repo=$Repo, branch=$Branch"
    }
    
    if (-not $Branch) {
        Write-WtStatus "Usage: Remove-Worktree <repo> <branch> [-Yes]"
        Write-WtStatus "       Remove-Worktree . [-Yes]"
        return
    }
    
    $repoPath = Join-Path $env:WORKTREE_BASE $Repo
    $branchDir = ConvertTo-WorktreeDir $Branch
    $worktreePath = Join-Path $repoPath $branchDir
    $defaultBranch = Get-DefaultBranch $Repo
    
    if ($Branch -eq $defaultBranch) {
        Write-Error "Error: Cannot remove the default branch worktree ($defaultBranch)"
        return
    }
    
    if (-not (Test-Path $worktreePath -PathType Container)) {
        Write-Error "Error: Worktree not found at $worktreePath"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess($worktreePath, "Remove worktree for branch '$Branch'")) {
        return
    }
    
    if ((Get-Location).Path -like "$worktreePath*") {
        Set-Location $repoPath
    }
    
    Push-Location $repoPath
    
    try {
        git worktree remove $branchDir --force
        Write-WtStatus "Removed worktree: $worktreePath"
        
        $deleteBranch = $false
        if ($Yes) {
            $deleteBranch = $true
        }
        else {
            $response = Read-Host "Delete branch '$Branch'? [y/N]"
            $deleteBranch = $response -match '^[Yy]'
        }
        
        if ($deleteBranch) {
            git branch -D $Branch 2>$null
            Write-WtStatus "Deleted branch: $Branch"
        }
    }
    finally {
        Pop-Location
    }
}

function Get-WorktreeList {
    <#
    .SYNOPSIS
    Lists worktrees for a repository.
    
    .EXAMPLE
    Get-WorktreeList -Repo myrepo
    
    .EXAMPLE
    wt-ls myrepo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Repo
    )
    
    $repoPath = Join-Path $env:WORKTREE_BASE $Repo
    
    if (-not (Test-Path (Join-Path $repoPath '.bare') -PathType Container)) {
        Write-Error "Error: Repository '$Repo' not found at $repoPath"
        return
    }
    
    Push-Location $repoPath
    try {
        git worktree list
    }
    finally {
        Pop-Location
    }
}

function Set-WorktreeLocation {
    <#
    .SYNOPSIS
    Changes to a worktree directory.
    
    .DESCRIPTION
    This function only changes the current directory, it does not modify system state.
    
    .EXAMPLE
    Set-WorktreeLocation -Repo myrepo -Branch main
    
    .EXAMPLE
    wt-cd myrepo main
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only changes current directory, not system state'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Repo,
        
        [Parameter(Position = 1)]
        [string]$Branch
    )
    
    if ($Branch) {
        $branchDir = ConvertTo-WorktreeDir $Branch
        Set-Location (Join-Path $env:WORKTREE_BASE $Repo $branchDir)
    }
    else {
        Set-Location (Join-Path $env:WORKTREE_BASE $Repo)
    }
}

function Update-WorktreeDefault {
    <#
    .SYNOPSIS
    Updates the default branch for a repo to match origin.
    
    .EXAMPLE
    Update-WorktreeDefault -Repo myrepo
    
    .EXAMPLE
    wt-update myrepo
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Repo
    )
    
    $repoPath = Join-Path $env:WORKTREE_BASE $Repo
    $defaultBranch = Get-DefaultBranch $Repo
    $defaultBranchDir = ConvertTo-WorktreeDir $defaultBranch
    $defaultWorktree = Join-Path $repoPath $defaultBranchDir
    
    if (-not $PSCmdlet.ShouldProcess($defaultWorktree, "Reset to origin/$defaultBranch")) {
        return
    }
    
    Push-Location $defaultWorktree
    try {
        git fetch origin
        git reset --hard "origin/$defaultBranch"
        Write-WtStatus "Updated $Repo/$defaultBranch to origin/$defaultBranch"
    }
    finally {
        Pop-Location
    }
}

function Invoke-WorktreeRebase {
    <#
    .SYNOPSIS
    Rebases the current feature branch onto the updated default branch.
    
    .DESCRIPTION
    Run from within a feature worktree. Updates the default branch first.
    
    .EXAMPLE
    wt-rebase
    #>
    [CmdletBinding()]
    param()
    
    $currentDir = Get-Location
    $repoRoot = Split-Path $currentDir -Parent
    $repoName = Split-Path $repoRoot -Leaf
    $defaultBranch = Get-DefaultBranch $repoName
    $defaultBranchDir = ConvertTo-WorktreeDir $defaultBranch
    $defaultWorktree = Join-Path $repoRoot $defaultBranchDir
    
    Push-Location $defaultWorktree
    try {
        git fetch origin
        git reset --hard "origin/$defaultBranch"
    }
    finally {
        Pop-Location
    }
    
    Set-Location $currentDir
    git rebase -i $defaultBranch
}

# ===========================
# Cross-repo task functions
# ===========================

function New-WorktreeTask {
    <#
    .SYNOPSIS
    Creates worktrees across multiple repos for a single task.
    
    .EXAMPLE
    New-WorktreeTask -Branch auth-fix -Repos backend,frontend,api
    
    .EXAMPLE
    wt-multi-new auth-fix backend frontend api
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Branch,
        
        [Parameter(Mandatory, Position = 1, ValueFromRemainingArguments)]
        [string[]]$Repos
    )
    
    $branchDir = ConvertTo-WorktreeDir $Branch
    $taskDir = Join-Path $env:CROSS_REPO_BASE $branchDir
    
    if (-not $PSCmdlet.ShouldProcess($taskDir, "Create multi-repo task '$Branch' with repos: $($Repos -join ', ')")) {
        return
    }
    
    New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
    
    foreach ($repo in $Repos) {
        Write-WtStatus "Creating worktree for $repo..."
        
        $worktreePath = Join-Path $env:WORKTREE_BASE $repo $branchDir
        
        Push-Location (Join-Path $env:WORKTREE_BASE $repo)
        try {
            New-Worktree $repo $Branch 2>$null
        }
        catch {
            if (Test-Path $worktreePath -PathType Container) {
                Write-WtStatus "  Worktree already exists"
            }
            else {
                Write-WtStatus "  Failed to create worktree for $repo" -Level Warning
                continue
            }
        }
        finally {
            Pop-Location
        }
        
        $linkPath = Join-Path $taskDir $repo
        if (-not (Test-Path $linkPath)) {
            try {
                New-Item -ItemType SymbolicLink -Path $linkPath -Target $worktreePath -Force | Out-Null
                Write-WtStatus "  ✓ $repo" -Level Success
            }
            catch {
                Write-WtStatus "  Failed to create symlink (may need admin/Developer Mode): $_" -Level Warning
            }
        }
    }
    
    Write-WtStatus "`nTask directory: $taskDir"
    Get-ChildItem $taskDir
    Set-Location $taskDir
}

function Add-WorktreeTaskRepo {
    <#
    .SYNOPSIS
    Adds repos to an existing cross-repo task.
    
    .EXAMPLE
    Add-WorktreeTaskRepo -Branch auth-fix -Repos api
    
    .EXAMPLE
    wt-multi-add auth-fix api
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Branch,
        
        [Parameter(Mandatory, Position = 1, ValueFromRemainingArguments)]
        [string[]]$Repos
    )
    
    $branchDir = ConvertTo-WorktreeDir $Branch
    $taskDir = Join-Path $env:CROSS_REPO_BASE $branchDir
    
    if (-not (Test-Path $taskDir -PathType Container)) {
        Write-Error "Task '$Branch' not found at $taskDir"
        Write-WtStatus "Use New-WorktreeTask to create a new task"
        return
    }
    
    foreach ($repo in $Repos) {
        Write-WtStatus "Adding $repo to task..."
        
        $linkPath = Join-Path $taskDir $repo
        
        if (Test-Path $linkPath) {
            Write-WtStatus "  $repo already in task"
            continue
        }
        
        $worktreePath = Join-Path $env:WORKTREE_BASE $repo $branchDir
        
        try {
            New-Worktree $repo $Branch 2>$null
        }
        catch {
            if (Test-Path $worktreePath -PathType Container) {
                Write-WtStatus "  Worktree already exists"
            }
            else {
                Write-WtStatus "  Failed to create worktree for $repo" -Level Warning
                continue
            }
        }
        
        try {
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $worktreePath -Force | Out-Null
            Write-WtStatus "  ✓ $repo" -Level Success
        }
        catch {
            Write-WtStatus "  Failed to create symlink (may need admin/Developer Mode): $_" -Level Warning
        }
    }
    
    Write-WtStatus "`nTask directory: $taskDir"
    Get-ChildItem $taskDir
}

function Remove-WorktreeTask {
    <#
    .SYNOPSIS
    Removes a multi-repo task (archives instead of deleting).
    
    .EXAMPLE
    Remove-WorktreeTask -Branch auth-fix
    
    .EXAMPLE
    wt-multi-rm auth-fix
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Branch
    )
    
    $branchDir = ConvertTo-WorktreeDir $Branch
    $taskDir = Join-Path $env:CROSS_REPO_BASE $branchDir
    
    if (-not (Test-Path $taskDir -PathType Container)) {
        Write-Error "Task '$Branch' not found at $taskDir"
        return
    }
    
    if (-not $PSCmdlet.ShouldProcess($taskDir, "Remove/archive multi-repo task '$Branch'")) {
        return
    }
    
    Write-WtStatus "Archiving task: $Branch"
    
    Get-ChildItem $taskDir | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $repo = $_.Name
            Write-WtStatus "Removing worktree: $repo/$Branch"
            Remove-Item $_.FullName -Force
            $null = 'n' | Remove-Worktree $repo $Branch 2>$null
        }
    }
    
    $remainingFiles = Get-ChildItem $taskDir -Force | Where-Object { $_.Name -ne '.DS_Store' }
    
    if ($remainingFiles) {
        New-Item -ItemType Directory -Path $env:CROSS_REPO_ARCHIVE -Force | Out-Null
        $archiveDest = Join-Path $env:CROSS_REPO_ARCHIVE $branchDir
        
        if (Test-Path $archiveDest) {
            $n = 1
            while (Test-Path "$archiveDest.$n") {
                $n++
            }
            $archiveDest = "$archiveDest.$n"
        }
        
        Move-Item $taskDir $archiveDest
        Write-WtStatus "✓ Task archived to: $archiveDest" -Level Success
    }
    else {
        Remove-Item $taskDir -Recurse -Force
        Write-WtStatus "✓ Task removed" -Level Success
    }
}

function Get-WorktreeTask {
    <#
    .SYNOPSIS
    Lists all cross-repo tasks.
    
    .EXAMPLE
    Get-WorktreeTask
    
    .EXAMPLE
    wt-multi-ls
    #>
    [CmdletBinding()]
    param()
    
    if (-not (Test-Path $env:CROSS_REPO_BASE -PathType Container)) {
        Write-WtStatus "No cross-repo tasks found"
        return
    }
    
    Write-WtStatus "Cross-repo tasks:"
    Get-ChildItem $env:CROSS_REPO_BASE -Directory | ForEach-Object {
        $task = $_.Name
        $repos = (Get-ChildItem $_.FullName -Name) -join ' '
        Write-WtStatus "  $task`: $repos"
    }
}

function Set-WorktreeTaskLocation {
    <#
    .SYNOPSIS
    Changes to a cross-repo task directory.
    
    .DESCRIPTION
    This function only changes the current directory, it does not modify system state.
    
    .EXAMPLE
    Set-WorktreeTaskLocation -Branch auth-fix
    
    .EXAMPLE
    wt-multi-cd auth-fix
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only changes current directory, not system state'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Branch
    )
    
    $branchDir = ConvertTo-WorktreeDir $Branch
    Set-Location (Join-Path $env:CROSS_REPO_BASE $branchDir)
}

# ===========================
# Aliases for CLI compatibility
# ===========================

Set-Alias -Name wt-clone    -Value Copy-WorktreeFromRemote
Set-Alias -Name wt-init     -Value Initialize-WorktreeRepo
Set-Alias -Name wt-new      -Value New-Worktree
Set-Alias -Name wt-continue -Value Resume-Worktree
Set-Alias -Name wt-rm       -Value Remove-Worktree
Set-Alias -Name wt-ls       -Value Get-WorktreeList
Set-Alias -Name wt-cd       -Value Set-WorktreeLocation
Set-Alias -Name wt-update   -Value Update-WorktreeDefault
Set-Alias -Name wt-rebase   -Value Invoke-WorktreeRebase

Set-Alias -Name wt-multi-new -Value New-WorktreeTask
Set-Alias -Name wt-multi-add -Value Add-WorktreeTaskRepo
Set-Alias -Name wt-multi-rm  -Value Remove-WorktreeTask
Set-Alias -Name wt-multi-ls  -Value Get-WorktreeTask
Set-Alias -Name wt-multi-cd  -Value Set-WorktreeTaskLocation

# Note: Functions and aliases are automatically available when dot-sourced.
# No Export-ModuleMember needed (only works in .psm1 module files).
