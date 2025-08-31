param(
    [string]$azureStorageAccount,
    [string]$azureSasToken,
    [string]$ociRegion,
    [string]$ociNamespace,
    [string]$ociOutBucket,
    [string]$downloadDirectory,
    [string]$uploadDirectory,
    [int]$logFrequency = 100
)

# ---------------------------
# Helper: Reset working directory
# ---------------------------
function Reset-Directory($path) {
    if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

# ---------------------------
# Setup
# ---------------------------
Import-Module Az.Storage -Force -ErrorAction Stop

Reset-Directory $downloadDirectory
Reset-Directory $uploadDirectory

$ctx     = New-AzStorageContext -StorageAccountName $azureStorageAccount -SasToken $azureSasToken
$cutoff  = [DateTime]::Now.AddDays(-1)
$counter = 0

# ---------------------------
# Process containers & blobs
# ---------------------------
$containers = Get-AzStorageContainer -Context $ctx
Write-Host "Found $($containers.Count) containers in storage account: $azureStorageAccount"

foreach ($container in $containers) {
    Write-Host "`n--- Container: $($container.Name) ---"

    # Get all blobs modified in last 1 day
    $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx |
             Where-Object { $_.LastModified -gt $cutoff }

    Write-Host "  -> Eligible blobs: $($blobs.Count)"

    foreach ($blob in $blobs) {
        $counter++
        $fileName     = $blob.Name
        $downloadPath = Join-Path $downloadDirectory $fileName
        $uploadPath   = Join-Path $uploadDirectory $fileName

        Write-Host "[$counter] Processing blob: $fileName"

        # Reset dirs each iteration
        Reset-Directory $downloadDirectory
        Reset-Directory $uploadDirectory

        # Ensure parent dirs exist
        New-Item -ItemType Directory -Force -Path (Split-Path $downloadPath) | Out-Null
        New-Item -ItemType Directory -Force -Path (Split-Path $uploadPath)   | Out-Null

        # Download from Azure
        Get-AzStorageBlobContent -Container $container.Name -Blob $fileName -Destination $downloadPath -Context $ctx -Force | Out-Null

        # Copy into upload dir
        Copy-Item $downloadPath $uploadPath -Force

        # Upload to OCI
        oci os object put `
          --region $ociRegion `
          --namespace $ociNamespace `
          --bucket-name $ociOutBucket `
          --file $uploadPath `
          --name $fileName `
          --force | Out-Null

        if ($counter % $logFrequency -eq 0) {
            Write-Host "Processed $counter files so far..."
        }
    }
}

Write-Host "`n✅ Transfer completed. Total blobs processed: $counter"
