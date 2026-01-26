<#
.SYNOPSIS
    Automatically upgrades packages managed by Windows Package Manager (winget)

.DESCRIPTION
    This script automates the process of upgrading packages using Windows Package Manager (winget).
    It uses the Microsoft.WinGet.Client PowerShell module for reliable package detection and
    filters them against a skip list before performing upgrades in parallel.

.NOTES
    File Name      : WingetUpgrade_v3.ps1
    Prerequisite   : Windows Package Manager (winget), Microsoft.WinGet.Client module
    Version        : 3.0

.PARAMETER DebugMode
    Enables debug output for troubleshooting

.EXAMPLE
    .\WingetUpgrade_v3.ps1
    Runs the script with default settings

.EXAMPLE
    .\WingetUpgrade_v3.ps1 -DebugMode $true
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

function Invoke-PackageUpgrade {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$UpgradeList
    )

    $upgradeCount = 0
    $skipCount = 0
    $packageStatus = @{}
    $packageJobs = @{}

    foreach ($package in $UpgradeList) {
        if (-not ($toSkip.packages -contains $package.Id)) {
            $upgradeCount++
            $packageStatus[$package.Id] = @{
                State = "Queued"
                Icon = "⏸"
                DownloadProgress = 0
                BytesDownloaded = 0
                BytesRequired = 0
            }
        } else {
            $skipCount++
        }
    }

    if ($upgradeCount -eq 0) {
        Write-Host 'No packages to upgrade.' -ForegroundColor Yellow
        return
    }

    # Start all upgrade jobs using Update-WinGetPackage with ThreadJob
    foreach ($package in $UpgradeList) {
        if (-not ($toSkip.packages -contains $package.Id)) {
            try {
                # Use Start-ThreadJob for better progress tracking
                $pkgId = $package.Id
                $scriptBlock = {
                    param($PackageId)
                    
                    # Import module in thread context
                    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
                    
                    # Re-get the package in the thread context
                    $pkg = Get-WinGetPackage -Id $PackageId | Where-Object { $_.IsUpdateAvailable -eq $true } | Select-Object -First 1
                    
                    if ($pkg) {
                        Write-Output "STATUS:Downloading:$PackageId"
                        
                        # Perform the update
                        $result = Update-WinGetPackage -InputObject $pkg -Mode Silent -Force
                        
                        Write-Output "STATUS:Completed:$PackageId"
                        return $result
                    } else {
                        Write-Output "STATUS:Failed:$PackageId"
                        throw "Package $PackageId not found or not updateable"
                    }
                }
                
                $job = Start-ThreadJob -ScriptBlock $scriptBlock -ArgumentList $pkgId
                $packageJobs[$package.Id] = $job
                
                if ($DebugMode) {
                    Write-Host "Started upgrade job for $($package.Id) (Job ID: $($job.Id))" -ForegroundColor Cyan
                }
            } catch {
                Write-Host "Failed to start upgrade for $($package.Id): $_" -ForegroundColor Red
                $packageStatus.Remove($package.Id)
            }
        }
    }

    if ($packageJobs.Count -eq 0) {
        Write-Host 'Failed to start any upgrade jobs.' -ForegroundColor Red
        return
    }

    # Stylish progress display with real-time status
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
        $completedJobs = @()
        
        # Update status for each package
        foreach ($pkgId in $packageJobs.Keys) {
            $job = $packageJobs[$pkgId]
            
            if ($job.State -eq 'Completed' -or $job.State -eq 'Failed') {
                $completedJobs += $pkgId
                
                # Check job output for status
                $jobOutput = Receive-Job -Job $job -Keep 2>&1
                $lastStatus = $jobOutput | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
                
                if ($lastStatus -match 'STATUS:Completed') {
                    $packageStatus[$pkgId].State = "Completed"
                    $packageStatus[$pkgId].Icon = "✓"
                } else {
                    $packageStatus[$pkgId].State = "Failed"
                    $packageStatus[$pkgId].Icon = "✗"
                }
                $completedCount++
            } else {
                # Job is still running - check for status updates
                try {
                    $jobOutput = Receive-Job -Job $job -Keep 2>&1
                    $lastStatus = $jobOutput | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
                    
                    if ($lastStatus -match 'STATUS:Downloading') {
                        $packageStatus[$pkgId].State = "Downloading"
                        $packageStatus[$pkgId].Icon = $spinnerChars[$spinnerIndex]
                    } elseif ($lastStatus -match 'STATUS:Installing') {
                        $packageStatus[$pkgId].State = "Installing"
                        $packageStatus[$pkgId].Icon = $spinnerChars[$spinnerIndex]
                    } else {
                        # No status yet, assume processing
                        $packageStatus[$pkgId].State = "Processing"
                        $packageStatus[$pkgId].Icon = $spinnerChars[$spinnerIndex]
                    }
                } catch {
                    # If we can't get output, just show spinner
                    $packageStatus[$pkgId].Icon = $spinnerChars[$spinnerIndex]
                }
            }
        }
        
        # Remove completed jobs
        foreach ($pkgId in $completedJobs) {
            $packageJobs.Remove($pkgId)
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
                # First time - record start position and print
                $displayStartLine = [Console]::CursorTop
            
                Write-Host ""
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
            
                # Show package statuses
                foreach ($pkgId in $packageStatus.Keys | Sort-Object) {
                    $status = $packageStatus[$pkgId]
                    $icon = $status.Icon
                    $state = $status.State
                
                    $color = switch -Regex ($state) {
                        "Completed" {
                            "Green" 
                        }
                        "Failed" {
                            "Red" 
                        }
                        "Downloading" {
                            "Cyan" 
                        }
                        "Installing" {
                            "Yellow" 
                        }
                        "Finishing" {
                            "Magenta" 
                        }
                        "Queued" {
                            "DarkGray" 
                        }
                        default {
                            "White" 
                        }
                    }
                
                    Write-Host "[$icon] " -NoNewline -ForegroundColor $color
                    Write-Host "$pkgId " -NoNewline -ForegroundColor White
                    Write-Host "($state)" -ForegroundColor $color
                }
            
                Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
            
                # Overall progress bar
                $percentage = if ($totalJobs -gt 0) {
                    [math]::Round(($completedCount / $totalJobs) * 100) 
                } else {
                    0 
                }
                $barLength = 30
                $filled = if ($totalJobs -gt 0) {
                    [math]::Round($barLength * $completedCount / $totalJobs) 
                } else {
                    0 
                }
                $bar = "█" * $filled + "░" * ($barLength - $filled)
            
                Write-Host "Upgrading packages... [$bar] $percentage% ($completedCount/$totalJobs)" -ForegroundColor Yellow
            
                # Status summary
                if ($packageJobs.Count -gt 0) {
                    # Count packages by state
                    $stateCounts = @{}
                    foreach ($pkgId in $packageStatus.Keys) {
                        $state = $packageStatus[$pkgId].State
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
                        Write-Host ("Status: " + ($statusParts -join ", ")) -ForegroundColor Magenta
                    }
                }
                Write-Host ""
            
                $displayLineCount = [Console]::CursorTop - $displayStartLine
            } else {
                # Update in place - overwrite existing lines
                $sortedPackages = $packageStatus.Keys | Sort-Object
                # Calculate expected lines: empty + separator + packages + separator + progress + current (if exists) + empty
                $hasCurrentActivity = ($packageJobs.Count -gt 0)
                $expectedLines = 2 + $sortedPackages.Count + 1 + 1 + ($hasCurrentActivity ? 1 : 0) + 1
                
                # Update line count
                $displayLineCount = $expectedLines
                
                # Build all display content first
                $displayContent = @()
                $displayContent += ""  # Line 0: empty
                $displayContent += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"  # Line 1: separator
                
                # Package lines
                foreach ($pkgId in $sortedPackages) {
                    if ($packageStatus.ContainsKey($pkgId)) {
                        $status = $packageStatus[$pkgId]
                        $displayContent += "[$($status.Icon)] $pkgId ($($status.State))"
                    }
                }
                
                $displayContent += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"  # Separator
                
                # Progress bar
                $percentage = if ($totalJobs -gt 0) {
                    [math]::Round(($completedCount / $totalJobs) * 100) 
                } else {
                    0 
                }
                $barLength = 30
                $filled = if ($totalJobs -gt 0) {
                    [math]::Round($barLength * $completedCount / $totalJobs) 
                } else {
                    0 
                }
                $bar = "█" * $filled + "░" * ($barLength - $filled)
                $displayContent += "Upgrading packages... [$bar] $percentage% ($completedCount/$totalJobs)"
                
                # Current activity - show status summary
                if ($hasCurrentActivity) {
                    # Count packages by state
                    $stateCounts = @{}
                    foreach ($pkgId in $packageStatus.Keys) {
                        $state = $packageStatus[$pkgId].State
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
                        $displayContent += "Status: " + ($statusParts -join ", ")
                    } else {
                        $displayContent += ""
                    }
                }
                
                $displayContent += ""  # Final empty line
                
                # Now render all lines
                for ($i = 0; $i -lt $displayContent.Count; $i++) {
                    $targetLine = $displayStartLine + $i
                    if ($targetLine -lt [Console]::BufferHeight) {
                        [Console]::SetCursorPosition(0, $targetLine)
                        # Clear line
                        Write-Host (" " * [Console]::WindowWidth) -NoNewline
                        [Console]::SetCursorPosition(0, $targetLine)
                        
                        # Write content with color
                        $line = $displayContent[$i]
                        if ($line -match "^\[(.+)\] (.+) \((.+)\)$") {
                            $icon = $matches[1]
                            $pkg = $matches[2]
                            $state = $matches[3]
                            
                            $color = switch -Regex ($state) {
                                "Completed" {
                                    "Green" 
                                }
                                "Failed" {
                                    "Red" 
                                }
                                "Downloading" {
                                    "Cyan" 
                                }
                                "Installing" {
                                    "Yellow" 
                                }
                                "Finishing" {
                                    "Magenta" 
                                }
                                "Queued" {
                                    "DarkGray" 
                                }
                                default {
                                    "White" 
                                }
                            }
                            
                            Write-Host "[$icon] " -NoNewline -ForegroundColor $color
                            Write-Host "$pkg " -NoNewline -ForegroundColor White
                            Write-Host "($state)" -ForegroundColor $color
                        } elseif ($line -match "^━") {
                            Write-Host $line -ForegroundColor Cyan
                        } elseif ($line -match "^Upgrading") {
                            Write-Host $line -ForegroundColor Yellow
                        } elseif ($line -match "^Status:") {
                            Write-Host $line -ForegroundColor Magenta
                        } else {
                            Write-Host $line
                        }
                    }
                }
                
                # Move cursor back to end (with boundary check)
                $targetPosition = $displayStartLine + $displayLineCount
                if ($targetPosition -lt [Console]::BufferHeight) {
                    [Console]::SetCursorPosition(0, $targetPosition)
                }
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
    
    # Show final summary
    Write-Host ""
    Write-Host "✨ Upgrade Complete" -ForegroundColor Cyan
    
    $successCount = 0
    $failCount = 0
    
    foreach ($pkgId in $packageStatus.Keys | Sort-Object) {
        $status = $packageStatus[$pkgId]
        
        if ($status.State -eq "Completed") {
            $successCount++
        } else {
            $failCount++
            Write-Host "  ❌ $pkgId" -ForegroundColor Red
        }
    }
    
    Write-Host "  ✅ $successCount succeeded" -NoNewline -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host ", " -NoNewline
        Write-Host "❌ $failCount failed" -ForegroundColor Red
    } else {
        Write-Host ""
    }
    Write-Host ""
}

#region Main Script Execution

# Stylish header
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      🚀 Winget Package Upgrade Script v3              ║" -ForegroundColor Cyan
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
