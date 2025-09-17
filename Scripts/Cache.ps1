# Cache.ps1
Write-Host "Caching AD data... Cache.ps1 invoked at $(Get-Date -Format 'HH:mm:ss')"

$Global:GroupCache = Get-ADGroup -Filter * | Group-Object DistinguishedName -AsHashTable
$Global:UserCache = Get-ADUser -Filter * -Properties MemberOf, DistinguishedName
$Global:OUCache = Get-ADOrganizationalUnit -Filter * -Properties Description | Group-Object DistinguishedName -AsHashTable

$Global:CacheTimestamp = Get-Date
Write-Host "Caching complete."
