.C:\LabFiles\AzureCreds.ps1

$userName = $AzureUserName
$password = $AzurePassword
$SubscriptionId = $AzureSubscriptionID

$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $userName, $SecurePassword

Connect-AzAccount -Credential $cred | Out-Null

$resourceGroupName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "*ManyModels*" }).ResourceGroupName

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
