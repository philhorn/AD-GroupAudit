Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Ensure Directories Exist ===
$reportsDir = "$PSScriptRoot\Reports"
$logsDir    = "$PSScriptRoot\Logs"
$cacheDir   = "$PSScriptRoot\Cache"
foreach ($dir in @($reportsDir, $logsDir, $cacheDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
}

# === Load Config ===
$configPath = "$PSScriptRoot\config.json"
$Global:CacheTimeoutHours = 3
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath | ConvertFrom-Json
        if ($config.CacheTimeoutHours) { $Global:CacheTimeoutHours = $config.CacheTimeoutHours }
    } catch {}
}

# === Load Cache Timestamp ===
$cacheFile = "$cacheDir\AD_Cache.json"
$Global:CacheTimestamp = $null
if (Test-Path $cacheFile) {
    try {
        $cacheObj = Get-Content $cacheFile | ConvertFrom-Json
        $Global:CacheTimestamp = [datetime]$cacheObj.Timestamp
    } catch {}
}

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

# === Status Console ===
$statusBox = New-Object System.Windows.Forms.RichTextBox
$statusBox.Size = New-Object System.Drawing.Size(900, 100)
$statusBox.Location = New-Object System.Drawing.Point(20, 450)
$statusBox.ReadOnly = $true
$form.Controls.Add($statusBox)

function LogStatus {
    param([string]$Message)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $statusBox.SelectionStart = $statusBox.TextLength
    $statusBox.SelectionColor = [System.Drawing.Color]::Black
    $statusBox.AppendText("[$timestamp] $Message`r`n")
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
        LogStatus "[Warning] CSV not found: $path"
    }
}

# === Cache Age Label ===
$cacheAgeLabel = New-Object System.Windows.Forms.Label
$cacheAgeLabel.Text = "Cache Age: Unknown"
$cacheAgeLabel.Location = New-Object System.Drawing.Point(320, 430)
$cacheAgeLabel.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($cacheAgeLabel)

function UpdateCacheAgeLabel {
    if ($Global:CacheTimestamp) {
        $ageMinutes = [math]::Round(((Get-Date) - $Global:CacheTimestamp).TotalMinutes / 5) * 5
        $cacheAgeLabel.Text = "Cache Age: $ageMinutes minutes"
    } else {
        $cacheAgeLabel.Text = "Cache Age: Unknown"
    }
}

# === Editable Timeout Field ===
$timeoutLabel = New-Object System.Windows.Forms.Label
$timeoutLabel.Text = "Cache Timeout (hrs):"
$timeoutLabel.Location = New-Object System.Drawing.Point(650, 430)
$timeoutLabel.Size = New-Object System.Drawing.Size(130, 20)
$form.Controls.Add($timeoutLabel)

$timeoutBox = New-Object System.Windows.Forms.TextBox
$timeoutBox.Text = "$Global:CacheTimeoutHours"
$timeoutBox.Location = New-Object System.Drawing.Point(780, 428)
$timeoutBox.Size = New-Object System.Drawing.Size(40, 20)
$form.Controls.Add($timeoutBox)

$timeoutBox.Add_TextChanged({
    $newVal = $timeoutBox.Text
    if ($newVal -match '^\d+(\.\d+)?$') {
        $Global:CacheTimeoutHours = [double]$newVal
        $config = @{ CacheTimeoutHours = $Global:CacheTimeoutHours }
        $config | ConvertTo-Json | Set-Content $configPath
        LogStatus "[OK] Cache timeout updated to $newVal hours."
        UpdateCacheAgeLabel
    } else {
        LogStatus "[Warning] Invalid timeout value: $newVal"
    }
})

# === Button Factory ===
function CreateButton($text, $x, $y, $scriptPath, $csvPath, $isRemediation = $false) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Size = New-Object System.Drawing.Size(280, 40)
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    $btn.Tag = $scriptPath
    $btn.Add_Click({
        $dryRunFlag = $dryRunCheckbox.Checked
        $script:ActiveJob = Start-Job -ScriptBlock {
            param($path, $dryRun)
            if (Test-Path $path) {
                & $path -DryRun:$dryRun -FromGUI
            }
        } -ArgumentList $this.Tag, $dryRunFlag

        $script:ActiveTimer = New-Object System.Windows.Forms.Timer
        $script:ActiveTimer.Interval = 1000
        $script:ActiveTimer.Add_Tick({
            if ($script:ActiveJob -and $script:ActiveJob.State -ne 'Running') {
                $script:ActiveTimer.Stop()
                if ($script:ActiveJob -and (Get-Job -Id $script:ActiveJob.Id -ErrorAction SilentlyContinue)) {
                    Receive-Job $script:ActiveJob | Out-Null
                    Remove-Job $script:ActiveJob -Force -ErrorAction SilentlyContinue
                }
                LogStatus "[OK] $text complete."
                if ($csvPath) { LoadCsvIntoGrid $csvPath }
                UpdateCacheAgeLabel
            }
        })
        $script:ActiveTimer.Start()
    })
    $form.Controls.Add($btn)
    return $btn
}

# === Script Paths ===
$auditScriptPath       = Join-Path $PSScriptRoot "Scripts\Audit.ps1"
$extraGroupsScriptPath = Join-Path $PSScriptRoot "Scripts\ExtraGroups.ps1"
$remediateScriptPath   = Join-Path $PSScriptRoot "Scripts\Remediate.ps1"
$compareScriptPath     = Join-Path $PSScriptRoot "Scripts\CompareReports.ps1"

# === Buttons ===
$runAuditBtn        = CreateButton "Run Audit" 20 60 $auditScriptPath "$reportsDir\AD_GroupAudit_Report.csv"
$extraGroupsBtn     = CreateButton "Run Extra Groups Report" 20 110 $extraGroupsScriptPath "$reportsDir\AD_ExtraGroups_Report.csv"
$remediationBtn     = CreateButton "Run Remediation" 20 160 $remediateScriptPath "$reportsDir\AD_GroupAudit_Report.csv" $true
$compareReportsBtn  = CreateButton "Compare Reports" 20 210 $compareScriptPath "$reportsDir\AD_GroupAudit_Changes.csv"

# === Refresh AD Cache Button ===
$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh AD Data"
$refreshButton.Size = New-Object System.Drawing.Size(280, 40)
$refreshButton.Location = New-Object System.Drawing.Point(20, 260)
$refreshButton.Add_Click({
    LogStatus "[Info] Refreshing AD cache..."
    try {
        . "$PSScriptRoot\Scripts\Cache.ps1"
        $cacheObj = Get-Content $cacheFile | ConvertFrom-Json
        $Global:CacheTimestamp = [datetime]$cacheObj.Timestamp
        $runAuditBtn.Enabled        = $true
        $extraGroupsBtn.Enabled     = $true
        $remediationBtn.Enabled     = $true
        $compareReportsBtn.Enabled  = $true
        UpdateCacheAgeLabel
        LogStatus "[OK] AD cache is refreshed and up to date."
    } catch {
        LogStatus "[Error] Cache refresh failed: $($_.Exception.Message)"
    }
})
$form.Controls.Add($refreshButton)

# === Exit Button ===
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Size = New-Object System.Drawing.Size(280, 40)
$exitButton.Location = New-Object System.Drawing.Point(20, 320)
$exitButton.Add_Click({ $form.Close() })
$form.Controls.Add($exitButton)

# === Timer to Auto-Update Cache Age Label ===
$ageTimer = New-Object System.Windows.Forms.Timer
$ageTimer.Interval = 600000
$ageTimer.Add_Tick({ UpdateCacheAgeLabel })
$ageTimer.Start()

# === Initial Cache Age Update ===
UpdateCacheAgeLabel

# === Initial Cache Load and First-Launch Check ===
if (-not $Global:CacheTimestamp) {
    LogStatus "[Warning] No AD cache found. Please refresh before running reports."
    $runAuditBtn.Enabled        = $false
    $extraGroupsBtn.Enabled     = $false
    $remediationBtn.Enabled     = $false
    $compareReportsBtn.Enabled  = $false
} elseif (((Get-Date) - $Global:CacheTimestamp).TotalHours -gt $Global:CacheTimeoutHours) {
    LogStatus "[Warning] AD cache is older than $Global:CacheTimeoutHours hours. You may want to refresh, but you can still use the data."
    $runAuditBtn.Enabled        = $true
    $extraGroupsBtn.Enabled     = $true
    $remediationBtn.Enabled     = $true
    $compareReportsBtn.Enabled  = $true
} else {
    $runAuditBtn.Enabled        = $true
    $extraGroupsBtn.Enabled     = $true
    $remediationBtn.Enabled     = $true
    $compareReportsBtn.Enabled  = $true
}
[void]$form.ShowDialog()