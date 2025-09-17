param (
    [switch]$FromGUI
)

# === Load Shared Modules ===
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Cache.ps1"

# === Ensure Cache Is Fresh ===
Test-CacheFreshness -ScriptRoot $PSScriptRoot -FromGUI:$FromGUI

# === Load Previous and Current Reports ===
$previousReport = "$PSScriptRoot\Reports\AD_GroupAudit_Previous.csv"
$currentReport  = "$PSScriptRoot\Reports\AD_GroupAudit_Report.csv"
$outputReport   = "$PSScriptRoot\Reports\AD_GroupAudit_Changes.csv"

if (!(Test-Path $previousReport) -or !(Test-Path $currentReport)) {
    Write-Host "[Error] One or both report files are missing."
    return
}

$prevData = Import-Csv $previousReport
$currData = Import-Csv $currentReport

# === Compare Logic ===
$changes = @()

foreach ($curr in $currData) {
    $match = $prevData | Where-Object { $_.User -eq $curr.User -and $_.Group -eq $curr.Group }
    if (-not $match) {
        $changes += [PSCustomObject]@{
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")
            User      = $curr.User
            Group     = $curr.Group
            Status    = "Added"
        }
    }
}

foreach ($prev in $prevData) {
    $match = $currData | Where-Object { $_.User -eq $prev.User -and $_.Group -eq $prev.Group }
    if (-not $match) {
        $changes += [PSCustomObject]@{
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")
            User      = $prev.User
            Group     = $prev.Group
            Status    = "Removed"
        }
    }
}

# === Output Results ===
$changes | Export-Csv $outputReport -NoTypeInformation

if ($FromGUI) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $form = [System.Windows.Forms.Application]::OpenForms[0]
        $statusBox = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.RichTextBox] }
        if ($statusBox) {
            $statusBox.SelectionStart = $statusBox.TextLength
            $statusBox.SelectionColor = [System.Drawing.Color]::Green
            $statusBox.AppendText("[OK] Comparison complete. Changes saved to AD_GroupAudit_Changes.csv`r`n")
            $statusBox.SelectionColor = $statusBox.ForeColor
        }
    } catch {
        Write-Host "[OK] Comparison complete. Changes saved to AD_GroupAudit_Changes.csv"
    }
} else {
    Write-Host "[OK] Comparison complete. Changes saved to AD_GroupAudit_Changes.csv"
}
