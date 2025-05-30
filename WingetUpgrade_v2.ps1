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
    [bool]$DebugMode = $false
)

class Software
{
    [string]$Name
    [string]$Id
    [string]$Version
    [string]$AvailableVersion
}

# Import SkipList
try
{
    $skipListPath = Join-Path -Path $PSScriptRoot -ChildPath "WingetUpgrade_SkipLists.json"
    $toSkip = Get-Content $skipListPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    
    if ($DebugMode)
    {
        Write-Host "Skip list loaded successfully from $skipListPath" -ForegroundColor Cyan
        Write-Host "Packages in skip list: $($toSkip.packages.Count)" -ForegroundColor Cyan
    }
} catch
{
    Write-Error "Failed to load skip list: $_" -ErrorAction Stop
}

function New-UpgradeList
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Header,
        
        [Parameter(Mandatory = $true)]
        [int]$Footer,
        
        [Parameter(Mandatory = $false)]
        [int[]]$ErrorLines = @()
    )
   
    # Extract column positions from header
    $idStart = $lines[$Header].IndexOf("Id")
    $versionStart = $lines[$Header].IndexOf("Version")
    $availableStart = $lines[$Header].IndexOf("Available")
    $sourceStart = $lines[$Header].IndexOf("Source")
  
    # Process package information
    $upgradeList = [System.Collections.ArrayList]::new()
    
    for ($i = $Header + 1; $i -le $Footer; $i++)
    {
        # Skip error lines
        if ($ErrorLines -contains $i)
        {
            continue
        }

        $line = $lines[$i]

        if ($line.Length -gt ($availableStart + 1) -and -not $line.StartsWith('-'))
        {
            $software = [Software]::new()
            $software.Name = $line.Substring(0, $idStart).TrimEnd()
            $software.Id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
            $software.Version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
            $software.AvailableVersion = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
            
            [void]$upgradeList.Add($software)
        }
    }
  
    return $upgradeList
}

function Invoke-PackageUpgrade
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Software[]]$UpgradeList
    )

    $upgradeCount = 0
    $skipCount = 0

    foreach ($package in $UpgradeList)
    {
        if (-not ($toSkip.packages -contains $package.Id))
        {
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
            
            if ($DebugMode)
            {
                Write-Host "Started job for $($package.Id) (Job ID: $($job.Id))" -ForegroundColor Cyan
            }
        } else
        {
            $skipCount++
            Write-Host "Skipped the upgrade for " -ForegroundColor Yellow -NoNewline
            Write-Host "$($package.Id)" -ForegroundColor Green
        }
    }

    Write-Host "`nSummary: $upgradeCount package(s) queued for upgrade, $skipCount package(s) skipped`n" -ForegroundColor Cyan

    # Check if there are any running jobs
    $runningJobs = Get-Job | Where-Object { $_.State -eq 'Running' }

    if ($runningJobs.Count -eq 0)
    {
        Write-Host 'No packages to upgrade.' -ForegroundColor Yellow
        return
    }

    # Progress animation
    $spinnerChars = @("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
    $spinnerIndex = 0
    $ProcessingDots = "."

    while ($runningJobs.Count -gt 0)
    {
        $runningJobs = Get-Job | Where-Object { $_.State -eq 'Running' }
        Write-Host "`rProcessing$ProcessingDots $($spinnerChars[$spinnerIndex])" -NoNewline
        $spinnerIndex = ($spinnerIndex + 1) % $spinnerChars.Count
        if($spinnerIndex -eq ($spinnerChars.Count - 1))
        {
            $ProcessingDots += "."
        }
        
        $completedJobs = Get-Job -State Completed -HasMoreData $true
        
        foreach ($job in $completedJobs)
        {
            $jobOutput = $job | Receive-Job | Where-Object { $_ -notmatch '^\s' -and $_ -ne '' }
            
            if ($jobOutput.Count -gt 0)
            {
                Write-Host "`r                                        " -NoNewline
                Write-Host "`r"
                
                foreach ($line in $jobOutput)
                {
                    # Color the final status line appropriately
                    if ($line -eq $jobOutput[-1])
                    {
                        if ($line -match 'Successfully installed')
                        {
                            Write-Host $line -ForegroundColor Green
                        } else
                        {
                            Write-Host $line -ForegroundColor Red
                        }
                    } else
                    {
                        Write-Host $line
                    }
                }
                
                Write-Host "`n$($runningJobs.Count) upgrade(s) remaining.`n" -ForegroundColor Cyan
                $ProcessingDots = ""
            }
        }

        if ($runningJobs.Count -gt 0)
        {
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

function Test-WingetAvailability
{
    try
    {
        $null = & winget --version
        return $true
    } catch
    {
        Write-Error "Windows Package Manager (winget) is not installed or not available in PATH." -ErrorAction Stop
        return $false
    }

}

function Get-AvailableUpgrades
{
    [CmdletBinding()]
    param()
    
    Write-Host "Checking for available package upgrades..." -ForegroundColor Cyan
    
    try
    {
        $upgradeResult = & winget upgrade
        return $upgradeResult.Split([Environment]::NewLine)
    } catch
    {
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
for ($i = 0; $i -lt $lines.Count; $i++)
{
    # Find header lines (start with "Name")
    if ($lines[$i].StartsWith("Name"))
    {
        [void]$headerLines.Add($i)
    }
    
    # Find footer lines (contain "upgrades available.")
    if ($lines[$i].Contains("upgrades available."))
    {
        $hasUpgradeList = $true
        [void]$footerLines.Add($i)
        
        # Process regular upgrade list
        $upgradeList1 = New-UpgradeList -Header $headerLines[0] -Footer $footerLines[0] -ErrorLines $errorLines
        
        if ($DebugMode)
        {
            Write-Host "Standard upgrades available:" -ForegroundColor Cyan
            $upgradeList1 | Format-Table
        }
    }

    # Process explicit targeting upgrade list
    if (($footerLines.Count -gt 0) -and $lines[$i].StartsWith("Name") -and ($headerLines.Count -gt 1))
    {
        $hasExplicitUpgradeList = $true
        [void]$footerLines.Add($lines.Count - 1)
        
        $upgradeList2 = New-UpgradeList -Header $headerLines[1] -Footer $footerLines[1] -ErrorLines $errorLines
        
        if ($DebugMode)
        {
            Write-Host "Explicit targeting upgrades available:" -ForegroundColor Cyan
            $upgradeList2 | Format-Table
        }
    }

    # Detect error lines
    if ($lines[$i].Contains("<"))
    {
        Write-Host $lines[$i]
        Write-Host "This line contains an error. It will be automatically removed from the upgrade list." -ForegroundColor Red
        [void]$errorLines.Add($i)
    }
}

# Process available upgrades
if ($hasUpgradeList)
{
    $allUpgrades = [System.Collections.ArrayList]::new()
    [void]$allUpgrades.AddRange($upgradeList1)
    
    if ($hasExplicitUpgradeList)
    {
        if ($upgradeList2 -is [System.Array] -or $upgradeList2 -is [System.Collections.ICollection])
        {
            [void]$allUpgrades.AddRange($upgradeList2)
        } elseif ($upgradeList2 -is [Software])
        {
            # If upgradeList2 is a single Software object, use Add instead of AddRange
            [void]$allUpgrades.Add($upgradeList2)
        }
    }
    
    Write-Host "Found $($allUpgrades.Count) package(s) with available upgrades:`n" -ForegroundColor Green
    $allUpgrades | Format-Table
    
    Invoke-PackageUpgrade -UpgradeList $allUpgrades
} else
{
    Write-Host "No updates are available. Your system is up to date." -ForegroundColor Green
}

#endregion Main Script Execution

