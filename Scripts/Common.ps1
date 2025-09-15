# Common.ps1
#AD_GroupAudit/
#├── Scripts/
#│   ├── Audit.ps1
#│   ├── ExtraGroups.ps1
#│   ├── Remediate.ps1
#│   └── CompareReports.ps1
#│   └── Common.ps1
#│   └── Cache.ps1
#├── Logs/
#│   └── AD_ErrorLog_YYYYMMDD_HHMMSS.csv
#├── Reports/
#│   ├── AD_GroupAudit_Report.csv
#│   ├── AD_ExtraGroups_Report.csv
#│   └── AD_GroupAudit_Changes.csv

# Common.ps1

function Log-Error {
    param (
        [string]$Context,
        [string]$Target,
        [string]$Details
    )
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logPath = ".\Logs\AD_ErrorLog_$timestamp.csv"
    $entry = [PSCustomObject]@{
        Timestamp = Get-Date
        Context   = $Context
        Target    = $Target
        Details   = $Details
    }
    $entry | Export-Csv -Path $logPath -Append -NoTypeInformation
}

function Get-InheritedGroups {
    param ($OU)
    if ($OU.Description -and $OU.Description.Contains(":")) {
        return $OU.Description.Split(":")[1].Split(",").Trim()
    }
    return @()
}
