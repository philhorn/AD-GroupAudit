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

# Optionally, get all groups (for lookup)
$groupList = Get-ADGroup -Filter * | Select-Object DistinguishedName, Name

$cacheObj = [PSCustomObject]@{
    Timestamp = (Get-Date).ToString("o")
    OUs       = $ouList
    Users     = $userList
    Groups    = $groupList
}

$cacheObj | ConvertTo-Json -Depth 5 | Set-Content $cacheFile

# Save full cache as AD_Cache_Original.json
$originalCacheFile = "$cacheDir\AD_Cache_Original.json"
$cacheObj | ConvertTo-Json -Depth 5 | Set-Content $originalCacheFile

# Filter OUs with non-empty Description
#$validOUs = $ouList | Where-Object { $_.Description -and $_.Description.Trim() -ne "" }

# Replace only the OUs in the cache object
#$cacheObj.OUs = $validOUs

# Save optimized cache as AD_Cache.json
$cacheObj | ConvertTo-Json -Depth 12 | Set-Content $cacheFile
Write-Host "Cache optimization complete. Saved to $cacheFile"


$Global:CacheTimestamp = Get-Date
Write-Host "Caching complete. Cache saved to $cacheFile"