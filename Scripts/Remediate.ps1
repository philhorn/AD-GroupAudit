param (
    [switch]$DryRun
)

Import-Module ActiveDirectory
. .\Scripts\Common.ps1

$errorLog = @()
$input = Import-Csv ".\Reports\AD_GroupAudit_Report.csv"

foreach ($entry in $input) {
    $user = $entry.Username
    $missingGroups = $entry.MissingGroups -split ', ' | ForEach-Object { $_.Trim() }

    foreach ($group in $missingGroups) {
        if ($DryRun) {
            Write-Host "DRY RUN: Would add $user to $group"
        } else {
            try {
                Add-ADGroupMember -Identity $group -Members $user -ErrorAction Stop
                Write-Host "✅ Added $user to $group"
            } catch {
                Log-Error -Context "Add-ADGroupMember" -Target "$user → $group" -Details $_.Exception.Message -ErrorLog ([ref]$errorLog)
                Write-Warning "⚠️ Failed to add $user to $group"
            }
        }
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$errorLog | Export-Csv ".\Logs\AD_ErrorLog_$timestamp.csv" -NoTypeInformation
