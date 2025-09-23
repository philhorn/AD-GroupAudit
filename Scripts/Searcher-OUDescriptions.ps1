# Set the search filter to search for Organizational Units (OUs)
$searcher = New-Object DirectoryServices.DirectorySearcher([ADSI]"LDAP://OU=Groups,DC=unionky,DC=edu")

# Specify properties you want to retrieve
$searcher.PropertiesToLoad.Add("Description")
$searcher.PropertiesToLoad.Add("Name")  # Explicitly load the Name attribute

# Execute the search
$results = $searcher.FindAll()

# Loop through the results and display Description values
foreach ($result in $results) {
    $ouName = $result.Properties["Name"]
    $descriptions = $result.Properties["Description"]
    
    foreach ($desc in $descriptions) {
        [PSCustomObject]@{
            OUName      = $ouName
            Description = $desc
        }
    }
}
