$errorLog = @()

try {
    $today = Import-Csv ".\Reports\AD_GroupAudit_Report.csv"
    $yesterday = Import-Csv ".\Reports\AD_GroupAudit_Report_Yesterday.csv"

    $diff = Compare-Object -ReferenceObject $yesterday -DifferenceObject $today -Property Username, OU, MissingGroups -IncludeEqual -PassThru
    $diff | Export-Csv ".\Reports\AD_GroupAudit_Changes.csv" -NoTypeInformation
} catch {
    Log-Error -Context "CompareReports" -Target "Daily CSVs" -Details $_.Exception.Message -ErrorLog ([ref]$errorLog)
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$errorLog | Export-Csv ".\Logs\AD_ErrorLog_$timestamp.csv" -NoTypeInformation
