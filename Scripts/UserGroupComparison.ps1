# Load cache.json
$cachePath = "$PSScriptRoot\..\Cache"
$cacheFile = "$cachePath\AD_Cache.json"
$cacheObj = Get-Content $cacheFile | ConvertFrom-Json

# Create OU lookup
$ouLookup = @{}
foreach ($ou in $cacheObj.OUs) {
    $ouLookup[$ou.DistinguishedName] = $ou
}

# Function to get inherited descriptions from OU hierarchy
function Get-InheritedDescriptions {
    param ($dn)

    $descriptions = @()
    while ($dn -match "^OU=([^,]+),(.+)$") {
        if ($ouLookup.ContainsKey($dn)) {
            $desc = $ouLookup[$dn].Description
            if ($desc -and $desc.Count -gt 0) {
                $descriptions += $desc
            }
        }
        $dn = $matches[2]
    }
    return $descriptions | Select-Object -Unique
}

# Build user report
$userReport = @()
foreach ($user in $cacheObj.Users) {
    $userDN = $user.DistinguishedName
    $ouPath = $user.OU

    # Get expected groups from OU hierarchy
    $expectedGroups = Get-InheritedDescriptions $ouPath
    $expectedGroupsClean = $expectedGroups | Where-Object { $_ -ne $null } | Sort-Object -Unique

    # Extract CN from MemberOf entries
    $currentGroupsCN = $user.MemberOf | ForEach-Object {
        ($_ -split ",")[0] -replace "^CN=", ""
    } | Where-Object { $_ -ne $null } | Sort-Object -Unique

    # Compare
    $missingGroups = $expectedGroupsClean | Where-Object { $currentGroupsCN -notcontains $_ }
    $extraGroups = $currentGroupsCN | Where-Object { $expectedGroupsClean -notcontains $_ }

    # Build report entry
    $userReport += [PSCustomObject]@{
        DisplayName     = ($user.DistinguishedName -split ",")[0] -replace "^CN=", ""
        SamAccountName  = $user.SamAccountName
        UserDN          = $user.DistinguishedName
        OUPath          = $user.OU
        ExpectedGroups  = $expectedGroupsClean -join "; "
        CurrentGroups   = $currentGroupsCN -join "; "
        MissingGroups   = $missingGroups -join "; "
        ExtraGroups     = $extraGroups -join "; "
    }
}

# Output to CSV
$reportPath = "$PSScriptRoot\..\Reports\UserGroupComparison.csv"
$userReport | Export-Csv $reportPath -NoTypeInformation
Write-Host "Report generated at: $reportPath"

# Generate remediation script
$remediationScriptPath = "$PSScriptRoot\..\Reports\RemediateUserGroups.ps1"
$logPath = "$PSScriptRoot\..\Reports\Remediation_Log.txt"

$remediationScript = @"
# Remediation Script: Add users to missing groups
# Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# NOTE: This script runs in Dry Run mode by default.
#       Use -Force to apply changes.

param (
    [switch] \$Force
)

Import-Module ActiveDirectory

\$logFile = '$logPath'
Add-Content -Path \$logFile -Value "Remediation started: $(Get-Date)"

\$totalUsers = 0
\$totalGroups = 0
\$successCount = 0
\$failureCount = 0

"@

foreach ($user in $userReport) {
    if ($user.MissingGroups -ne "") {
        $missingGroupList = $user.MissingGroups -split "; "
        $remediationScript += "`n# Processing user: $($user.SamAccountName)`n"
        $remediationScript += "`$totalUsers++`n"
        foreach ($group in $missingGroupList) {
            $remediationScript += @"
# Add $($user.SamAccountName) to '$group'
\$totalGroups++
if (-not \$Force) {
    Write-Host "[DryRun] Would add $($user.SamAccountName) to '$group'"
    Add-Content -Path \$logFile -Value "[DryRun] Would add $($user.SamAccountName) to '$group'"
} else {
    try {
        Add-ADGroupMember -Identity '$group' -Members '$($user.SamAccountName)' -ErrorAction Stop
        Write-Host "Added $($user.SamAccountName) to '$group'"
        Add-Content -Path \$logFile -Value "Added $($user.SamAccountName) to '$group'"
        \$successCount++
    } catch {
        Write-Warning "Failed to add $($user.SamAccountName) to '$group': \$($_.Exception.Message)"
        Add-Content -Path \$logFile -Value "ERROR: Failed to add $($user.SamAccountName) to '$group': \$($_.Exception.Message)"
        \$failureCount++
    }
}
"@
        }
    }
}

$remediationScript += @"

Add-Content -Path \$logFile -Value "Remediation completed: $(Get-Date)"
Add-Content -Path \$logFile -Value "Summary:"
Add-Content -Path \$logFile -Value "  Total users processed: \$totalUsers"
Add-Content -Path \$logFile -Value "  Total group additions attempted: \$totalGroups"
Add-Content -Path \$logFile -Value "  Successful additions: \$successCount"
Add-Content -Path \$logFile -Value "  Failed additions: \$failureCount"
"@

# Save the remediation script
$remediationScript | Out-File $remediationScriptPath -Encoding UTF8
Write-Host "Remediation script generated at: $remediationScriptPath"
