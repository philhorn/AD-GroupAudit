Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Main Form ===
$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Group Audit Dashboard"
$form.Size = New-Object System.Drawing.Size(900, 600)
$form.StartPosition = "CenterScreen"

# === Dry Run Checkbox ===
$dryRunCheckbox = New-Object System.Windows.Forms.CheckBox
$dryRunCheckbox.Text = "Dry Run Mode"
$dryRunCheckbox.Location = New-Object System.Drawing.Point(20, 20)
$dryRunCheckbox.Checked = $true
$form.Controls.Add($dryRunCheckbox)

# === Status Console ===
$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Multiline = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.Size = New-Object System.Drawing.Size(850, 100)
$statusBox.Location = New-Object System.Drawing.Point(20, 450)
$statusBox.ReadOnly = $true
$form.Controls.Add($statusBox)

function LogStatus($msg) {
    $statusBox.AppendText("$msg`r`n")
}

# === CSV Preview Panel ===
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Size = New-Object System.Drawing.Size(600, 350)
$grid.Location = New-Object System.Drawing.Point(270, 20)
$grid.AutoSizeColumnsMode = "Fill"
$form.Controls.Add($grid)

function LoadCsvIntoGrid($path) {
    if (Test-Path $path) {
        $csv = Import-Csv $path
        $grid.DataSource = $csv
    } else {
        [System.Windows.Forms.MessageBox]::Show("CSV not found: $path")
    }
}

# === Button Factory ===
function CreateButton($text, $x, $y, $action) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Size = New-Object System.Drawing.Size(220, 40)
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Add_Click($action)
    $form.Controls.Add($btn)
}

# === Buttons ===
CreateButton "Run Audit" 20 60 {
    & ".\Scripts\Audit.ps1"
    LoadCsvIntoGrid "Reports\AD_GroupAudit_Report.csv"
    LogStatus "✅ Audit complete"
}

CreateButton "Run Extra Groups Report" 20 110 {
    & ".\Scripts\ExtraGroups.ps1"
    LoadCsvIntoGrid "Reports\AD_ExtraGroups_Report.csv"
    LogStatus "✅ Extra groups report complete"
}

CreateButton "Run Remediation" 20 160 {
    if ($dryRunCheckbox.Checked) {
        & ".\Scripts\Remediate.ps1" -DryRun
        LogStatus "🧪 Dry run remediation complete"
    } else {
        & ".\Scripts\Remediate.ps1"
        LogStatus "✅ Live remediation complete"
    }
}

CreateButton "Compare Reports" 20 210 {
    & ".\Scripts\CompareReports.ps1"
    LoadCsvIntoGrid "Reports\AD_GroupAudit_Changes.csv"
    LogStatus "✅ Comparison complete"
}

CreateButton "View Latest Error Log" 20 260 {
    $latestLog = Get-ChildItem ".\Logs\AD_ErrorLog_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        LoadCsvIntoGrid $latestLog.FullName
        LogStatus "📄 Loaded error log: $($latestLog.Name)"
    } else {
        LogStatus "⚠️ No error logs found"
    }
}

# === Launch GUI ===
[void]$form.ShowDialog()
