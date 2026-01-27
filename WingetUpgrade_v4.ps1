<#
.SYNOPSIS
    Automatically upgrades packages managed by Windows Package Manager (winget)

.DESCRIPTION
    This script automates the process of upgrading packages using Windows Package Manager (winget).
    It uses the Microsoft.WinGet.Client PowerShell module for reliable package detection and
    filters them against a skip list before performing upgrades in parallel.
    
    Version 4.0 improvements:
    - Refactored into smaller, maintainable functions
    - Enhanced error handling with detailed error messages
    - Improved code organization and readability

.NOTES
    File Name      : WingetUpgrade_v4.ps1
    Prerequisite   : Windows Package Manager (winget), Microsoft.WinGet.Client module
    Version        : 4.0

.PARAMETER DebugMode
    Enables debug output for troubleshooting

.EXAMPLE
    .\WingetUpgrade_v4.ps1
    Runs the script with default settings

.EXAMPLE
    .\WingetUpgrade_v4.ps1 -DebugMode $true
    Runs the script with debug information enabled
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [bool]$DebugMode = $false
)

# Clear screen at the very beginning
Clear-Host

# Import required module
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    if ($DebugMode) {
        Write-Host "Microsoft.WinGet.Client module loaded successfully" -ForegroundColor Cyan
    }
} catch {
    Write-Error "Failed to load Microsoft.WinGet.Client module. Please install it with: Install-Module -Name Microsoft.WinGet.Client" -ErrorAction Stop
}

# Import ThreadJob module for better job handling
try {
    Import-Module ThreadJob -ErrorAction Stop
    if ($DebugMode) {
        Write-Host "ThreadJob module loaded successfully" -ForegroundColor Cyan
    }
} catch {
    Write-Warning "ThreadJob module not found. Installing..."
    try {
        Install-Module -Name ThreadJob -Force -Scope CurrentUser -ErrorAction Stop
        Import-Module ThreadJob -ErrorAction Stop
        Write-Host "ThreadJob module installed and loaded successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to install ThreadJob module: $_" -ErrorAction Stop
    }
}

# Import SkipList
try {
    $skipListPath = Join-Path -Path $PSScriptRoot -ChildPath "WingetUpgrade_SkipLists.json"
    $toSkip = Get-Content $skipListPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    
    if ($DebugMode) {
        Write-Host "Skip list loaded successfully from $skipListPath" -ForegroundColor Cyan
        Write-Host "Packages in skip list: $($toSkip.packages.Count)" -ForegroundColor Cyan
    }
} catch {
    Write-Error "Failed to load skip list: $_" -ErrorAction Stop
}

#region Helper Functions

function Get-FilteredUpgradeList {
    <#
    .SYNOPSIS
        Filters package list against skip list and initializes package status
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$PackageList,
        
        [Parameter(Mandatory = $true)]
        [object]$SkipList
    )
    
    $upgradeCount = 0
    $skipCount = 0
    $packageStatus = @{}
    
    foreach ($package in $PackageList) {
        if (-not ($SkipList.packages -contains $package.Id)) {
            $upgradeCount++
            $packageStatus[$package.Id] = @{
                State = "Queued"
                Icon = "⏸"
                ErrorMessage = $null
                ErrorDetails = $null
                StartTime = $null
                EndTime = $null
            }
        } else {
            $skipCount++
        }
    }
    
    return @{
        PackageStatus = $packageStatus
        UpgradeCount = $upgradeCount
        SkipCount = $skipCount
    }
}

function Start-PackageUpgradeJob {
    <#
    .SYNOPSIS
        Starts a ThreadJob to upgrade a single package
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,
        
        [Parameter(Mandatory = $false)]
        [bool]$DebugMode = $false
    )
    
    $scriptBlock = {
        param($PackageId)
        
        # Suppress all output streams
        $ProgressPreference = 'SilentlyContinue'
        $VerbosePreference = 'SilentlyContinue'
        $DebugPreference = 'SilentlyContinue'
        $WarningPreference = 'SilentlyContinue'
        $InformationPreference = 'SilentlyContinue'
        
        try {
            # Import module in thread context
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop | Out-Null
            
            # Re-get the package in the thread context
            $pkg = Get-WinGetPackage -Id $PackageId | Where-Object { $_.IsUpdateAvailable -eq $true } | Select-Object -First 1
            
            if ($pkg) {
                Write-Output "STATUS:Downloading:${PackageId}"
                
                # Perform the update with all output suppressed
                try {
                    Update-WinGetPackage -InputObject $pkg -Mode Silent -Force *>&1 | Out-Null
                    Write-Output "STATUS:Completed:${PackageId}"
                } catch {
                    Write-Output "STATUS:Failed:${PackageId}"
                    Write-Output "ERROR:${PackageId}:$($_.Exception.Message)"
                    if ($_.ScriptStackTrace) {
                        Write-Output "ERRORDETAIL:${PackageId}:$($_.ScriptStackTrace)"
                    }
                    throw
                }
            } else {
                Write-Output "STATUS:Failed:${PackageId}"
                Write-Output "ERROR:${PackageId}:Package not found or not updateable"
                throw "Package $PackageId not found or not updateable"
            }
        } catch {
            # Ensure error is captured
            if (-not ($_ -match '^(STATUS|ERROR|ERRORDETAIL):')) {
                Write-Output "ERROR:${PackageId}:$($_.Exception.Message)"
            }
            throw
        }
    }
    
    try {
        $job = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList $PackageId
        
        if ($DebugMode) {
            Write-Host "Started upgrade job for $PackageId (Job ID: $($job.Id))" -ForegroundColor Cyan
        }
        
        return $job
    } catch {
        Write-Host "Failed to start upgrade for ${PackageId}: $_" -ForegroundColor Red
        return $null
    }
}

function Update-PackageJobStatus {
    <#
    .SYNOPSIS
        Updates package status based on job output
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageStatus,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageJobs,
        
        [Parameter(Mandatory = $true)]
        [array]$SpinnerChars,
        
        [Parameter(Mandatory = $true)]
        [int]$SpinnerIndex
    )
    
    $completedJobs = @()
    
    foreach ($pkgId in $PackageJobs.Keys) {
        $job = $PackageJobs[$pkgId]
        
        if ($job.State -eq 'Completed' -or $job.State -eq 'Failed') {
            $completedJobs += $pkgId
            
            # Check job output for status and errors
            $jobOutput = Receive-Job -Job $job -Keep 2>&1
            $lastStatus = $jobOutput | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
            $errorMessages = $jobOutput | Where-Object { $_ -match '^ERROR:' }
            $errorDetails = $jobOutput | Where-Object { $_ -match '^ERRORDETAIL:' }
            
            if ($lastStatus -match 'STATUS:Completed') {
                $PackageStatus[$pkgId].State = "Completed"
                $PackageStatus[$pkgId].Icon = "✓"
                $PackageStatus[$pkgId].EndTime = Get-Date
            } else {
                $PackageStatus[$pkgId].State = "Failed"
                $PackageStatus[$pkgId].Icon = "✗"
                $PackageStatus[$pkgId].EndTime = Get-Date
                
                # Extract error information
                if ($errorMessages) {
                    foreach ($errMsg in $errorMessages) {
                        if ($errMsg -match "^ERROR:$([regex]::Escape(${pkgId})):(.*)") {
                            $PackageStatus[$pkgId].ErrorMessage = $matches[1]
                        }
                    }
                }
                
                if ($errorDetails) {
                    foreach ($errDetail in $errorDetails) {
                        if ($errDetail -match "^ERRORDETAIL:$([regex]::Escape(${pkgId})):(.*)") {
                            $PackageStatus[$pkgId].ErrorDetails = $matches[1]
                        }
                    }
                }
            }
        } else {
            # Job is still running - check for status updates
            try {
                $jobOutput = Receive-Job -Job $job -Keep 2>&1
                $lastStatus = $jobOutput | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
                
                if ($lastStatus -match 'STATUS:Downloading') {
                    $PackageStatus[$pkgId].State = "Downloading"
                    $PackageStatus[$pkgId].Icon = $SpinnerChars[$SpinnerIndex]
                    if (-not $PackageStatus[$pkgId].StartTime) {
                        $PackageStatus[$pkgId].StartTime = Get-Date
                    }
                } elseif ($lastStatus -match 'STATUS:Installing') {
                    $PackageStatus[$pkgId].State = "Installing"
                    $PackageStatus[$pkgId].Icon = $SpinnerChars[$SpinnerIndex]
                } else {
                    # No status yet, assume processing
                    $PackageStatus[$pkgId].State = "Processing"
                    $PackageStatus[$pkgId].Icon = $SpinnerChars[$SpinnerIndex]
                }
            } catch {
                # If we can't get output, just show spinner
                $PackageStatus[$pkgId].Icon = $SpinnerChars[$SpinnerIndex]
            }
        }
    }
    
    return @{
        CompletedJobs = $completedJobs
    }
}

function Get-StateColor {
    <#
    .SYNOPSIS
        Returns the appropriate color for a given package state
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$State
    )
    
    switch -Regex ($State) {
        "Completed" {
            return "Green" 
        }
        "Failed" {
            return "Red" 
        }
        "Downloading" {
            return "Cyan" 
        }
        "Installing" {
            return "Yellow" 
        }
        "Finishing" {
            return "Magenta" 
        }
        "Queued" {
            return "DarkGray" 
        }
        default {
            return "White" 
        }
    }
}

function Get-ProgressBar {
    <#
    .SYNOPSIS
        Generates a progress bar string
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$TotalJobs,
        
        [Parameter(Mandatory = $true)]
        [int]$CompletedCount
    )
    
    $percentage = if ($TotalJobs -gt 0) {
        [math]::Round(($CompletedCount / $TotalJobs) * 100) 
    } else {
        0 
    }
    $barLength = 30
    $filled = if ($TotalJobs -gt 0) {
        [math]::Round($barLength * $CompletedCount / $TotalJobs) 
    } else {
        0 
    }
    $bar = "█" * $filled + "░" * ($barLength - $filled)
    
    return "Upgrading packages... [$bar] $percentage% ($CompletedCount/$TotalJobs)"
}

function Get-StatusSummary {
    <#
    .SYNOPSIS
        Generates a status summary string
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageStatus
    )
    
    # Count packages by state
    $stateCounts = @{}
    foreach ($pkgId in $PackageStatus.Keys) {
        $state = $PackageStatus[$pkgId].State
        if ($stateCounts.ContainsKey($state)) {
            $stateCounts[$state]++
        } else {
            $stateCounts[$state] = 1
        }
    }
    
    # Build status summary
    $statusParts = @()
    $order = @("Downloading", "Installing", "Processing", "Completed", "Failed", "Queued")
    foreach ($state in $order) {
        if ($stateCounts.ContainsKey($state) -and $stateCounts[$state] -gt 0) {
            $statusParts += "$state $($stateCounts[$state])"
        }
    }
    
    if ($statusParts.Count -gt 0) {
        return "Status: " + ($statusParts -join ", ")
    }
    
    return $null
}

function Write-ColoredLine {
    <#
    .SYNOPSIS
        Writes a line with appropriate coloring
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Line = ""
    )
    
    # Handle empty or null lines
    if ([string]::IsNullOrEmpty($Line)) {
        Write-Host ""
        return
    }
    
    try {
        if ($Line -match "^\[(.+)\] (.+) \((.+)\)$") {
            $icon = $matches[1]
            $pkg = $matches[2]
            $state = $matches[3]
            
            $color = Get-StateColor -State $state
            
            Write-Host "[$icon] " -NoNewline -ForegroundColor $color
            Write-Host "$pkg " -NoNewline -ForegroundColor White
            Write-Host "($state)" -ForegroundColor $color
        } elseif ($Line -match "^━") {
            Write-Host $Line -ForegroundColor Cyan
        } elseif ($Line -match "^Upgrading") {
            Write-Host $Line -ForegroundColor Yellow
        } elseif ($Line -match "^Status:") {
            Write-Host $Line -ForegroundColor Magenta
        } else {
            Write-Host $Line
        }
    } catch {
        # Fallback to plain output if coloring fails
        Write-Host $Line
    }
}

function Update-ProgressDisplay {
    <#
    .SYNOPSIS
        Updates the progress display in place
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageStatus,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalJobs,
        
        [Parameter(Mandatory = $true)]
        [int]$CompletedCount,
        
        [Parameter(Mandatory = $true)]
        [int]$DisplayStartLine,
        
        [Parameter(Mandatory = $true)]
        [bool]$HasCurrentActivity
    )
    
    $sortedPackages = $PackageStatus.Keys | Sort-Object
    
    # Build all display content first
    $displayContent = @()
    $displayContent += ""  # Line 0: empty
    $displayContent += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"  # Line 1: separator
    
    # Package lines
    foreach ($pkgId in $sortedPackages) {
        if ($PackageStatus.ContainsKey($pkgId)) {
            $status = $PackageStatus[$pkgId]
            $displayContent += "[$($status.Icon)] $pkgId ($($status.State))"
        }
    }
    
    $displayContent += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"  # Separator
    
    # Progress bar
    $progressBar = Get-ProgressBar -TotalJobs $TotalJobs -CompletedCount $CompletedCount
    $displayContent += $progressBar
    
    # Current activity - show status summary
    if ($HasCurrentActivity) {
        $statusSummary = Get-StatusSummary -PackageStatus $PackageStatus
        if ($statusSummary) {
            $displayContent += $statusSummary
        } else {
            $displayContent += ""
        }
    }
    
    $displayContent += ""  # Final empty line
    
    # Now render all lines
    for ($i = 0; $i -lt $displayContent.Count; $i++) {
        $targetLine = $DisplayStartLine + $i
        if ($targetLine -lt [Console]::BufferHeight) {
            try {
                [Console]::SetCursorPosition(0, $targetLine)
                # Clear line
                Write-Host (" " * [Console]::WindowWidth) -NoNewline
                [Console]::SetCursorPosition(0, $targetLine)
                
                # Write content with color
                $line = $displayContent[$i]
                Write-ColoredLine -Line $line
            } catch {
                # Silently ignore display errors to prevent spam
                # This can happen when console is resized or scrolled
            }
        }
    }
    
    # Return actual line count based on cursor position
    return ([Console]::CursorTop - $DisplayStartLine)
}

function Show-UpgradeSummary {
    <#
    .SYNOPSIS
        Displays the final upgrade summary with error details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PackageStatus
    )
    
    Write-Host ""
    Write-Host "✨ Upgrade Complete" -ForegroundColor Cyan
    
    $successCount = 0
    $failCount = 0
    $failedPackages = @()
    
    foreach ($pkgId in $PackageStatus.Keys | Sort-Object) {
        $status = $PackageStatus[$pkgId]
        
        if ($status.State -eq "Completed") {
            $successCount++
        } else {
            $failCount++
            $failedPackages += @{
                Id = $pkgId
                ErrorMessage = $status.ErrorMessage
                ErrorDetails = $status.ErrorDetails
            }
        }
    }
    
    Write-Host "  ✅ $successCount succeeded" -NoNewline -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host ", " -NoNewline
        Write-Host "❌ $failCount failed" -ForegroundColor Red
    } else {
        Write-Host ""
    }
    
    # Show detailed error information for failed packages
    if ($failedPackages.Count -gt 0) {
        Write-Host ""
        Write-Host "❌ Failed Packages:" -ForegroundColor Red
        foreach ($failedPkg in $failedPackages) {
            Write-Host "  • $($failedPkg.Id)" -ForegroundColor Red
            if ($failedPkg.ErrorMessage) {
                Write-Host "    Reason: $($failedPkg.ErrorMessage)" -ForegroundColor DarkRed
            }
            if ($failedPkg.ErrorDetails) {
                Write-Host "    Details: $($failedPkg.ErrorDetails)" -ForegroundColor DarkGray
            }
        }
    }
    
    Write-Host ""
}

#endregion Helper Functions

function Invoke-PackageUpgrade {
    <#
    .SYNOPSIS
        Main function to orchestrate package upgrades
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$UpgradeList
    )

    # Filter packages and initialize status
    $filterResult = Get-FilteredUpgradeList -PackageList $UpgradeList -SkipList $toSkip
    $packageStatus = $filterResult.PackageStatus
    $upgradeCount = $filterResult.UpgradeCount
    $skipCount = $filterResult.SkipCount
    $packageJobs = @{}

    if ($DebugMode -and $skipCount -gt 0) {
        Write-Host "Skipped $skipCount package(s) based on skip list" -ForegroundColor DarkGray
    }

    if ($upgradeCount -eq 0) {
        Write-Host 'No packages to upgrade.' -ForegroundColor Yellow
        return
    }

    # Start all upgrade jobs
    foreach ($package in $UpgradeList) {
        if (-not ($toSkip.packages -contains $package.Id)) {
            $job = Start-PackageUpgradeJob -PackageId $package.Id -DebugMode $DebugMode
            
            if ($job) {
                $packageJobs[$package.Id] = $job
            } else {
                $packageStatus.Remove($package.Id)
            }
        }
    }

    if ($packageJobs.Count -eq 0) {
        Write-Host 'Failed to start any upgrade jobs.' -ForegroundColor Red
        return
    }

    # Progress display with real-time status
    $spinnerChars = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
    $spinnerIndex = 0
    $totalJobs = $packageJobs.Count
    $completedCount = 0
    $lastDisplayHash = ""
    $displayStartLine = -1
    $displayLineCount = 0
    
    # Hide cursor during progress display
    [Console]::CursorVisible = $false

    while ($packageJobs.Count -gt 0) {
        # Update status for each package
        $updateResult = Update-PackageJobStatus `
            -PackageStatus $packageStatus `
            -PackageJobs $packageJobs `
            -SpinnerChars $spinnerChars `
            -SpinnerIndex $spinnerIndex
        
        $completedJobs = $updateResult.CompletedJobs
        
        # Remove completed jobs
        foreach ($pkgId in $completedJobs) {
            $packageJobs.Remove($pkgId)
        }
        
        # Calculate actual completed count from package status
        $completedCount = 0
        foreach ($pkgId in $packageStatus.Keys) {
            if ($packageStatus[$pkgId].State -eq "Completed" -or $packageStatus[$pkgId].State -eq "Failed") {
                $completedCount++
            }
        }
        
        # Build current state hash to detect changes (include spinner index for animation)
        $stateHash = ""
        foreach ($pkgId in $packageStatus.Keys | Sort-Object) {
            $stateHash += "$pkgId-$($packageStatus[$pkgId].State)|"
        }
        $stateHash += "$completedCount/$totalJobs-$spinnerIndex"
        
        # Only redraw if state changed or first time
        if ($stateHash -ne $lastDisplayHash) {
            $lastDisplayHash = $stateHash
            
            if ($displayStartLine -eq -1) {
                # First time - record start position without drawing
                # This prevents double rendering on initial display
                $displayStartLine = [Console]::CursorTop
            }
            
            # Use Update-ProgressDisplay for all rendering (first time and updates)
            # This ensures consistent display position throughout execution
            $hasCurrentActivity = ($packageJobs.Count -gt 0)
            
            $displayLineCount = Update-ProgressDisplay `
                -PackageStatus $packageStatus `
                -TotalJobs $totalJobs `
                -CompletedCount $completedCount `
                -DisplayStartLine $displayStartLine `
                -HasCurrentActivity $hasCurrentActivity
            
            # Move cursor back to end (with boundary check)
            $targetPosition = $displayStartLine + $displayLineCount
            if ($targetPosition -lt [Console]::BufferHeight) {
                [Console]::SetCursorPosition(0, $targetPosition)
            }
        } else {
            # Just update spinner for running jobs
            $spinnerIndex = ($spinnerIndex + 1) % $spinnerChars.Count
            foreach ($pkgId in $packageJobs.Keys) {
                if ($packageStatus.ContainsKey($pkgId)) {
                    $state = $packageStatus[$pkgId].State
                    if ($state -eq "Downloading" -or $state -eq "Installing" -or $state -eq "Processing") {
                        $packageStatus[$pkgId].Icon = $spinnerChars[$spinnerIndex]
                    }
                }
            }
        }

        if ($packageJobs.Count -gt 0) {
            Start-Sleep -Milliseconds 5
        }
    }
    
    # Show cursor again
    [Console]::CursorVisible = $true
    
    # Move cursor to after the display area (with boundary check)
    if ($displayStartLine -ne -1) {
        $targetPosition = $displayStartLine + $displayLineCount
        if ($targetPosition -lt [Console]::BufferHeight) {
            [Console]::SetCursorPosition(0, $targetPosition)
        }
    }
    
    # Show final summary with error details
    Show-UpgradeSummary -PackageStatus $packageStatus
}

#region Main Script Execution

# Stylish header
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      🚀 Winget Package Upgrade Script v4              ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "🔍 Checking for package updates..." -ForegroundColor Gray

# Get packages with available updates using Microsoft.WinGet.Client module
try {
    $packagesWithUpdates = Get-WinGetPackage -Source winget | Where-Object { 
        $_.AvailableVersions -ne $null -and $_.IsUpdateAvailable -eq $true 
    }
    
    if ($DebugMode) {
        Write-Host "`nPackages with updates available:" -ForegroundColor Cyan
        $packagesWithUpdates | Format-Table -Property Id, InstalledVersion, @{
            Label = "AvailableVersion"
            Expression = { $_.AvailableVersions[0] }
        }, IsUpdateAvailable -AutoSize
    }
} catch {
    Write-Error "Failed to get available upgrades: $_" -ErrorAction Stop
}

# Process available upgrades
if ($packagesWithUpdates.Count -gt 0) {
    Write-Host ""
    Write-Host "📦 Found $($packagesWithUpdates.Count) package(s) to upgrade" -ForegroundColor Green
    Write-Host ""
    
    # Show all packages with skip status
    $index = 0
    $packagesWithUpdates | ForEach-Object {
        $index++
        $isSkipped = $toSkip.packages -contains $_.Id
        
        Write-Host "  $index. " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($_.Id) " -NoNewline -ForegroundColor White
        Write-Host "$($_.InstalledVersion)" -NoNewline -ForegroundColor Red
        Write-Host " → " -NoNewline -ForegroundColor Yellow
        Write-Host "$($_.AvailableVersions[0])" -NoNewline -ForegroundColor Green
        
        if ($isSkipped) {
            Write-Host " (Skip)" -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }
    }
    
    Write-Host ""
    
    Invoke-PackageUpgrade -UpgradeList $packagesWithUpdates
} else {
    Write-Host ""
    Write-Host "✅ All packages are up to date!" -ForegroundColor Green
    Write-Host ""
}

#endregion Main Script Execution
