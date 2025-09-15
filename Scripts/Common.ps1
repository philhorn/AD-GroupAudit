# Common.ps1
#AD_GroupAudit/
#├── Scripts/
#│   ├── Audit.ps1
#│   ├── ExtraGroups.ps1
#│   ├── Remediate.ps1
#│   └── CompareReports.ps1
#├── Logs/
#│   └── AD_ErrorLog_YYYYMMDD_HHMMSS.csv
#├── Reports/
#│   ├── AD_GroupAudit_Report.csv
#│   ├── AD_ExtraGroups_Report.csv
#│   └── AD_GroupAudit_Changes.csv



function Log-Error {
    param (
        [string]$Context,
        [string]$Target,
        [string]$Details,
        [ref]$ErrorLog
    )
    $ErrorLog.Value += [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("s")
        Context   = $Context
        Target    = $Target
        Error     = $Details
    }
}

function Get-InheritedGroups {
    param ($OU)
    $groups = @()
    while ($OU) {
        try {
            $desc = (Get-ADOrganizationalUnit -Identity $OU -Properties Description).Description
            if ($desc) {
                $groups += $desc -split '[,;]' | ForEach-Object { $_.Trim() }
            }
        } catch {
            # Skip broken OU
            break
        }
        $parentDN = ($OU -split ',')[1..($OU.Length)] -join ','
        $OU = if ($parentDN -match '^OU=') { $parentDN } else { $null }
    }
    return $groups | Sort-Object -Unique
}
