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

$Global:CacheTimestamp = Get-Date
Write-Host "Caching complete. Cache saved to $cacheFile"