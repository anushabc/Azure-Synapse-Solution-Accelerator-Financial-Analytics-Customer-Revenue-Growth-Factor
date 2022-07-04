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

#install sql server cmdlets
Write-Host "Installing SQL Module." -ForegroundColor Green -Verbose
Install-Module -Name SqlServer

#install cosmosdb
Write-Host "Installing CosmosDB Module." -ForegroundColor Green -Verbose
Install-Module -Name Az.CosmosDB -AllowClobber
Import-Module Az.CosmosDB

(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\1 - Clean Data.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name ='source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb") | ForEach-Object {$_ -Replace "full_dataset = ''", "full_dataset = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\2 - Data Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\3 - Feature Engineering.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb") | ForEach-Object {$_ -Replace "data_lake_account_name = ''", "data_lake_account_name = '$storagedatalake'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb"
(Get-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb") | ForEach-Object {$_ -Replace "file_system_name = ''", "file_system_name = 'source'"} | Set-Content -Path "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\day-03\lab-06-machine-learning\4 - ML Model Building.ipynb"


Write-Information "Using $resourceGroupName";

$uniqueId = (Get-AzResourceGroup -Name $resourceGroupName).Tags["DeploymentId"]
$resourceGroupLocation = (Get-AzResourceGroup -Name $resourceGroupName).Location
$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id
$global:logindomain = (Get-AzContext).Tenant.Id;

$synapseWorkspace = Get-AzSynapseWorkspace -ResourceGroupName $resourceGroupName
$workspaceName =$synapseWorkspace.Name

$integrationRuntimeName = "AzureIntegrationRuntime01"
$sparkPoolName1 = "Spark1"
$global:sqlEndpoint = "$($workspaceName).sql.azuresynapse.net"
$global:sqlUser = "asa.sql.admin"

$global:synapseToken = ""
$global:synapseSQLToken = ""
$global:managementToken = ""
$global:powerbiToken = "";

$global:tokenTimes = [ordered]@{
        Synapse = (Get-Date -Year 1)
        SynapseSQL = (Get-Date -Year 1)
        Management = (Get-Date -Year 1)
        PowerBI = (Get-Date -Year 1)
}

$notebooks = [ordered]@{
       "1 - Clean Data.ipynb" = "$artifactsPath\day-03\lab-06-machine-learning" 
       "2 - Data Engineering.ipynb" = "$artifactsPath\day-03\lab-06-machine-learning"
       "3 - Feature Engineering.ipynb" = "$artifactsPath\day-03\lab-06-machine-learning"
       "4 - ML Model Building" = "$artifactsPath\day-03\lab-06-machine-learning"
}

$notebookSparkPools = [ordered]@{
       "1 - Clean Data.ipynb" = $sparkPoolName1
       "2 - Data Engineering.ipynb" = $sparkPoolName1
       "3 - Feature Engineering.ipynb" = $sparkPoolName1
       "4 - ML Model Building" = $sparkPoolName1
}

$storageAccounts = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Storage/storageAccounts"
$asadatalakename = $storageAccounts | Where-Object { $_.Name -Notlike 'ml*' }
$storagedatalake =$asadatalakename.Name

$cellParams = [ordered]@{
        "#data_lake_account_name#" = $storagedatalake
        "#file_system_name" = "source"
        "#full_dataset" = "source"
}

foreach ($notebookName in $notebooks.Keys) {

        $notebookFileName = "$($notebooks[$notebookName])\$($notebookName).ipynb"
        Write-Information "Creating notebook $($notebookName) from $($notebookFileName)"
        $result = Create-SparkNotebook -TemplatesPath $templatesPath -SubscriptionId $SubscriptionId -ResourceGroupName $resourceGroupName `
                -WorkspaceName $workspaceName -SparkPoolName $notebookSparkPools[$notebookName] -Name $notebookName -NotebookFileName $notebookFileName -CellParams $cellParams -PersistPayload $false
        Write-Information "Create notebook initiated..."
        $operationResult = Wait-ForSparkNotebookOperation -WorkspaceName $workspaceName -OperationId $result.operationId
        $operationResult
}

Write-Information "Create pipeline to load the SQL pool"

$loadingPipelineName = "Pipeline 1"
$fileName = "pipeline1"

Write-Information "Creating pipeline $($loadingPipelineName)"

$result = Create-Pipeline -PipelinesPath $pipelinesPath -WorkspaceName $workspaceName -Name $loadingPipelineName -FileName $fileName 
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Running pipeline $($loadingPipelineName)"

$result = Run-Pipeline -WorkspaceName $workspaceName -Name $loadingPipelineName
$result = Wait-ForPipelineRun -WorkspaceName $workspaceName -RunId $result.runId
$result

Write-Information "Create pipeline to Set Up Batch Scoring"

$PipelineName = "Daily Orchestration"

Write-Information "Creating pipeline $($PipelineName)"

$result = Create-Pipeline -PipelinesPath $pipelinesPath -WorkspaceName $workspaceName -Name $PipelineName -FileName $PipelineName 
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Running pipeline $($PipelineName)"

$result = Run-Pipeline -WorkspaceName $workspaceName -Name $PipelineName
$result = Wait-ForPipelineRun -WorkspaceName $workspaceName -RunId $result.runId
$result

Set-AzSynapseTrigger -WorkspaceName $workspaceName -Name "MyTrigger" -DefinitionFile "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\environment-setup\pipelines\MyTrigger.json"
Get-AzSynapseTrigger -WorkspaceName $workspaceName -Name "MyTrigger"
Start-AzSynapseTrigger -WorkspaceName $workspaceName -Name "MyTrigger"

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
