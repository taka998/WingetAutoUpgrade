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

# Import required module
try {
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    if ($DebugMode) {
        Write-Host "Microsoft.WinGet.Client module loaded successfully" -ForegroundColor Cyan
    }
} catch {
    Write-Error "Failed to load Microsoft.WinGet.Client module. Please install it with: Install-Module -Name Microsoft.WinGet.Client" -ErrorAction Stop
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

    foreach ($package in $UpgradeList) {
        if (-not ($toSkip.packages -contains $package.Id)) {
            $upgradeCount++
            Write-Host "Going to upgrade " -ForegroundColor Blue -NoNewline
            Write-Host "$($package.Id)" -ForegroundColor Green -NoNewline
            Write-Host " ($($package.InstalledVersion) -> $($package.AvailableVersions[0]))" -ForegroundColor Cyan
            
            $cmd = @"
Write-Host ''
Write-Host 'Finished upgrade process for ' -ForegroundColor Blue -NoNewline
Write-Host '$($package.Id)' -ForegroundColor Green
winget upgrade --id '$($package.Id)' --silent --accept-source-agreements --accept-package-agreements
Write-Host 'Details:'
"@
            $sb = [scriptblock]::Create($cmd)
            $job = Start-Job -ScriptBlock $sb
            
            if ($DebugMode) {
                Write-Host "Started job for $($package.Id) (Job ID: $($job.Id))" -ForegroundColor Cyan
            }
        } else {
            $skipCount++
            Write-Host "Skipped the upgrade for " -ForegroundColor Yellow -NoNewline
            Write-Host "$($package.Id)" -ForegroundColor Green -NoNewline
            Write-Host " ($($package.InstalledVersion) -> $($package.AvailableVersions[0]))" -ForegroundColor DarkGray
        }
    }

    Write-Host "`nSummary: $upgradeCount package(s) queued for upgrade, $skipCount package(s) skipped`n" -ForegroundColor Cyan

    # Check if there are any running jobs
    $runningJobs = Get-Job | Where-Object { $_.State -eq 'Running' }

    if ($runningJobs.Count -eq 0) {
        Write-Host 'No packages to upgrade.' -ForegroundColor Yellow
        return
    }

    # Progress animation
    $spinnerChars = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
    $spinnerIndex = 0
    $ProcessingDots = "."

    while ($runningJobs.Count -gt 0) {
        $runningJobs = Get-Job | Where-Object { $_.State -eq 'Running' }
        Write-Host "`rProcessing$ProcessingDots $($spinnerChars[$spinnerIndex])" -NoNewline
        $spinnerIndex = ($spinnerIndex + 1) % $spinnerChars.Count
        if($spinnerIndex -eq ($spinnerChars.Count - 1)) {
            $ProcessingDots += "."
        }
        
        $completedJobs = Get-Job -State Completed -HasMoreData $true
        
        foreach ($job in $completedJobs) {
            $jobOutput = $job | Receive-Job | Where-Object { $_ -notmatch '^\s*$' }
            
            if ($jobOutput.Count -gt 0) {
                Write-Host "`r                                        " -NoNewline
                Write-Host "`r"
                
                foreach ($line in $jobOutput) {
                    # Color the final status line appropriately
                    if ($line -eq $jobOutput[-1]) {
                        if ($line -match 'Successfully installed') {
                            Write-Host $line -ForegroundColor Green
                        } else {
                            Write-Host $line -ForegroundColor Red
                        }
                    } else {
                        Write-Host $line
                    }
                }
                
                Write-Host "`n$($runningJobs.Count) upgrade(s) remaining.`n" -ForegroundColor Cyan
                $ProcessingDots = ""
            }
        }

        if ($runningJobs.Count -gt 0) {
            Start-Sleep -Milliseconds 500
        }
    }
    
    # Process any remaining completed jobs
    Get-Job -State Completed -HasMoreData $true | Receive-Job | Where-Object { $_ -notmatch '^\s*$' } | ForEach-Object {
        Write-Host $_
    }
    
    # Clean up all jobs
    Get-Job | Remove-Job -Force
}

#region Main Script Execution

Write-Host "Checking for available package upgrades..." -ForegroundColor Cyan

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
    Write-Host "Found $($packagesWithUpdates.Count) package(s) with available upgrades:`n" -ForegroundColor Green
    
    $packagesWithUpdates | Format-Table -Property Id, InstalledVersion, @{
        Label = "AvailableVersion"
        Expression = { $_.AvailableVersions[0] }
    } -AutoSize
    
    Invoke-PackageUpgrade -UpgradeList $packagesWithUpdates
} else {
    Write-Host "No updates are available. Your system is up to date." -ForegroundColor Green
}

#endregion Main Script Execution
