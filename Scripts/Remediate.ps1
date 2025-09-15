# Remediate.ps1
param (
    [switch]$DryRun
)

. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Cache.ps1"

$reportPath = ".\Reports\AD_GroupAudit_Report.csv"
if (-not (Test-Path $reportPath)) {
    Log-Error -Context "Remediate" -Target "Audit Report" -Details "Missing audit report"
    return
}

$report = Import-Csv $reportPath

foreach ($entry in $report) {
    $user = Get-ADUser -Identity $entry.User
    $groups = $entry.MissingGroups -split ",\s*"

    foreach ($groupName in $groups) {
        try {
            if ($DryRun) {
                Write-Host "[DryRun] Would add $($user.SamAccountName) to $groupName"
            } else {
                Add-ADGroupMember -Identity $groupName -Members $user
                Write-Host "[Live] Added $($user.SamAccountName) to $groupName"
            }
        } catch {
            Log-Error -Context "Remediate" -Target "$($user.SamAccountName)" -Details $_.Exception.Message
        }
    }
}
