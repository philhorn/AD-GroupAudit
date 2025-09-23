# parse the cache
# Load the AD_Cache.json file
$cacheFile = "$PSScriptRoot\..\Cache\AD_Cache.json"
$cacheObj = Get-Content -Path $cacheFile | ConvertFrom-Json

# Build a hash table for OUs and their expected groups
$ouGroupsHashTable = @{}
foreach ($ou in $cacheObj.OUs) {
    # If the OU has a description, use it for the group list
    if ($ou.Description -ne $null -and $ou.Description.Count -gt 0) {
        $ouGroupsHashTable[$ou.DistinguishedName] = $ou.Description
    }
}

# Get all users
$userList = $cacheObj.Users

# Output list for missing groups and extra groups
$missingGroups = @()
$extraGroups = @()

# Check each user
foreach ($user in $userList) {
    # Extract OU from user DistinguishedName
    $userOU = ($user.DistinguishedName -split ',')[1..100] -join ','

    # Check if user has groups listed in the OU descriptions
    if ($ouGroupsHashTable.ContainsKey($userOU)) {
        $expectedGroups = $ouGroupsHashTable[$userOU]
        $userGroups = $user.MemberOf

        # Find missing groups (groups the user should have, but doesn't)
        $missingGroupsForUser = $expectedGroups | Where-Object { $_ -notin $userGroups }
        $extraGroupsForUser = $userGroups | Where-Object { $_ -notin $expectedGroups }

        # Add missing groups to the list
        foreach ($missingGroup in $missingGroupsForUser) {
            $missingGroups += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                MissingGroup   = $missingGroup
            }
        }

        # Add extra groups to the list
        foreach ($extraGroup in $extraGroupsForUser) {
            $extraGroups += [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                ExtraGroup     = $extraGroup
            }
        }
    }
}


# Generate PowerShell script to add missing groups
$addMissingGroupsScript = $missingGroups | ForEach-Object {
    "Add-ADGroupMember -Identity '$($_.MissingGroup)' -Members '$($_.SamAccountName)'"
}

# Output the PowerShell script to a file
$addMissingGroupsScript | Set-Content "$PSScriptRoot\..\Reports\AddMissingGroups.ps1"
Write-Host "PowerShell script to add missing groups has been saved to Reports\AddMissingGroups.ps1"

# Export extra groups to a CSV file for auditing
$extraGroups | Export-Csv "$PSScriptRoot\..\Reports\ExtraGroups.csv" -NoTypeInformation
Write-Host "Extra groups have been exported to \Reports\ExtraGroups.csv"
