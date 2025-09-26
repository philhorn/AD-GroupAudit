#. "$PSScriptRoot\Scripts\Common.ps1"
$logPath = "$PSScriptRoot\Logs\AD_ErrorLog.csv"
Write-Host "Running Audit. DryRun: $DryRun FromGUI: $FromGUI"

#Test-CacheFreshness -ScriptRoot $PSScriptRoot -FromGUI:$FromGUI

# Reload the cache from file after freshness check
$cacheFile = "$PSScriptRoot\Cache\AD_Cache.json"
if (Test-Path $cacheFile) {
    $cacheObj = Get-Content $cacheFile | ConvertFrom-Json
    $OUCache = $cacheObj.OUs
    $UserCache = $cacheObj.Users
    $GroupCache = $cacheObj.Groups
    $CacheTimestamp = [datetime]$cacheObj.Timestamp
} else {
    Write-Host "[Error] Cache file not found: $cacheFile"
    exit 1
}

# Build a hashtable for group DN -> group name
$groupHash = @{}
foreach ($g in $GroupCache) { $groupHash[$g.DistinguishedName] = $g.Name }

function Get-InheritedGroups {
    param (
        [string]$ouDn,
        $ouCache
    )
    $groups = @()
    $currentDn = $ouDn
    while ($currentDn) {
        $ou = $ouCache | Where-Object { $_.DistinguishedName -eq $currentDn }
        if ($ou -and $ou.Description -and $ou.Description.Contains(":")) {
            $descGroups = $ou.Description.Split(":")[1].Split(",").Trim()
            $groups += $descGroups
        }
        # Move up to parent OU
        if ($currentDn -match '^OU=[^,]+,(.+)$') {
            $currentDn = $matches[1]
        } else {
            $currentDn = $null
        }
    }
    return $groups | Where-Object { $_ -ne "" } | Select-Object -Unique
}

$results = @()

foreach ($user in $UserCache) {
    $userGroups = @()
    if ($user.MemberOf) {
        $userGroups = $user.MemberOf | ForEach-Object {
            if ($groupHash.ContainsKey($_)) { $groupHash[$_] }
        }
    }

    $requiredGroups = Get-InheritedGroups $user.OU $OUCache
    $missing = $requiredGroups | Where-Object { $_ -and ($_ -notin $userGroups) }

    if ($missing.Count -gt 0) {
        $ouEntry = $OUCache | Where-Object { $_.DistinguishedName -eq $user.OU }
        $results += [PSCustomObject]@{
            User             = $user.SamAccountName
            OU               = $ouEntry.Name
            MissingGroups    = ($missing -join ", ")
        }
    }
}

$results | Export-Csv -Path "$PSScriptRoot\Reports\AD_GroupAudit_Report.csv" -NoTypeInformation
