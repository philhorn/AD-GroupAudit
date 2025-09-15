Import-Module ActiveDirectory
. .\Scripts\Common.ps1

$errorLog = @()
$report = @()
$OUs = Get-ADOrganizationalUnit -Filter * -Properties Description

foreach ($OU in $OUs) {
    $requiredGroups = Get-InheritedGroups -OU $OU.DistinguishedName
    try {
        $users = Get-ADUser -Filter * -SearchBase $OU.DistinguishedName -SearchScope OneLevel -Properties MemberOf
    } catch {
        Log-Error -Context "Get-ADUser" -Target $OU.DistinguishedName -Details $_.Exception.Message -ErrorLog ([ref]$errorLog)
        continue
    }

    foreach ($user in $users) {
        try {
            $userGroups = ($user.MemberOf | ForEach-Object {
                (Get-ADGroup -Identity $_).Name
            }) | Sort-Object -Unique
        } catch {
            Log-Error -Context "Get-ADGroup" -Target $user.SamAccountName -Details $_.Exception.Message -ErrorLog ([ref]$errorLog)
            continue
        }

        $missingGroups = $requiredGroups | Where-Object { $_ -notin $userGroups }

        if ($missingGroups.Count -gt 0) {
            $report += [PSCustomObject]@{
                Username      = $user.SamAccountName
                OU            = $OU.DistinguishedName
                MissingGroups = ($missingGroups -join ', ')
            }
        }
    }
}

$report | Export-Csv ".\Reports\AD_GroupAudit_Report.csv" -NoTypeInformation
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$errorLog | Export-Csv ".\Logs\AD_ErrorLog_$timestamp.csv" -NoTypeInformation
