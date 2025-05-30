class Software {
    [string]$Name
    [string]$Id
    [string]$Version
    [string]$AvailableVersion
}

$upgradeResult = winget upgrade --include-unknown | Out-String

# Import SkipList
try{
  $LSPath = ".\WingetUpgrade_SkipLists.json" 
  $toSkip = (Get-Content $LSPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}

catch {
  Write-Error "$_" -ErrorAction Stop
}


# Create UpgradeListTable
function CreateUpgradeList([int]$header, [int]$footer, $err) {

  # Line $i has the header, we can find char where we find ID and Version
  $idStart = $lines[$header].IndexOf("Id")
  $versionStart = $lines[$header].IndexOf("Version")
  $availableStart = $lines[$header].IndexOf("Available")
  $sourceStart = $lines[$header].IndexOf("Source")
  
  # Now cycle in real package and split accordingly
  $upgradeList = @()
  $j = 0
  For ($i = $header + 1; $i -le $footer; $i++) 
  {
      if ($i -eq $err[$j]){
        Write-Error "This line contains an error. It will be automatically removed from the upgrade list."
        Write-Host "$lines[$i]`n"
        continue
      }

      $line = $lines[$i]

      if ($line.Length -gt ($availableStart + 1) -and -not $line.StartsWith('-'))
      {
          $name = $line.Substring(0, $idStart).TrimEnd()
          $id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
          $version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
          $available = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
          $software = [Software]::new()
          $software.Name = $name;
          $software.Id = $id;
          $software.Version = $version
          $software.AvailableVersion = $available;
  
          $upgradeList += $software
      }
  }
  
  return $upgradeList
}


# Upgrade by reffering upgradeListTable
function UpgradePackages($upgradeList){
  foreach ($package in $upgradeList) 
  {
      if (-not ($toSkip.packages -contains $package.Id)) 
      {
          Write-Host "Going to upgrade package " -ForegroundColor Blue -NoNewline
          Write-Host "$($package.id)" -Foreground Green
          winget upgrade $package.id --silent
          Write-Host ""
      }
      else 
      {    
          Write-Host "Skipped upgrade to package " -ForegroundColor Yellow -NoNewline
          Write-Host "$($package.id)`n" -ForegroundColor Green
      }
  }
}

# Check the flagged number of the lines 
$count = 0
$hl = @()
$fl = @()
$err = @() 
$flagList1 = $false
$flagList2 = $false


$lines = $upgradeResult.Split([Environment]::NewLine)

while ($count -le ($lines.Count - 1))
{
  # Find the line that starts with Name, it contains the header
  if($lines[$count].StartsWith("Name")){
    $flagList1 = $true
    $hl += $count
  }
  # Find the line that ends with "upgrades available.", it contains the footer
  if($lines[$count].Contains("upgrades available.")){
    $fl += $count
    $upgradeList1 = CreateUpgradeList $hl[0] $fl[0] $err 
    #$upgradeList1 | Format-Table
  }

  # The following packages have an upgrade available, but require explicit targeting for upgrade:
  if(($null -ne $fl[0]) -and $lines[$count].StartsWith("Name")){
    $flagList2 = $true
    $hl += $count
    $fl += $lines.Count
    $upgradeList2 = CreateUpgradeList $hl[1] $fl[1] $err
    #Write-Host "The following packages have an upgrade available, but require explicit targeting for upgrade:"
    #$upgradeList2 | Format-Table
    #Write-Host ""
  }

  if($lines[$count].Contains("<")){
    $err += $count
  }

  $count++
}


try{
  if ($flagList1){
    if($flagList2){
      $upgradeList1 += $upgradeList2
    }
    $upgradeList1 | Format-Table
    Write-Host "$($upgradeList1.Count) upgrades available.`n"
    UpgradePackages $upgradeList1
  }
  else{
    Write-Host "No updates are available. Your system is up to date." -ErrorAction Stop
  }
}

catch{
  Write-Error "$_" -ErrorAction Stop
}
