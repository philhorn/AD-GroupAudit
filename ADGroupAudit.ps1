Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Main Form ===
$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Group Audit Dashboard"
$form.Size = New-Object System.Drawing.Size(950, 600)
$form.StartPosition = "CenterScreen"

# === Dry Run Checkbox ===
$dryRunCheckbox = New-Object System.Windows.Forms.CheckBox
$dryRunCheckbox.Text = "Dry Run Mode"
$dryRunCheckbox.Location = New-Object System.Drawing.Point(20, 20)
$dryRunCheckbox.Checked = $true
$form.Controls.Add($dryRunCheckbox)

# === RichTextBox for Status Console ===
$statusBox = New-Object System.Windows.Forms.RichTextBox
$statusBox.Size = New-Object System.Drawing.Size(900, 100)
$statusBox.Location = New-Object System.Drawing.Point(20, 450)
$statusBox.ReadOnly = $true
$form.Controls.Add($statusBox)

function LogStatus {
    param (
        [string]$Message,
        [string]$Type = "Info"  # Info, OK, Error, Warning
    )
    $color = switch ($Type) {
        "OK"      { "Green" }
        "Error"   { "Red" }
        "Warning" { "Orange" }
        default   { "Black" }
    }

    $statusBox.SelectionStart = $statusBox.TextLength
    $statusBox.SelectionColor = [System.Drawing.Color]::$color
    $statusBox.AppendText("$Message`r`n")
    $statusBox.SelectionColor = $statusBox.ForeColor
}

# === CSV Preview Grid ===
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Size = New-Object System.Drawing.Size(600, 400)
$grid.Location = New-Object System.Drawing.Point(320, 20)
$grid.AutoSizeColumnsMode = "Fill"
$form.Controls.Add($grid)

function LoadCsvIntoGrid($path) {
    if (Test-Path $path) {
        $csv = Import-Csv $path
        $grid.DataSource = $csv
    } else {
        LogStatus "[Warning] CSV not found: $path" "Warning"
    }
}

# === Button Factory ===
function CreateButton($text, $x, $y, $scriptPath, $csvPath) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Size = New-Object System.Drawing.Size(280, 40)
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Add_Click({
        LogStatus "[Running] $text started..."
        $job = Start-Job -ScriptBlock {
            & $using:scriptPath
        }

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $timer.Add_Tick({
            if ($job.State -ne 'Running') {
                $timer.Stop()
                Receive-Job $job | Out-Null
                Remove-Job $job
                LogStatus "[OK] $text complete." "OK"
                if ($csvPath) { LoadCsvIntoGrid $csvPath }
            }
        })
        $timer.Start()
    })
    $form.Controls.Add($btn)
}

# === Buttons ===
CreateButton "Run Audit" 20 60 ".\Scripts\Audit.ps1" "Reports\AD_GroupAudit_Report.csv"
CreateButton "Run Extra Groups Report" 20 110 ".\Scripts\ExtraGroups.ps1" "Reports\AD_ExtraGroups_Report.csv"
CreateButton "Run Remediation" 20 160 ".\Scripts\Remediate.ps1 -DryRun:$($dryRunCheckbox.Checked)" {
    if ($dryRunCheckbox.Checked) {
        $latestDryRun = Get-ChildItem ".\Logs\AD_DryRun_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestDryRun) {
            LoadCsvIntoGrid $latestDryRun.FullName
            LogStatus "[OK] Dry run preview loaded: $($latestDryRun.Name)" "OK"
        }
    } else {
        LoadCsvIntoGrid "Reports\AD_GroupAudit_Report.csv"
    }
}
CreateButton "Compare Reports" 20 210 ".\Scripts\CompareReports.ps1" "Reports\AD_GroupAudit_Changes.csv"

# === Error Log Viewer ===
$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = "View Latest Error Log"
$logButton.Size = New-Object System.Drawing.Size(280, 40)
$logButton.Location = New-Object System.Drawing.Point(20, 260)
$logButton.Add_Click({
    $latestLog = Get-ChildItem ".\Logs\AD_ErrorLog_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        LoadCsvIntoGrid $latestLog.FullName
        LogStatus "[Log] Loaded error log: $($latestLog.Name)" "OK"
    } else {
        LogStatus "[Warning] No error logs found." "Warning"
    }
})
$form.Controls.Add($logButton)

# === Launch GUI ===
[void]$form.ShowDialog()
