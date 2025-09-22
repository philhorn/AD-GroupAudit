param(
    [switch]$DryRun,
    [switch]$FromGUI
)

. "$PSScriptRoot\Common.ps1"
$logPath = "$PSScriptRoot\..\Logs\AD_ErrorLog.csv"
Write-Host "Running Audit. DryRun: $DryRun FromGUI: $FromGUI"

Test-CacheFreshness -ScriptRoot $PSScriptRoot -FromGUI:$FromGUI

# Reload the cache from file after freshness check
$cacheFile = "$PSScriptRoot\..\Cache\AD_Cache.json"
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

$results = @()
$extraGroupsResults = @()

foreach ($user in $UserCache) {
    $userGroups = @()
    if ($user.MemberOf) {
        $userGroups = $user.MemberOf | ForEach-Object {
            if ($groupHash.ContainsKey($_)) { $groupHash[$_] }
        }
    }

    $requiredGroups = Get-InheritedGroups $user.OU $OUCache
    $missing = $requiredGroups | Where-Object { $_ -and ($_ -notin $userGroups) }
    $extra = $userGroups | Where-Object { $_ -and ($_ -notin $requiredGroups) }

    $ouEntry = $OUCache | Where-Object { $_.DistinguishedName -eq $user.OU }
    $ouName = if ($ouEntry) { $ouEntry.Name } else { $user.OU }

    if ($missing.Count -gt 0) {
        $results += [PSCustomObject]@{
            User             = $user.SamAccountName
            OU               = $ouName
            MissingGroups    = ($missing -join ", ")
        }
    }

    if ($extra.Count -gt 0) {
        $extraGroupsResults += [PSCustomObject]@{
            User         = $user.SamAccountName
            OU           = $ouName
            ExtraGroups  = ($extra -join ", ")
        }
    }
}

$results | Export-Csv -Path "$PSScriptRoot\..\Reports\AD_GroupAudit_Report.csv" -NoTypeInformation
$extraGroupsResults | Export-Csv -Path "$PSScriptRoot\..\Reports\AD_ExtraGroups_Report.csv" -NoTypeInformation