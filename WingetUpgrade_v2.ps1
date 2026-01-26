<#
.SYNOPSIS
    Automatically upgrades packages managed by Windows Package Manager (winget)

.DESCRIPTION
    This script automates the process of upgrading packages using Windows Package Manager (winget).
    It detects available updates, filters them against a skip list, and performs upgrades in parallel.

.NOTES
    File Name      : WingetUpgrade_v2.ps1
    Prerequisite   : Windows Package Manager (winget)
    Version        : 2.1

.PARAMETER DebugMode
    Enables debug output for troubleshooting

.EXAMPLE
    .\WingetUpgrade_v2.ps1
    Runs the script with default settings

.EXAMPLE
    .\WingetUpgrade_v2.ps1 -DebugMode $true
    Runs the script with debug information enabled
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [bool]$DebugMode = $true
)

class Software {
    [string]$Name
    [string]$Id
    [string]$Version
    [string]$AvailableVersion
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

function New-UpgradeList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Header,
        
        [Parameter(Mandatory = $true)]
        [int]$Footer,
        
        [Parameter(Mandatory = $false)]
        [int[]]$ErrorLines = @()
    )
   
    # Process package information
    $upgradeList = [System.Collections.ArrayList]::new()
    # Support both formats: with and without Source column
    $pattern = '^(.+?)\s{2,}([\S]+)\s+([\S]+)\s+([\S]+)(?:\s+([\S]+))?\s*$'
   
    for ($i = $Header + 1; $i -le $Footer; $i++) {
        # Skip error lines
        if ($ErrorLines -contains $i) {
            continue
        }

        $line = $lines[$i]
        
        if ($DebugMode) {
            Write-Host "Line $i`: $line" -ForegroundColor DarkGray
        }

        if ($line -notlike '---*' -and $line.Trim() -ne '' -and $line -match $pattern) {
            $software = [Software]::new()
            $software.Name = $matches[1].TrimEnd()
            $software.Id = $matches[2].TrimEnd()
            $software.Version = $matches[3].TrimEnd()
            $software.AvailableVersion = $matches[4].TrimEnd()
           
            if ($DebugMode) {
                Write-Host "Matched: $($software.Id)" -ForegroundColor Green
            }
           
            [void]$upgradeList.Add($software)
        } elseif ($DebugMode -and $line.Trim() -ne '' -and $line -notlike '---*') {
            Write-Host "Not matched: $line" -ForegroundColor Red
        }
    }
  
    return $upgradeList
}

function Invoke-PackageUpgrade {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Software[]]$UpgradeList
    )

    $upgradeCount = 0
    $skipCount = 0

    foreach ($package in $UpgradeList) {
        if (-not ($toSkip.packages -contains $package.Id)) {
            $upgradeCount++
            Write-Host "Going to upgrade " -ForegroundColor Blue -NoNewline
            Write-Host "$($package.Id)" -ForegroundColor Green
            
            $cmd = @"
Write-Host ''
Write-Host 'Finished upgrade process for ' -ForegroundColor Blue -NoNewline
Write-Host '$($package.Id)' -ForegroundColor Green
winget upgrade '$($package.Id)' --silent
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
            Write-Host "$($package.Id)" -ForegroundColor Green
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
            $jobOutput = $job | Receive-Job | Where-Object { $_ -notmatch '^\s' -and $_ -ne '' }
            
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
    Get-Job -State Completed -HasMoreData $true | Receive-Job | Where-Object { $_ -notmatch '^\s' -and $_ -ne '' } | ForEach-Object {
        Write-Host $_
    }
    
    # Clean up all jobs
    Get-Job | Remove-Job -Force
}

#region Main Script Execution

function Test-WingetAvailability {
    try {
        $null = & winget --version
        return $true
    } catch {
        Write-Error "Windows Package Manager (winget) is not installed or not available in PATH." -ErrorAction Stop
        return $false
    }

}

function Get-AvailableUpgrades {
    [CmdletBinding()]
    param()
    
    Write-Host "Checking for available package upgrades..." -ForegroundColor Cyan
    
    try {
        # Set a very large buffer width to prevent line wrapping
        $originalWidth = $Host.UI.RawUI.BufferSize.Width
        $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(500, 3000)
        
        # Use --disable-interactivity to get full output without truncation
        $upgradeResult = & winget upgrade --disable-interactivity
        
        # Restore original buffer width
        $currentSize = $Host.UI.RawUI.BufferSize
        $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size($originalWidth, $currentSize.Height)
        
        return $upgradeResult.Split([Environment]::NewLine)
    } catch {
        Write-Error "Failed to get available upgrades: $_" -ErrorAction Stop
    }
}

# Verify winget is available
Test-WingetAvailability | Out-Null

# Get available upgrades
$lines = Get-AvailableUpgrades

# Initialize variables
$headerLines = [System.Collections.ArrayList]::new()
$footerLines = [System.Collections.ArrayList]::new()
$errorLines = [System.Collections.ArrayList]::new()
$hasUpgradeList = $false
$hasExplicitUpgradeList = $false

# Process winget output
for ($i = 0; $i -lt $lines.Count; $i++) {
    # Find header lines (start with "Name")
    if ($lines[$i].StartsWith("Name")) {
        [void]$headerLines.Add($i)
    }
    
    # Find footer lines (contain "upgrades available.")
    if ($lines[$i].Contains("upgrades available.")) {
        $hasUpgradeList = $true
        [void]$footerLines.Add($i)
        
        # Process regular upgrade list
        $upgradeList1 = New-UpgradeList -Header $headerLines[0] -Footer $footerLines[0] -ErrorLines $errorLines
        
        if ($DebugMode) {
            Write-Host "Standard upgrades available:" -ForegroundColor Cyan
            $upgradeList1 | Format-Table -AutoSize -Wrap
        }
    }

    # Process explicit targeting upgrade list
    if (($footerLines.Count -gt 0) -and $lines[$i].StartsWith("The following packages")) {
        if ($DebugMode) {
            Write-Host "Found explicit targeting section at line $i" -ForegroundColor Cyan
        }
        
        # Find the next "Name" header line after this message
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            if ($lines[$j].StartsWith("Name")) {
                $hasExplicitUpgradeList = $true
                [void]$headerLines.Add($j)
                
                # Find the end of this section (empty line or end of output)
                $sectionEnd = $lines.Count - 1
                for ($k = $j + 1; $k -lt $lines.Count; $k++) {
                    if ($lines[$k].Trim() -eq '' -and $lines[$k + 1].Trim() -eq '') {
                        $sectionEnd = $k - 1
                        break
                    }
                }
                [void]$footerLines.Add($sectionEnd)
                
                if ($DebugMode) {
                    Write-Host "Explicit header at line $j, footer at line $sectionEnd" -ForegroundColor Cyan
                }
                
                $upgradeList2 = New-UpgradeList -Header $headerLines[1] -Footer $footerLines[1] -ErrorLines $errorLines
                
                if ($DebugMode) {
                    Write-Host "Explicit targeting upgrades available:" -ForegroundColor Cyan
                    $upgradeList2 | Format-Table -AutoSize -Wrap
                }
                break
            }
        }
    }

    # Detect error lines
    if ($lines[$i].Contains("<")) {
        Write-Host $lines[$i]
        Write-Host "This line contains an error. It will be automatically removed from the upgrade list." -ForegroundColor Red
        [void]$errorLines.Add($i)
    }
}

# Process available upgrades
if ($hasUpgradeList) {
    $allUpgrades = [System.Collections.ArrayList]::new()
    
    # Safely add upgradeList1
    if ($upgradeList1) {
        if ($upgradeList1 -is [System.Array] -or $upgradeList1 -is [System.Collections.ICollection]) {
            [void]$allUpgrades.AddRange($upgradeList1)
        } elseif ($upgradeList1 -is [Software]) {
            [void]$allUpgrades.Add($upgradeList1)
        }
    }
    
    # Safely add upgradeList2
    if ($hasExplicitUpgradeList -and $upgradeList2) {
        if ($upgradeList2 -is [System.Array] -or $upgradeList2 -is [System.Collections.ICollection]) {
            [void]$allUpgrades.AddRange($upgradeList2)
        } elseif ($upgradeList2 -is [Software]) {
            [void]$allUpgrades.Add($upgradeList2)
        }
    }
    
    if ($allUpgrades.Count -eq 0) {
        Write-Host "No valid upgrades found after filtering." -ForegroundColor Yellow
        return
    }
    
    Write-Host "Found $($allUpgrades.Count) package(s) with available upgrades:`n" -ForegroundColor Green
    $allUpgrades | Format-Table
    
    Invoke-PackageUpgrade -UpgradeList $allUpgrades
} else {
    Write-Host "No updates are available. Your system is up to date." -ForegroundColor Green
}

#endregion Main Script Execution

