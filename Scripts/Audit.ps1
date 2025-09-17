# In Scripts/Audit.ps1
. "$PSScriptRoot\Common.ps1"
$logPath = "$PSScriptRoot\..\Logs\AD_ErrorLog.csv"
Write-Host "Running Audit. DryRun: $DryRun FromGUI: $FromGUI"

Test-CacheFreshness -ScriptRoot $PSScriptRoot -FromGUI:$FromGUI

# 2. Always reload the cache from file after freshness check
$cacheFile = "$PSScriptRoot\..\Cache\AD_Cache.json"
if (Test-Path $cacheFile) {
    $cacheObj = Get-Content $cacheFile | ConvertFrom-Json
    $OUCache = $cacheObj.OUs
    $CacheTimestamp = [datetime]$cacheObj.Timestamp
} else {
    Write-Host "[Error] Cache file not found: $cacheFile"
    exit 1
}



$results = @()

foreach ($user in $UserCache) {
    $userDN = $user.DistinguishedName
    $userGroups = $user.MemberOf | ForEach-Object {
        if ($GroupCache.ContainsKey($_)) {
            $GroupCache[$_].Name
        }
    }

    $ou = ($OUCache[$userDN] -as [Microsoft.ActiveDirectory.Management.ADOrganizationalUnit])
    $requiredGroups = Get-InheritedGroups $ou

    $missing = $requiredGroups | Where-Object { $_ -notin $userGroups }

    if ($missing.Count -gt 0) {
        $results += [PSCustomObject]@{
            User             = $user.SamAccountName
            OU               = $ou.Name
            MissingGroups    = ($missing -join ", ")
        }
    }
}






$results = @()

# Example: Loop through cached OUs and groups
foreach ($ouEntry in $OUCache) {
    $ouName = $ouEntry.OU
    $groups = $ouEntry.Groups
    # ...your audit logic here...
}

# Example output (replace with your real logic)
$results | Export-Csv -Path "$PSScriptRoot\..\Reports\AD_GroupAudit_Report.csv" -NoTypeInformation