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
function Ensure-FreshCache {
    param (
        [string]$ScriptRoot,
        [switch]$FromGUI
    )

    if (-not $Global:CacheTimestamp -or ((Get-Date) - $Global:CacheTimestamp).TotalHours -gt $Global:CacheTimeoutHours) {
        . "$ScriptRoot\Cache.ps1"
        $refreshedAt = Get-Date -Format "yyyy-MM-dd HH:mm"

        if ($FromGUI) {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                $form = [System.Windows.Forms.Application]::OpenForms[0]
                $statusBox = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.RichTextBox] }
                if ($statusBox) {
                    $statusBox.SelectionStart = $statusBox.TextLength
                    $statusBox.SelectionColor = [System.Drawing.Color]::Green
                    $statusBox.AppendText("[OK] Cache refreshed at $refreshedAt`r`n")
                    $statusBox.SelectionColor = $statusBox.ForeColor
                }
            } catch {
                Write-Host "[Warning] GUI logging failed. Falling back to console."
                Write-Host "[OK] Cache refreshed at $refreshedAt"
            }
        } else {
            Write-Host "[OK] Cache refreshed at $refreshedAt"
        }
    }
}


function Get-InheritedGroups {
    param ($OU)
    if ($OU.Description -and $OU.Description.Contains(":")) {
        return $OU.Description.Split(":")[1].Split(",").Trim()
    }
    return @()
}
