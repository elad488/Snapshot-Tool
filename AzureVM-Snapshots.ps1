#Write-Host "Choose VM Subscription:"
#$subscriptions = Get-AzureRmSubscription
#$i = 0
#foreach ($subscription in $subscriptions)
#{
#    $i++
#    write-host "$i."$subscription.Name
#}
#$subscriptionChoice = Read-Host "Enter Subscription Number: "
#Select-AzureRmSubscription -SubscriptionId $subscriptions[$subscriptionChoice].Id

function install-tool ($storageName)
{
    
    $installedSA = az storage table list --account-name $storageName
    if ($installedSA -ne $null){return}
    else{
        New-AzureRmResourceGroup -Name "snapshotTool-RG" -Location "westeurope" -Force
        $storage = New-AzureRmStorageAccount -ResourceGroupName "snapshotTool-RG" -Name "$storageName" -SkuName Standard_LRS -Location 'West Europe'
        $ctx = $storage.Context

        az storage table create -n snapshots --account-name $storageName
    }
}

function takeSnapshot ($storageName, $snapshotName)
{
    
    $resourceGroup = Read-Host "Enter the RG name where the VM resides in: "
    $vmName = Read-Host "Enter the VM name to snapshot: "

    $VM = Get-AzureRmVM -name $vmName -ResourceGroupName $resourceGroup
    Start-AzureRmVM -Name $vmName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue
    $storageType = $VM.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
    $location = $vm.Location

    $snapshotConfig =  New-AzureRmSnapshotConfig -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy
    $snapshot = New-AzureRmSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $resourceGroup
    
    $diskConfig = New-AzureRmDiskConfig -SkuName $storageType -Location $location -CreateOption Copy -SourceResourceId $snapshot.Id
    $diskName = "$vmName-$snapshotName"
    $snapshotDisk = New-AzureRmDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName $diskName

    az storage entity insert --account-name $storageName -t snapshots -e PartitionKey=$snapshotName RowKey=$vmName disk_name=$diskName resource_group=$resourceGroup
}

function revertFromSnapshot ($snapshotName, $vmName, $resourceGroup, $storageName, $diskName)
{
    try
    {
         # Get the VM 
        $vm = Get-AzureRmVM -ResourceGroupName $resourceGroup -Name $vmName 
        $oldDisk = $vm.StorageProfile.OsDisk.Name

        # Make sure the VM is stopped\deallocated
        Stop-AzureRmVM -ResourceGroupName $resourceGroup -Name $VM.Name -Force

        # Get the new disk that you want to swap in
        $disk = Get-AzureRmDisk -ResourceGroupName $resourceGroup -Name $diskName

        # Set the VM configuration to point to the new disk  
        Set-AzureRmVMOSDisk -VM $vm -ManagedDiskId $disk.Id -Name $disk.Name 

        # Update the VM with the new OS disk
        Update-AzureRmVM -ResourceGroupName $resourceGroup -VM $VM 

        # Start the VM
        Start-AzureRmVM -Name $VM.Name -ResourceGroupName $resourceGroup
    }
    catch
    {
        Write-Host $Error[0]
    }
    finally
    {
        Write-Host "Deleting snapshot record..."
        Remove-AzureRmDisk -ResourceGroupName $resourceGroup -DiskName $oldDisk -Force
        Remove-AzureRmSnapshot -ResourceGroupName $resourceGroup -SnapshotName $snapshotName -Force
        az storage entity delete -t snapshots --account-name $storageName --partition-key $snapshotName --row-key $vmName
        Write-Host "Snapshot deleted."
    }
  
}


function startMenu ()
{
    $storageName = (Get-AzureRmContext).Subscription.Name
    $storageName = $storageName.Replace(" ","")
    $storageName = $storageName.Replace("'","")
    $storageName = $storageName.Replace("-","")
    $storageName = $storageName.ToLower()
    if ($storageName.Length -ge 24) {
        $trim = ($storageName.Length) - 22
        $index = ($storageName.Length) - $trim
        $storageName = $storageName.Substring(0,$index)
    }
    $storageName = $storageName + "st"
    install-tool -storageName $storageName
    Write-Host "================ Azure Snapshot Tool ================"
    Write-Host "Please choose what would you like to do:"
    Write-Host "1. Take a snapshot"
    Write-Host "2. Revert to snapshot"
    Write-Host "3. Delete a snapshot"
    Write-Host "4. List Snapshots"
    $selection = Read-Host "Please make a selection "
    switch ($selection)
    {
        '1' {
                $snapshotName = nameValidation
                takeSnapshot -storageName $storageName -snapshotName $snapshotName
            }
        '2' {
                listSnapshots -storageName $storageName
            }
        '3' {
                Write-Host -ForegroundColor Red "Function not available yet"
            }
        '4' {
                listSnapshots -storageName $storageName
            }
        #Default {Write-Host -ForegroundColor Red "Function not available yet"; return}
    }
    
}

function listSnapshots ($storageName)
{
    $table = az storage entity query -t snapshots --account-name $storageName
    $table = $table | ConvertFrom-Json
    $i = 0

    $snapshotTable = @()
    foreach ($item in $table.items)
    {
        $snapshotRow = New-Object -TypeName psobject 
        $snapshotRow | Add-Member -MemberType NoteProperty -Name snapshotName -Value $null
        $snapshotRow | Add-Member -MemberType NoteProperty -Name vmName -Value $null
        $snapshotRow | Add-Member -MemberType NoteProperty -Name diskName -Value $null
        $snapshotRow | Add-Member -MemberType NoteProperty -Name resourceGroup -Value $null
        $snapshotRow.snapshotName = $item.PartitionKey
        $snapshotRow.vmName = $item.RowKey
        $snapshotRow.diskName = $item.disk_name
        $snapshotRow.resourceGroup = $item.resource_group
        $snapshotTable += $snapshotRow
    }
    $snapshotTable  | ft
    $choice = Read-Host "Enter the snapshot name to revert to: "
    $vm = $snapshotTable | Where {$_.snapshotName -eq $choice}
    $vmName = $vm.vmName
    $resourceGroup = $vm.resourceGroup
    $diskName = $vm.diskName
    revertFromSnapshot -snapshotName $choice -vmName $vmName -resourceGroup $resourceGroup -storageName $storageName -diskName $diskName
}

function nameValidation ()
{
    $table = az storage entity query -t snapshots --account-name eladhascalsinternalconst
    $table = $table | ConvertFrom-Json
    $names = ($table.items).PartitionKey
    $flag = "true"
    $snapshotName = Read-Host "Enter a snapshot name: "
    foreach ($name in $names){
        if ($snapshotName -eq $name){
            Write-Host "The name $snapshotName already exist please try another name"
            $flag = "false"
        }
    }
    if ($flag -eq "false"){nameValidation}
    else {return $snapshotName}
}

startMenu