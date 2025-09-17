Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === Ensure Reports and Logs Directories Exist ===
$reportsDir = "$PSScriptRoot\Reports"
$logsDir = "$PSScriptRoot\Logs"
if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
if (-not (Test-Path $logsDir))    { New-Item -ItemType Directory -Path $logsDir    | Out-Null }

# === Load Config ===
$ConfigPath = "$PSScriptRoot\config.json"
if (Test-Path $ConfigPath) {
    try {
        $Config = Get-Content $ConfigPath | ConvertFrom-Json
        $Global:CacheTimeoutHours = $Config.CacheTimeoutHours
    } catch {
        $Global:CacheTimeoutHours = 3
    }
} else {
    $Global:CacheTimeoutHours = 3
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

# === RichTextBox for Status Console ===
$statusBox = New-Object System.Windows.Forms.RichTextBox
$statusBox.Size = New-Object System.Drawing.Size(900, 100)
$statusBox.Location = New-Object System.Drawing.Point(20, 450)
$statusBox.ReadOnly = $true
$form.Controls.Add($statusBox)

function LogStatus {
    param (
        [string]$Message
    )

    # Default tag
    $tag = "Info"

    # Extract tag from message (e.g., [OK], [Error], etc.)
 if ($Message -match '^\[(\w+)\]') {
    $tag = $matches[1]
}

    # Map tag to color
    $color = switch ($tag) {
        "OK"      { "Green" }
        "Error"   { "Red" }
        "Warning" { "Orange" }
        "Debug"   { "Gray" }
        "Audit"   { "Blue" }
        default   { "Black" }
    }

    # Optional: Add timestamp
    $timestamp = Get-Date -Format "HH:mm:ss"

    $statusBox.SelectionStart = $statusBox.TextLength
    $statusBox.SelectionColor = [System.Drawing.Color]::$color
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
        LogStatus "[Warning] CSV not found: $path" "Warning"
    }
}

# === Cache Age Label ===
$cacheAgeLabel = New-Object System.Windows.Forms.Label
$cacheAgeLabel.Text = "Cache Age: Unknown"
$cacheAgeLabel.Location = New-Object System.Drawing.Point(320, 430)
$cacheAgeLabel.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($cacheAgeLabel)

# === Cache Expired Warning Label ===
$cacheExpiredLabel = New-Object System.Windows.Forms.Label
$cacheExpiredLabel.Text = ""
$cacheExpiredLabel.ForeColor = [System.Drawing.Color]::OrangeRed
$cacheExpiredLabel.Location = New-Object System.Drawing.Point(320, 455)
$cacheExpiredLabel.Size = New-Object System.Drawing.Size(300, 20)
$form.Controls.Add($cacheExpiredLabel)

# === Global Job and Timer Variables ===
$script:ActiveJob = $null
$script:ActiveTimer = $null

function UpdateCacheAgeLabel {
    if ($Global:CacheTimestamp) {
        $ageMinutes = [math]::Round(((Get-Date) - $Global:CacheTimestamp).TotalMinutes / 5) * 5
        $cacheAgeLabel.Text = "Cache Age: $ageMinutes minutes"

        if (((Get-Date) - $Global:CacheTimestamp).TotalHours -ge $Global:CacheTimeoutHours) {
            $cacheExpiredLabel.Text = "⚠️ Cache is older than timeout ($Global:CacheTimeoutHours hrs)"
        } else {
            $cacheExpiredLabel.Text = ""
        }
    } else {
        $cacheAgeLabel.Text = "Cache Age: Unknown"
        $cacheExpiredLabel.Text = ""
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
        $config | ConvertTo-Json | Set-Content "$PSScriptRoot\config.json"
        LogStatus "[OK] Cache timeout updated to $newVal hours." "OK"
        UpdateCacheAgeLabel
    } else {
        LogStatus "[Warning] Invalid timeout value: $newVal" "Warning"
    }
})

# === Button Factory ===
function CreateButton($text, $x, $y, $fullScriptPath, $csvPath, $isRemediation = $false) {
    if (-not $fullScriptPath -or $fullScriptPath -eq "") {
        LogStatus "[Error] No script path provided for '$text' button." "Error"
        Write-Host "[DEBUG] No script path provided for '$text' button."
        return $null
    }
    LogStatus "[Debug] Full script path resolved: $fullScriptPath" "Debug"
    Write-Host "[DEBUG] Creating button '$text' with script path: $fullScriptPath"

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $text
    $btn.Size = New-Object System.Drawing.Size(280, 40)
    $btn.Location = New-Object System.Drawing.Point($x, $y)
    # Store the path as a property on the button
    $btn.Tag = $fullScriptPath

    $btn.Add_Click({
        $thisBtn = $this
        $scriptPath = $thisBtn.Tag
        LogStatus "[Running] $text started..."
        $dryRunFlag = $dryRunCheckbox.Checked

        $script:ActiveJob = Start-Job -ScriptBlock {
            param($path, $dryRun)
            Write-Host "DEBUG: Job received path: '$path'"
            if (Test-Path $path) {
                & $path -DryRun:$dryRun -FromGUI
            } else {
                Write-Host "[Error] Script not found: $path"
            }
        } -ArgumentList $scriptPath, $dryRunFlag

        if (-not $script:ActiveJob) {
            LogStatus "[Error] Failed to start background job for $text." "Error"
            return
        }

        $script:ActiveTimer = New-Object System.Windows.Forms.Timer
        $script:ActiveTimer.Interval = 1000
        $script:ActiveTimer.Add_Tick({
            try {
                if ($script:ActiveJob -and $script:ActiveJob.State -ne 'Running') {
                    $script:ActiveTimer.Stop()
                    if ($script:ActiveJob -and (Get-Job -Id $script:ActiveJob.Id -ErrorAction SilentlyContinue)) {
                        Receive-Job $script:ActiveJob | Out-Null
                        Remove-Job $script:ActiveJob -Force -ErrorAction SilentlyContinue
                    }
                    LogStatus "[OK] $text complete." "OK"

                    if ($isRemediation -and $dryRunFlag) {
                        $latestDryRun = Get-ChildItem "$logsDir\AD_DryRun_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($latestDryRun) {
                            LoadCsvIntoGrid $latestDryRun.FullName
                            LogStatus "[OK] Dry run preview loaded: $($latestDryRun.Name)" "OK"
                        }
                    } elseif ($csvPath) {
                        LoadCsvIntoGrid $csvPath
                    }
                    UpdateCacheAgeLabel
                }
            } catch {
                LogStatus "[Error] Timer tick failed: $($_.Exception.Message)" "Error"
            }
        })
        $script:ActiveTimer.Start()
    })
    $form.Controls.Add($btn)
    return $btn
}

# === Load Cache and Check Freshness ===

if (-not $Global:CacheTimestamp -or ((Get-Date) - $Global:CacheTimestamp).TotalHours -gt $Global:CacheTimeoutHours) {
    $cacheAgeLabel.Text = "Cache Age: Unknown or Expired"
    LogStatus "[Warning] No valid AD cache found. Please refresh before running reports." "Warning"

    # Disable all action buttons
    $form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] } | ForEach-Object {
        $_.Enabled = $false
    }

    # Enable only the Refresh Cache button (we’ll tag it next)
    $refreshButton.Enabled = $true
}

# === Buttons ===
#$runAuditBtn        = CreateButton "Run Audit" 20 60 "$PSScriptRoot Scripts\Audit.ps1" "$reportsDir\AD_GroupAudit_Report.csv"
#$extraGroupsBtn     = CreateButton "Run Extra Groups Report" 20 110 "$PSScriptRoot\Scripts\ExtraGroups.ps1" "$reportsDir\AD_ExtraGroups_Report.csv"
#$remediationBtn     = CreateButton "Run Remediation" 20 160 "$PSScriptRoot\Scripts\Remediate.ps1" "$reportsDir\AD_GroupAudit_Report.csv" $true
#$compareReportsBtn  = CreateButton "Compare Reports" 20 210 "$PSScriptRoot\Scripts\CompareReports.ps1" "$reportsDir\AD_GroupAudit_Changes.csv"

# Disable action buttons if cache is expired or missing
$cacheIsFresh = $Global:CacheTimestamp -and ((Get-Date) - $Global:CacheTimestamp).TotalHours -le $Global:CacheTimeoutHours
$runAuditBtn.Enabled        = $cacheIsFresh
$extraGroupsBtn.Enabled     = $cacheIsFresh
$remediationBtn.Enabled     = $cacheIsFresh
$compareReportsBtn.Enabled  = $cacheIsFresh

#######################################
$auditScriptPath       = Join-Path $PSScriptRoot "Scripts\Audit.ps1"
$extraGroupsScriptPath = Join-Path $PSScriptRoot "Scripts\ExtraGroups.ps1"
$remediateScriptPath   = Join-Path $PSScriptRoot "Scripts\Remediate.ps1"
$compareScriptPath     = Join-Path $PSScriptRoot "Scripts\CompareReports.ps1"

Write-Host "Audit script path: $auditScriptPath"
Write-Host "ExtraGroups script path: $extraGroupsScriptPath"
Write-Host "Remediate script path: $remediateScriptPath"
Write-Host "Compare script path: $compareScriptPath"

$runAuditBtn        = CreateButton "Run Audit" 20 60 $auditScriptPath "$reportsDir\AD_GroupAudit_Report.csv"
$extraGroupsBtn     = CreateButton "Run Extra Groups Report" 20 110 $extraGroupsScriptPath "$reportsDir\AD_ExtraGroups_Report.csv"
$remediationBtn     = CreateButton "Run Remediation" 20 160 $remediateScriptPath "$reportsDir\AD_GroupAudit_Report.csv" $true
$compareReportsBtn  = CreateButton "Compare Reports" 20 210 $compareScriptPath "$reportsDir\AD_GroupAudit_Changes.csv"############################################


# === Error Log Viewer ===
$logButton = New-Object System.Windows.Forms.Button
$logButton.Text = "View Latest Error Log"
$logButton.Size = New-Object System.Drawing.Size(280, 40)
$logButton.Location = New-Object System.Drawing.Point(20, 260)
$logButton.Add_Click({
    $latestLog = Get-ChildItem "$logsDir\AD_ErrorLog_*.csv" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestLog) {
        LoadCsvIntoGrid $latestLog.FullName
        LogStatus "[Log] Loaded error log: $($latestLog.Name)" "OK"
    } else {
        LogStatus "[Warning] No error logs found." "Warning"
    }
})
$form.Controls.Add($logButton)

# === Refresh AD Cache Button ===
$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh AD Data"
$refreshButton.Size = New-Object System.Drawing.Size(280, 40)
$refreshButton.Location = New-Object System.Drawing.Point(20, 310)
$refreshButton.Add_Click({
    LogStatus "[Info] Refreshing AD cache..." "Info"

    try {
        . "$PSScriptRoot\Scripts\Cache.ps1"
        UpdateCacheAgeLabel
        LogStatus "[OK] AD cache is refreshed and up to date."

        $form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] } | ForEach-Object {
            $_.Enabled = $true
        }
    } catch {
        LogStatus "[Error] Cache refresh failed: $($_.Exception.Message)" "Error"
        $statusLabel.Text = "Refresh failed."
        $statusLabel.ForeColor = [System.Drawing.Color]::Red
    }
})
$form.Controls.Add($refreshButton)

$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Size = New-Object System.Drawing.Size(280, 40)
$exitButton.Location = New-Object System.Drawing.Point(20, 400)
$exitButton.Add_Click({
    if ($script:ActiveTimer) { $script:ActiveTimer.Stop() }
    if ($script:ActiveJob) {
        try {
            Receive-Job $script:ActiveJob | Out-Null
            Remove-Job $script:ActiveJob
        } catch {}
    }
    $form.Close()
})
$form.Controls.Add($exitButton)

# === Timer to Auto-Update Cache Age Label Every 10 Minutes ===
$ageTimer = New-Object System.Windows.Forms.Timer
$ageTimer.Interval = 600000
$ageTimer.Add_Tick({ UpdateCacheAgeLabel })
$ageTimer.Start()

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Size = New-Object System.Drawing.Size(280, 20)
$statusLabel.Location = New-Object System.Drawing.Point(20, 340)
$form.Controls.Add($statusLabel)

# === Initial Cache Age Update ===
UpdateCacheAgeLabel

# === Initial Cache Load and First-Launch Check ===
if (-not $Global:CacheTimestamp -or ((Get-Date) - $Global:CacheTimestamp).TotalHours -gt $Global:CacheTimeoutHours) {
    $statusLabel.Text = "Initializing AD cache..."
    $statusLabel.ForeColor = [System.Drawing.Color]::Orange

    LogStatus "[Info] No valid AD cache found. Refreshing now... Cache.ps1 invoked at $(Get-Date -Format 'HH:mm:ss')" "Info"

    . "$PSScriptRoot\Scripts\Cache.ps1"
    UpdateCacheAgeLabel
    LogStatus "[OK] AD cache refreshed on first launch."

    $statusLabel.Text = "AD cache is up to date."
    $statusLabel.ForeColor = [System.Drawing.Color]::Green
}

# === Launch GUI ===
[void]$form.ShowDialog()