# Audit.ps1
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

    $missing = $requiredGroups | Where-Object { $_ -notin $userGroups }

    if ($missing.Count -gt 0) {
        $results += [PSCustomObject]@{
            User             = $user.SamAccountName
            OU               = $ou.Name
            MissingGroups    = ($missing -join ", ")
        }
    }
}

$results | Export-Csv -Path ".\Reports\AD_GroupAudit_Report.csv" -NoTypeInformation
