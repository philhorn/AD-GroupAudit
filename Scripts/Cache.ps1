# Cache.ps1
# Query AD and build cache structure

$cacheDir = "$PSScriptRoot\..\Cache"
$cacheFile = "$cacheDir\AD_Cache.json"
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir | Out-Null }

# Get all OUs with their descriptions
$ouList = Get-ADOrganizationalUnit -Filter * -Properties Description | Select-Object DistinguishedName, Name, Description

# Get all users with their group memberships and OU

$userList = Get-ADUser -Filter * -Properties MemberOf, DistinguishedName, SamAccountName | ForEach-Object {
    $ouDn = ($_.DistinguishedName -split ',(?=OU=)')[1..100] -join ',' # Get the OU part of the DN
    [PSCustomObject]@{
        SamAccountName    = $_.SamAccountName
        DistinguishedName = $_.DistinguishedName
        OU                = $ouDn
        MemberOf          = @($_.MemberOf) # Array of group DNs
    }
}

# Get all groups (for lookup)
$groupList = Get-ADGroup -Filter * | Select-Object DistinguishedName, Name

$cacheObj = [PSCustomObject]@{
    Timestamp = (Get-Date).ToString("o")
    OUs       = $ouList
    Users     = $userList
    Groups    = $groupList
}

$cacheObj | ConvertTo-Json -Depth 12 | Set-Content $cacheFile

# Save full cache as AD_Cache_Original.json
$originalCacheFile = "$cacheDir\AD_Cache_Original.json"
$cacheObj | ConvertTo-Json -Depth 5 | Set-Content $originalCacheFile

# Filter OUs with non-empty Description
#$validOUs = $ouList | Where-Object { $_.Description -and $_.Description.Trim() -ne "" }

# Replace only the OUs in the cache object
#$cacheObj.OUs = $validOUs

# Process OUs that already have a Description (non-null, non-empty)
foreach ($ou in $cacheObj.OUs) {
    # Only process OUs that have a valid description (non-null)
    if ($ou.Description -ne $null -and $ou.Description.Count -gt 0) {
        # Use ADSI to search for the OU's full details
        $searcher = New-Object DirectoryServices.DirectorySearcher([ADSI]"LDAP://$($ou.DistinguishedName)")
        $searcher.PropertiesToLoad.Add("Description")
        $searcher.PropertiesToLoad.Add("Name")

        # Execute the search to retrieve the full details
        $results = $searcher.FindOne()

        # If results are found, update the OU object with the retrieved description
        if ($results) {
            $description = $results.Properties["Description"]
            $name = $results.Properties["Name"]

            # If no description found, set it to empty array
            if (-not $description) {
                $description = @()
            }

            # Update the OU object in the cache
            $ou.Description = $description
            $ou.Name = $name
        }
    }
}


# Save optimized cache as AD_Cache.json
$cacheObj | ConvertTo-Json -Depth 12 | Set-Content $cacheFile
Write-Host "Cache optimization complete. Saved to $cacheFile"


$Global:CacheTimestamp = Get-Date
Write-Host "Caching complete. Cache saved to $cacheFile"