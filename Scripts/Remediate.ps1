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

# === Prepare Dry Run Log ===
if ($DryRun) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $dryRunPath = ".\Logs\AD_DryRun_$timestamp.csv"
    $dryRunLog = @()
}

foreach ($entry in $report) {
    $user = Get-ADUser -Identity $entry.User
    $groups = $entry.MissingGroups -split ",\s*"

    foreach ($groupName in $groups) {
        try {
            if ($DryRun) {
                $dryRunLog += [PSCustomObject]@{
                    Timestamp = Get-Date
                    User      = $user.SamAccountName
                    Group     = $groupName
                    Action    = "Would Add"
                }
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

# === Save Dry Run Log ===
if ($DryRun -and $dryRunLog.Count -gt 0) {
    $dryRunLog | Export-Csv -Path $dryRunPath -NoTypeInformation

    # Keep only the 3 most recent dry-run logs
    $dryRunFiles = Get-ChildItem ".\Logs\AD_DryRun_*.csv" | Sort-Object LastWriteTime -Descending
    if ($dryRunFiles.Count -gt 3) {
        $dryRunFiles[3..($dryRunFiles.Count - 1)] | Remove-Item
    }
}
