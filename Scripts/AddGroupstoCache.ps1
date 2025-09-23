# Cache.ps1
# Query AD and build cache structure

$cacheDir = "$PSScriptRoot\..\Cache"
$cacheFile = "$cacheDir\AD_Cache.json"

if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir | Out-Null }

# Load the existing cache from AD_Cache.json if it exists
if (Test-Path $cacheFile) {
    $cacheObj = Get-Content -Path $cacheFile | ConvertFrom-Json
} else {
    Write-Host "Cache file does not exist. Exiting."
    exit
}

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

# Process OUs that do not have a Description (Description is null)
foreach ($ou in $cacheObj.OUs) {
    # Only process OUs with Description null (they have no description)
    if ($ou.Description -eq $null) {
        # No need to update, just keep them as they are
        continue
    }
}

# Save the updated cache back to the AD_Cache.json file
$cacheObj | ConvertTo-Json -Depth 5 | Set-Content -Path $cacheFile
Write-Host "Cache updated and saved to $cacheFile"
