# Snapshot-Tool
Azure snapshot tool that allows taking a disk snapshot and reverting to it in a matter of seconds!
Snapshots are point in time disk images created in seconds, the tool then utilizes them together with Azures disk swap API to quickly and easily restore the image to any point in time a snapshot was taken at in no more than a few seconds.

# Installation
In order to install the tool in your Azure Cloud Shell please follow these instructions:
- Download the AzureVM-Snapshots.ps1 script to your local hard disk.

- Open the cloud shell:

![alt text](https://raw.githubusercontent.com/elad488/Snapshot-Tool/master/pics/Azure-Cloud-Shell-Initiate.png)

- Upload the script from you local hard disk:

![alt text](https://raw.githubusercontent.com/elad488/Snapshot-Tool/master/pics/Azure-Cloud-Shell-File-Upload.png)

- Set an alias for the script:
```
New-Alias snapshot-tool $HOME/clouddrive/AzureVM-Snapshots.ps1
```

- Thats it! when you type snapshot-tool the tool will launch in your shell and you can start working.
