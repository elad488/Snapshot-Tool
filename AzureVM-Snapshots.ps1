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

function install-tool ()
{
    $installedSA = az storage table list --account-name snapshottoolsa
    if ($installedSA){return}
    else{
        New-AzureRmResourceGroup -Name "snapshotTool-RG" -Location "westeurope"
        $storage = New-AzureRmStorageAccount -ResourceGroupName "snapshotTool-RG" -Name "snapshottoolsa" -SkuName Standard_LRS -Location 'West Europe'
        $ctx = $storage.Context

        az storage table create -n snapshots --account-name snapshottoolsa
    }
}

function takeSnapshot ()
{
    
    $resourceGroup = Read-Host "Enter the RG name where the VM resides in: "
    $vmName = Read-Host "Enter the VM name to snapshot: "
    $snapshotName = Read-Host "Enter a snapshot name: "


    $VM = Get-AzureRmVM -name $vmName -ResourceGroupName $resourceGroup
    $storageType = $VM.StorageProfile.OsDisk.ManagedDisk.StorageAccountType
    $location = $vm.Location

    $snapshotConfig =  New-AzureRmSnapshotConfig -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy
    $snapshotName = "$vmName-snapshot"
    $snapshot = New-AzureRmSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $resourceGroup
    
    $diskConfig = New-AzureRmDiskConfig -AccountType $storageType -Location $location -CreateOption Copy -SourceResourceId $snapshot.Id
    $diskName = "$vmName-snapshotdisk"
    $snapshotDisk = New-AzureRmDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName $diskName

    az storage entity insert --account-name snapshottoolsa -t snapshots -e PartitionKey=$snapshotName RowKey=$vmName disk_name=$diskName
}

function revertFromSnapshot ($snapshotName)
{
    # Get the VM 
    $vm = Get-AzureRmVM -ResourceGroupName $resourceGroup -Name $vmName 

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


function startMenu ()
{
    install-tool
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
                takeSnapshot
            }
        '2' {
                listSnapshots
            }
        '3' {
                Write-Host -ForegroundColor Red "Function not available yet"
            }
        '4' {
                Write-Host -ForegroundColor Red "Function not available yet"
            }
        #Default {Write-Host -ForegroundColor Red "Function not available yet"; return}
    }
    
}

function listSnapshots ()
{
    $table = az storage entity query -t snapshots --account-name snapshottoolsa
    $table = $table | ConvertFrom-Json
    $i = 0

    $snapshotTable = @()
    foreach ($item in $table.items)
    {
        $snapshotRow = New-Object -TypeName psobject 
        $snapshotRow | Add-Member -MemberType NoteProperty -Name snapshotName -Value $null
        $snapshotRow | Add-Member -MemberType NoteProperty -Name vmName -Value $null
        $snapshotRow | Add-Member -MemberType NoteProperty -Name diskName -Value $null
        $snapshotRow.snapshotName = $item.PartitionKey
        $snapshotRow.vmName = $item.RowKey
        $snapshotRow.diskName = $item.disk_name
        $snapshotTable += $snapshotRow
    }
    $snapshotTable  | ft
    $choice = Read-Host "Enter the snapshot name to revert to: "
    revertFromSnapshot($choice)
}

startMenu




