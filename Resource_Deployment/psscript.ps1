Param (
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,

    [string]
    $AzurePassword,

    [string]
    $AzureTenantID,

    [string]
    $AzureSubscriptionID,

    [string]
    $ODLID,
    
    [string]
    $DeploymentID,

    [string]
    $InstallCloudLabsShadow,
    
    [string]
    $vmAdminUsername,

    [string]
    $trainerUserName,

    [string]
    $trainerUserPassword
)

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 

#Import Common Functions
$path = pwd
$path=$path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

# Run Imported functions from cloudlabs-windows-functions.ps1
WindowsServerCommon
#InstallCloudLabsShadow $ODLID $InstallCloudLabsShadow
CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID $ODLID
InstallAzPowerShellModule
InstallModernVmValidator
InstallPowerBIDesktop

Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SpektraSystems/CloudLabs-Azure/master/azure-synapse-analytics-workshop-400/artifacts/setup/azcopy.exe" -OutFile "C:\LabFiles\azcopy.exe"

Add-Content -Path "C:\LabFiles\AzureCreds.txt" -Value "ODLID= $ODLID" -PassThru

$LabFilesDirectory = "C:\LabFiles"

.C:\LabFiles\AzureCreds.ps1

$userName = $AzureUserName
$password = $AzurePassword
$SubscriptionId = $AzureSubscriptionID

$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $userName, $SecurePassword

Connect-AzAccount -Credential $cred | Out-Null

$resourceGroupName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "*ManyModels*" }).ResourceGroupName
$deploymentId =  (Get-AzResourceGroup -Name $resourceGroupName).Tags["DeploymentId"]

# Template deployment

New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
  -TemplateUri "https://raw.githubusercontent.com/Sanket-ST/Azure-Synapse-Solution-Accelerator-Financial-Analytics-Customer-Revenue-Growth-Factor/main/Resource_Deployment/azuredeploy.json" `
  -DeploymentId $deploymentId
  
$storageAccounts = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Storage/storageAccounts"
$asadatalakename = $storageAccounts | Where-Object { $_.Name -Notlike 'ml*' }
$storagedatalake =$asadatalakename.Name
$Context = $storagedatalake.Context

$storage = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $asadatalakename.Name
$storageContext = $storage.Context

$storContainer = Get-AzStorageContainer -Name "source" -Context $storageContext
$storageContainer = $storContainer.Name
$Context = $storageContainer.Context

New-AzStorageDirectory -ShareName "raw_data" -Path $storContainer

$uploadstorage = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $asadatalakename.Name
$storcontext = $uploadstorage.Context

Get-ChildItem -File -Recurse | Set-AzStorageBlobContent -Container "source" -Context $storcontext

New-AzRoleAssignment -SignInName $userName -RoleDefinitionName "Storage Blob Data Contributor" -Scope "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storagedatalake"
$id = "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storagedatalake"

Install-Module -Name Az.Synapse -RequiredVersion 0.3.0 -Force

$workspaceName = $synapseWorkspace | Where-Object { $_.workspacename -like 'synapse-workspace*' }

$synapseWorkspace =$workspacename.Name

$synapseWorkspace = Get-AzSynapseWorkspace -ResourceGroupName $resourceGroupName
$workspaceName =$synapseWorkspace.Name

New-AzSynapseFirewallRule -WorkspaceName $workspaceName -Name NewClientIp -StartIpAddress "0.0.0.0" -EndIpAddress "255.255.255.255"

cd "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\environment-setup\automation\"
$sparkpoolName = "spark1"
Update-AzSynapseSparkPool -WorkspaceName $WorkspaceName -Name $sparkpoolName -LibraryRequirementsFilePath "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\environment-setup\automation\requirements.txt" #path

cd C:/

function InstallGit()
{
  Write-Host "Installing Git." -ForegroundColor Green -Verbose

  #download and install git...        
  $output = "$env:TEMP\git.exe";
  Invoke-WebRequest -Uri https://github.com/git-for-windows/git/releases/download/v2.27.0.windows.1/Git-2.27.0-64-bit.exe -OutFile $output; 

  $productPath = "$env:TEMP";
  $productExec = "git.exe"    
  $argList = "/SILENT"
  start-process "$productPath\$productExec" -ArgumentList $argList -wait

}

function InstallAzureCli()
{
  Write-Host "Installing Azure CLI." -ForegroundColor Green -Verbose

  #install azure cli
  Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi -usebasicparsing; 
  Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; 
  rm .\AzureCLI.msi
}

InstallGit
InstallAzureCli

function CreateCredFile($azureUsername, $azurePassword, $azureTenantID, $azureSubscriptionID, $deploymentId)
{
  $WebClient = New-Object System.Net.WebClient
  $WebClient.DownloadFile("https://raw.githubusercontent.com/solliancenet/azure-synapse-analytics-workshop-400/master/artifacts/environment-setup/spektra/AzureCreds.txt","C:\LabFiles\AzureCreds.txt")
  $WebClient.DownloadFile("https://raw.githubusercontent.com/solliancenet/azure-synapse-analytics-workshop-400/master/artifacts/environment-setup/spektra/AzureCreds.ps1","C:\LabFiles\AzureCreds.ps1")

  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "ClientIdValue", ""} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$azureUsername"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$azurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureSQLPasswordValue", "$azurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$azureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$azureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"
  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$deploymentId"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"               
  (Get-Content -Path "C:\LabFiles\AzureCreds.txt") | ForEach-Object {$_ -Replace "ODLIDValue", "$odlId"} | Set-Content -Path "C:\LabFiles\AzureCreds.txt"  
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "ClientIdValue", ""} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureUserNameValue", "$azureUsername"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzurePasswordValue", "$azurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureSQLPasswordValue", "$azurePassword"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureTenantIDValue", "$azureTenantID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "AzureSubscriptionIDValue", "$azureSubscriptionID"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "DeploymentIDValue", "$deploymentId"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  (Get-Content -Path "C:\LabFiles\AzureCreds.ps1") | ForEach-Object {$_ -Replace "ODLIDValue", "$odlId"} | Set-Content -Path "C:\LabFiles\AzureCreds.ps1"
  Copy-Item "C:\LabFiles\AzureCreds.txt" -Destination "C:\Users\Public\Desktop"
}

CreateCredFile


(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name ='source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb") | ForEach-Object {$_ -Replace "full_dataset = ''", "full_dataset = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb"

#Download power Bi desktop
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup_x64.exe","C:\LabFiles\PBIDesktop_x64.exe")

#Storage explorer
choco install microsoftazurestorageexplorer -y -force
sleep 10

#Create shorcut in desktop
$WshShell = New-Object -comObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("C:\Users\Public\Desktop\StorageExplorer.lnk")
$Shortcut.TargetPath = "C:\Program Files (x86)\Microsoft Azure Storage Explorer\StorageExplorer.exe"
$Shortcut.Save() 


Restart-Computer -Force
