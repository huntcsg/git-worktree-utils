# Setup script for git-worktree-utils (PowerShell)
# Run this to configure your PowerShell profile
#
# Usage:
#   .\setup.ps1           # Interactive setup
#   .\setup.ps1 -Update   # Update existing config (re-copy scripts if relocated)

# Suppress Write-Host warning - this is an interactive setup script that requires console output
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'Interactive setup script requires direct console output for user prompts'
)]
[CmdletBinding()]
param(
    [switch]$Update
)

$ErrorActionPreference = 'Stop'

# Configuration block markers (used for idempotent updates)
$BlockStart = '# >>> git-worktree-utils >>>'
$BlockEnd = '# <<< git-worktree-utils <<<'

# Default install location
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA 'git-worktree-utils'

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host 'Git Worktree Utils Setup (PowerShell)' -ForegroundColor Cyan
Write-Host '======================================' -ForegroundColor Cyan
Write-Host ''

# Ensure profile directory exists
$ProfileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

# Ensure profile file exists
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    Write-Host "Created new profile at: $PROFILE"
}

Write-Host "PowerShell profile: $PROFILE"

# Check for existing config
$profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
$ExistingConfig = $profileContent -and $profileContent.Contains($BlockStart)

# Helper function to extract current value from existing config
function Get-ExistingValue {
    param(
        [string]$Pattern,
        [string]$Default
    )
    
    if ($ExistingConfig) {
        $match = [regex]::Match($profileContent, $Pattern)
        if ($match.Success -and $match.Groups.Count -gt 1) {
            return $match.Groups[1].Value
        }
    }
    return $Default
}

# Get current install dir if exists
function Get-ExistingInstallDir {
    if ($ExistingConfig) {
        $match = [regex]::Match($profileContent, '\.\s+"([^"]+)\\worktree\.ps1"')
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }
    return $null
}

# Default values
$DefaultWorktreeBase = Join-Path $HOME 'worktrees'
$DefaultCrossRepoBase = Join-Path $HOME 'cross-repo-tasks'

if ($ExistingConfig) {
    Write-Host ''
    Write-Host 'Existing configuration found in profile' -ForegroundColor Yellow
    
    if ($Update) {
        Write-Host 'Running in update mode...'
    }
    else {
        $confirm = Read-Host 'Update existing configuration? [Y/n]'
        if ($confirm -match '^[Nn]') {
            Write-Host 'Aborted.'
            exit 0
        }
    }
    
    # Get existing values as defaults
    $DefaultWorktreeBase = Get-ExistingValue '\$env:WORKTREE_BASE\s*=\s*"([^"]+)"' $DefaultWorktreeBase
    $DefaultCrossRepoBase = Get-ExistingValue '\$env:CROSS_REPO_BASE\s*=\s*"([^"]+)"' $DefaultCrossRepoBase
    $DefaultCrossRepoArchive = Get-ExistingValue '\$env:CROSS_REPO_ARCHIVE\s*=\s*"([^"]+)"' ''
    $CurrentInstallDir = Get-ExistingInstallDir
}
else {
    $DefaultCrossRepoArchive = ''
    $CurrentInstallDir = $null
}

Write-Host ''

# In update mode with existing config, skip prompts
if ($Update -and $ExistingConfig) {
    $WorktreeBase = $DefaultWorktreeBase
    $CrossRepoBase = $DefaultCrossRepoBase
    $CrossRepoArchive = if ($DefaultCrossRepoArchive) { $DefaultCrossRepoArchive } else { Join-Path $CrossRepoBase 'wt-archive' }
    $InstallDir = if ($CurrentInstallDir) { $CurrentInstallDir } else { $ScriptDir }
    $Overrides = @{}
}
else {
    # Get worktree base directory
    $WorktreeBase = Read-Host "Worktree base directory [$DefaultWorktreeBase]"
    if (-not $WorktreeBase) { $WorktreeBase = $DefaultWorktreeBase }
    $WorktreeBase = $WorktreeBase -replace '^~', $HOME
    
    # Get cross-repo base directory
    $CrossRepoBase = Read-Host "Cross-repo tasks directory [$DefaultCrossRepoBase]"
    if (-not $CrossRepoBase) { $CrossRepoBase = $DefaultCrossRepoBase }
    $CrossRepoBase = $CrossRepoBase -replace '^~', $HOME
    
    # Ask about archive directory
    Write-Host ''
    Write-Host 'When removing cross-repo tasks, where should they be archived?'
    Write-Host "  1) $CrossRepoBase\wt-archive (default)"
    Write-Host "  2) $env:LOCALAPPDATA\git-worktree-utils\archive"
    Write-Host '  3) Custom path'
    $archiveChoice = Read-Host 'Choice [1]'
    if (-not $archiveChoice) { $archiveChoice = '1' }
    
    switch ($archiveChoice) {
        '1' { $CrossRepoArchive = Join-Path $CrossRepoBase 'wt-archive' }
        '2' { $CrossRepoArchive = Join-Path $env:LOCALAPPDATA 'git-worktree-utils\archive' }
        '3' { 
            $CrossRepoArchive = Read-Host 'Archive directory'
            $CrossRepoArchive = $CrossRepoArchive -replace '^~', $HOME
        }
        default { $CrossRepoArchive = Join-Path $CrossRepoBase 'wt-archive' }
    }
    
    # Ask about default branch overrides
    Write-Host ''
    Write-Host "Some repos may use a non-standard default branch (e.g., 'master' instead of 'main')."
    Write-Host "Enter overrides as 'repo=branch' (comma-separated), or leave blank for none."
    Write-Host 'Example: comfyui=master,legacy-app=develop'
    $overridesInput = Read-Host 'Default branch overrides []'
    
    $Overrides = @{}
    if ($overridesInput) {
        $overridesInput -split ',' | ForEach-Object {
            $parts = $_ -split '='
            if ($parts.Count -eq 2) {
                $Overrides[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }
    
    # Ask about installation location
    Write-Host ''
    Write-Host 'Where should the scripts be installed?'
    Write-Host "  1) Current location: $ScriptDir"
    Write-Host "  2) Stable location:  $DefaultInstallDir (recommended)"
    Write-Host ''
    Write-Host 'Option 2 copies scripts to a stable location, so you can delete this checkout.'
    $installChoice = Read-Host 'Choice [2]'
    if (-not $installChoice) { $installChoice = '2' }
    
    if ($installChoice -eq '1') {
        $InstallDir = $ScriptDir
    }
    else {
        $InstallDir = Read-Host "Install directory [$DefaultInstallDir]"
        if (-not $InstallDir) { $InstallDir = $DefaultInstallDir }
        $InstallDir = $InstallDir -replace '^~', $HOME
    }
}

# Create directories
New-Item -ItemType Directory -Path $WorktreeBase -Force | Out-Null
New-Item -ItemType Directory -Path $CrossRepoBase -Force | Out-Null
New-Item -ItemType Directory -Path $CrossRepoArchive -Force | Out-Null

# Copy scripts if using a different install location
if ($InstallDir -ne $ScriptDir) {
    Write-Host ''
    Write-Host "Copying scripts to $InstallDir..."
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item (Join-Path $ScriptDir 'worktree.ps1') $InstallDir -Force
    Copy-Item (Join-Path $ScriptDir 'completions.ps1') $InstallDir -Force
    Write-Host '✓ Scripts copied' -ForegroundColor Green
}

# Build the config block
$configLines = @()
$configLines += $BlockStart
$configLines += "# Installed: $(Get-Date -Format 'o')"
$configLines += "`$env:WORKTREE_BASE = `"$WorktreeBase`""
$configLines += "`$env:CROSS_REPO_BASE = `"$CrossRepoBase`""
$configLines += "`$env:CROSS_REPO_ARCHIVE = `"$CrossRepoArchive`""

# Add overrides if any
if ($Overrides.Count -gt 0) {
    $configLines += '# Default branch overrides'
    $configLines += '$global:WT_DEFAULT_BRANCH_OVERRIDES = @{'
    foreach ($key in $Overrides.Keys) {
        $configLines += "    '$key' = '$($Overrides[$key])'"
    }
    $configLines += '}'
}

$configLines += ". `"$InstallDir\worktree.ps1`""
$configLines += ". `"$InstallDir\completions.ps1`""
$configLines += $BlockEnd

$configBlock = $configLines -join "`n"

# Remove existing config block if present
if ($ExistingConfig) {
    # Create backup
    Copy-Item $PROFILE "$PROFILE.bak"
    
    # Remove old block
    $pattern = "(?s)$([regex]::Escape($BlockStart)).*?$([regex]::Escape($BlockEnd))\r?\n?"
    $profileContent = [regex]::Replace($profileContent, $pattern, '')
    Set-Content -Path $PROFILE -Value $profileContent.TrimEnd() -NoNewline
    
    Write-Host "✓ Removed old configuration (backup: $PROFILE.bak)" -ForegroundColor Green
}

# Append new config
Add-Content -Path $PROFILE -Value "`n$configBlock`n"

Write-Host ''
Write-Host "✓ Configuration added to $PROFILE" -ForegroundColor Green
Write-Host ''
Write-Host 'Restart PowerShell or run the following to activate:'
Write-Host "  . `$PROFILE" -ForegroundColor Yellow
Write-Host ''
Write-Host 'Commands available:' -ForegroundColor Cyan
Write-Host '  wt-clone <url>           Clone a repo into worktree structure'
Write-Host '  wt-new <repo> <branch>   Create a new feature worktree'
Write-Host '  wt-cd <repo> [branch]    Navigate to a worktree'
Write-Host '  wt-rm <repo> <branch>    Remove a worktree'
Write-Host ''
Write-Host 'Run ".\setup.ps1 -Update" to refresh scripts after git pull.'

# Note about symlinks on Windows
Write-Host ''
Write-Host 'NOTE: Cross-repo symlinks (wt-multi-*) may require:' -ForegroundColor Yellow
Write-Host '  - Developer Mode enabled, OR'
Write-Host '  - Running PowerShell as Administrator'
Write-Host ''
