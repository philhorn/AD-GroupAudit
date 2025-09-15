# ExtraGroups.ps1
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Cache.ps1"

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

    $extra = $userGroups | Where-Object { $_ -notin $requiredGroups }

    if ($extra.Count -gt 0) {
        $results += [PSCustomObject]@{
            User          = $user.SamAccountName
            OU            = $ou.Name
            ExtraGroups   = ($extra -join ", ")
        }
    }
}

$results | Export-Csv -Path ".\Reports\AD_ExtraGroups_Report.csv" -NoTypeInformation
