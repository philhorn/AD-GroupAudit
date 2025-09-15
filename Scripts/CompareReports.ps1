# CompareReports.ps1
. "$PSScriptRoot\Common.ps1"

$today = Get-Date -Format "yyyyMMdd"
$files = Get-ChildItem ".\Reports\AD_GroupAudit_Report*.csv" | Sort-Object LastWriteTime -Descending

if ($files.Count -lt 2) {
    Log-Error -Context "CompareReports" -Target "Daily CSVs" -Details "Not enough reports to compare"
    return
}

$latest = Import-Csv $files[0].FullName
$previous = Import-Csv $files[1].FullName

$changes = Compare-Object $previous $latest -Property User, MissingGroups -PassThru

$changes | Export-Csv -Path ".\Reports\AD_GroupAudit_Changes.csv" -NoTypeInformation
