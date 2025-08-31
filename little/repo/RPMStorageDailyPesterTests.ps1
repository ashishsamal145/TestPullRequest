# RPMStorageDailyPesterTests.ps1

<# 
.SYNOPSIS 
This is a powershell script to be run using pester to test if all required storage container blob files are present and have been updated in the past day

.DESCRIPTION 
run a series of pester tests to determine if daily file updates have occured - the list of containers/files to be checked occurs at the end of the script

.NOTES 
┌─────────────────────────────────────────────────────────────────────────────────────────────┐ 
│ ORIGIN STORY                                                                                │ 
├─────────────────────────────────────────────────────────────────────────────────────────────┤  
|   DATE        : 2020-12-03
│   AUTHOR      : K Sheridan 
│   DESCRIPTION :  
│   UPDATES     : 2020-12-03     creation
|                 2021-01-25     added backwards compatibility switch for container locations
└─────────────────────────────────────────────────────────────────────────────────────────────┘ 

.PARAMETER StorageAccountName 
The storage account the contaienrs will be checked for

.PARAMETER StorageAccountKey 
The key to access the named storage account

.PARAMETER extraBlob 
In order to force failures for error handling tests

.PARAMETER backwardsCompatibility 
Use "Y" for pre-autotrain storage locations

.EXAMPLE 

Invoke-Pester `
-Script @{ Path =  'RPMPipeLinePesterTests.ps1'; Parameters = @{StorageAccountName = "revpredtempblobdev"; StorageAccountKey = "$StorageAccountKey"} }  `
-OutputFile "./Test-Pester.XML" `
-OutputFormat 'NUnitXML'
#>

[cmdletbinding()]
param(

[Parameter(Mandatory)]
[ValidateNotNullOrEmpty()]
[string]$StorageAccountName,


[Parameter(Mandatory)]
[ValidateNotNullOrEmpty()]
[string]$StorageAccountKey,

[Parameter()]
[string]$backwardsCompatibility,

[Parameter()]
[string]$extraContainer,

[Parameter()]
[string]$extraBlob
)

Function Get-AzBlobList {
        [cmdletbinding()]
        Param (
        $context 
        )


        $contents = Get-AzStorageContainer -context $context
        $allContents = @()
        foreach ($storageContainer in $contents) {
                $blobContents = Get-AzStorageBlob -context $context -container $storageContainer.name
                foreach ($blob in $blobContents) {
                        $allContents += [PSCustomObject] @{
                                AccountName =   $StorageAccountName
                                ContainerName = $storageContainer.name
                                BlobName =          $blob.Name             
                                BlobType =      $blob.BlobType
                                Length =        $blob.Length  
                                ContentType =   $blob.ContentType              
                                LastModified =  $blob.LastModified    
                                AccessTier =    $blob.AccessTier
                                SnapshotTime =  $blob.SnapshotTime             
                                IsDeleted =     $blob.IsDeleted
                                VersionId =     $blob.VersionId
                        }
                }
        }

        return $allContents
}

Function Check-StorageContainerPresenceWithoutActualTest {
    [cmdletbinding()]
    Param (
        $list,
        $context, 
        [string] $container,
        [string] $blob,
        [DateTime] $LastModifiedSince
    )
    
    $nameAndDateConstrainedList = $list | Where-Object { ($_.ContainerName -eq $container) -and ($_.blobName -like $blob) -and ($_.LastModified -gt $LastModifiedSince) }
    return ($nameAndDateConstrainedList.count -gt 0)
}


Function Test-StorageContainerPresence {
        [cmdletbinding()]
        Param (
        $list,
        $context, 
        [string] $container,
        [string] $blob,
        [string] $desiredColumns = 'yes',
        [DateTime] $LastModifiedSince
        )

        $nameConstrainedList = @($list  | ?{ ( $_.ContainerName -eq  "$container") -and ( $_.blobName -like  "$blob" ) } )
    $lastConstrainedEntry = $nameConstrainedList | Sort-Object LastModified -Descending | select-object -first 1

        Describe "Container $container has a blob $blob which is not empty and has been updated" {
                It "Container $container Blob $blob exists" {
                        $nameConstrainedList.Count | should BeGreaterThan 0 
                }
                
                It "Container $container Blob $blob is of length > 0" {
                        $lastConstrainedEntry.Length | should BeGreaterThan 0  
                }
                
                It "Container $container Blob $blob is not deleted" {
                        $lastConstrainedEntry.IsDeleted | should Be False  
                }
        
                if ($LastModifiedSince) {

                        $hoursSince = [math]::Round(([DateTime]::Now - $LastModifiedSince ).TotalHours)     
            
                        It "Container $container Blob $blob has been updated in the past $hoursSince hours" {
                                        $lastConstrainedEntry.LastModified | should  BeGreaterThan $LastModifiedSince  
            }
                }



        if (("$blob" -match ".csv") -and ($desiredColumns) -and ($lastConstrainedEntry)) {

                        $tmp = New-TemporaryFile

                        $testBlobContent = Get-AzStorageBlobContent -context $context -container $lastConstrainedEntry.ContainerName -blob $lastConstrainedEntry.blobName -Destination $tmp.name -force

                        $truncatedtmp = New-TemporaryFile

                        # csv files can be safely truncated, and this REALLY speeds up processing
                        # we run this twice so column names don't get trimmed for "not having contents" 
                        $content =  @(Get-Content $tmp.name -first 1)
                        $content += @(Get-Content $tmp.name -first 1)
                        $content | Set-Content $truncatedtmp.name

                        $blobcsv = import-csv $truncatedtmp.name

                        if ($blobcsv) {
                                $blobCsvColumns = ($blobcsv | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name | Select-Object -Unique | %{"`'$_`'"})
                                $BlobCsvColumnNames = [string]::Join(", ", $blobCsvColumns)
                        }

                        $lastConstrainedEntry | Add-Member -NotePropertyName CsvColumnNames -NotePropertyValue $BlobCsvColumnNames -force

                        It "Container $container blob $($lastConstrainedEntry.blobName) has column count $($blobCsvColumns.count) should be greater than 0" {
                                $($blobCsvColumns.count) | should BeGreaterThan 0  
                        }

                        It "Container $container blob $($lastConstrainedEntry.blobName) has column names: { $($blobCsvColumnNames) } should not be empty" {
                                $($blobCsvColumnNames) | should not BeNullOrEmpty  
                        }
                        
                        del $tmp.Name
                        del $truncatedtmp.name
                }

        }
    
    write-verbose "$lastConstrainedEntry"
    
        return $lastConstrainedEntry
}


[DateTime] $LastModifiedSince = [DateTime]::Now.AddDays(-1)

# set these in advance so they don't go out of scope
$context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$allContents = Get-AzBlobList -context $context

Describe "Can access storage account $StorageAccountName" {

        It "Can access storage account $StorageAccountName"  {
                $context | should not BeNullorEmpty  
                }
}

Describe  "Can read content list for storage account $StorageAccountName" {        
        
        It "Can read content list for storage account $StorageAccountName"  {
                $allContents | should not BeNullOrEmpty 
                }
        }
        
# to check on all files updated in last day, regardless of name:
#     $allContents | ?{ $_.LastModified -gt $LastModifiedSince } | %{"TestForPresence -container `"$($_.ContainerName)`" -blob `"$($_.BlobName)`""}
#

# named container files we will check
$processedStorageContainers = @()

$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "backlog" -blob "current/daily/backlog.csv"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "opps" -blob "current/daily/opportunity.csv"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "option" -blob "current/daily/optiondetail.csv"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "organization" -blob "actuals.csv"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "organization" -blob "fiscal-period/current/daily/fiscal-periods.csv"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "organization" -blob "historyowningtoplevel.csv"

$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "training" -blob "model3/current/monthly/training_data.csv"


# location of files changed when model 3,4,5 autotrain introduced

if ($backwardsCompatibility -eq "Y") {

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model2-output" -blob "Backlog_preds.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model2-output" -blob "Opportunities_preds.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model3-score-output" -blob "*/backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model3-score-output" -blob "backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model3-score-output" -blob "*/opportunities.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model3-score-output" -blob "opportunities.csv"
   
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model41-score-output" -blob "*/backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model41-score-output" -blob "*/opportunities.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model41-score-output" -blob "backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model41-score-output" -blob "opportunities.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "*/backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "*/opportunities.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "opportunities.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "*/backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "*/opportunities.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "opportunities.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model42-score-output" -blob "opportunities.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/DS.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/G&A.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/IA.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/IDG.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/India.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/SSES.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/TAC.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/actuals_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/estimates_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/estimates_lag_count.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/estimates_lag_lwa.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/forecasted_spreads.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/historical_spread_proportions.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/idx_spread_weights.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/missing_opportunities.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "business_unit/missing_opportunities_predicted_capped.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "m5_output.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/ACP.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/AS.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/CDD.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/CDO.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/COO.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/DS EVP.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/Energy.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/GH.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/Health.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/IA CAS.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/IA Fed.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/ICO.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/IRG Integration.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/ITHC.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/Int'l Ed.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/Office of the President.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/RTI India.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/SG&R.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/SSES VP Office.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/WASH.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/WRM.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/actuals_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/estimates_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/estimates_lag_count.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/estimates_lag_lwa.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/forecasted_spreads.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/historical_spread_proportions.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/idx_spread_weights.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/missing_opportunities.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model5-output" -blob "unit/missing_opportunities_predicted_capped.json"

}
else {

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model2-output" -blob "*Backlog_preds.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "model2-output" -blob "*Opportunities_preds.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model3-score-output" -blob "*/spread/score-output/backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model3-score-output" -blob "*/spread/score-output/opportunities.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model4-score-output" -blob "*/project-income/score-output/backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model4-score-output" -blob "*/project-income/score-output/opportunities.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model4-score-output" -blob "*/spread/score-output/backlog.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model4-score-output" -blob "*/spread/score-output/opportunities.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/DS.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/G&A.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/IA.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/IDG.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/India.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/SSES.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/TAC.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/actuals_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/estimates_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/estimates_lag_count.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/estimates_lag_lwa.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/forecasted_spreads.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/historical_spread_proportions.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/idx_spread_weights.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/missing_opportunities.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/business_unit/missing_opportunities_predicted_capped.json"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/m5_output.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/DS_ACP.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/DS_AS.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/DS_CDD.csv"
#   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/DS_DS EVP.csv"
#   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/DS_FP&C.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/G&A_Finance.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/G&A_GTS.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/IA_IA CAS.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/IA_IA Fed.csv"
   
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/IDG_GH.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/IDG_IDG VP Office.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/IDG_Int'l Ed.csv"
#   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/IDG_IRG Integration.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/IDG_SG&R.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/India_CDO.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/India_Energy.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/India_Health.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/India_ICO.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/India_RTI India.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/India_WASH.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/India_WRM.csv"

   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Analytics.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Communication.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Data.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Education.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Environment.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Health.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Justice.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_SSES VP Office.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_Technology.csv"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/SSES_TRUE.csv"

    
   
    
    # First, check for TAC_TAC.csv; if not found, then check for TAC_TAC VP.csv
    if (Check-StorageContainerPresenceWithoutActualTest -list $allcontents -context $context -LastModifiedSince $LastModifiedSince -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/TAC_TAC.csv") {
        $tacTacCheck = Test-StorageContainerPresence -list $allcontents -context $context -lastmodifiedsince $LastModifiedSince -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/TAC_TAC.csv"
        $processedStorageContainers += $tacTacCheck
    } else {
        $tacTacVpCheck = Test-StorageContainerPresence -list $allcontents -context $context -lastmodifiedsince $LastModifiedSince -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/TAC_TAC VP.csv"
        if ($tacTacVpCheck) {
            $processedStorageContainers += $tacTacVpCheck
        }
    }


#Add additional files below once the additional groups are added
#TAC_BM.csv
#TAC_DCS.csv
#TAC_EP.csv
#TAC_ME.csv
#TAC_SES.csv
   
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/actuals_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/estimates_lag_amount.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/estimates_lag_count.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/estimates_lag_lwa.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/forecasted_spreads.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/historical_spread_proportions.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/idx_spread_weights.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/missing_opportunities.json"
   $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince   -container "autotrain-model5-score-output" -blob "*/spread/score-output/unit/missing_opportunities_predicted_capped.json"   
}



$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (All RTI) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (DS) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (IA) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (IDG - GH) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (IDG - Int'l Ed) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (IDG) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (India) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (IDG - SG&R) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Analytics) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Communication) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Data) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Education) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Environment) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Health) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Justice) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - Technology) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES - TRUE) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (SSES) *.xlsx"
$processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "excel" -blob "*/Revenue Prediction (TAC) *.xlsx"

# also run for any {container, blob} inserted through parameters.  
# this is used for failure path testing
if (($extraBlob) -and ($extraContainer)) {
        $processedStorageContainers += Test-StorageContainerPresence -list $allcontents -context $context   -lastmodifiedsince $LastModifiedSince  -container "$extraContainer" -blob "$extraBlob"
}
# if we want to test for unknown containers showing up, we might check is allContens is same containers as $processedStorageContainers ...

# print out final details to logs of all storage containers processed
$processedStorageContainers | Sort-Object AccountName,ContainerName,BlobName | format-table -wrap AccountName,ContainerName,BlobName,BlobType,Length,LastModified,IsDeleted
