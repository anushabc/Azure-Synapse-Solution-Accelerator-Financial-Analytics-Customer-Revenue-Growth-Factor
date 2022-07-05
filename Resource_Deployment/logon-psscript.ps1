cd './synapse-ws-L400/azure-synapse-analytics-workshop-400-master/artifacts/environment-setup/automation'


$InformationPreference = "Continue"

$IsCloudLabs = Test-Path C:\LabFiles\AzureCreds.ps1;

if($IsCloudLabs){
        if(Get-Module -Name solliance-synapse-automation){
                Remove-Module solliance-synapse-automation
        }
        Import-Module "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\environment-setup\solliance-synapse-automation"

        . C:\LabFiles\AzureCreds.ps1

        $userName = $AzureUserName                # READ FROM FILE
        $password = $AzurePassword                # READ FROM FILE
        $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"     # READ FROM FILE
        $global:sqlPassword = "password.1!!" 

        $securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
        $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $userName, $SecurePassword

        Connect-AzAccount -Credential $cred | Out-Null

        $resourceGroupName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "*Many*" }).ResourceGroupName

        if ($resourceGroupName.Count -gt 1)
        {
                $resourceGroupName = $resourceGroupName[0];
        }

        $ropcBodyCore = "client_id=$($clientId)&username=$($userName)&password=$($password)&grant_type=password"
        $global:ropcBodySynapse = "$($ropcBodyCore)&scope=https://dev.azuresynapse.net/.default"
        $global:ropcBodyManagement = "$($ropcBodyCore)&scope=https://management.azure.com/.default"
        $global:ropcBodySynapseSQL = "$($ropcBodyCore)&scope=https://sql.azuresynapse.net/.default"
        $global:ropcBodyPowerBI = "$($ropcBodyCore)&scope=https://analysis.windows.net/powerbi/api/.default"

          $artifactsPath = "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts"

        $reportsPath = "..\reports"
        $templatesPath = "C:\synapse-ws-L400\azure-synapse-analytics-workshop-400-master\artifacts\environment-setup\templates"
        $datasetsPath = "..\datasets"
        $dataflowsPath = "..\dataflows"
        $pipelinesPath = "..\pipelines"
        $sqlScriptsPath = "..\sql"
} else {
        if(Get-Module -Name solliance-synapse-automation){
                Remove-Module solliance-synapse-automation
        }
        Import-Module "..\solliance-synapse-automation"

        #Different approach to run automation in Cloud Shell
        $subs = Get-AzSubscription | Select-Object -ExpandProperty Name
        if($subs.GetType().IsArray -and $subs.length -gt 1){
                $subOptions = [System.Collections.ArrayList]::new()
                for($subIdx=0; $subIdx -lt $subs.length; $subIdx++){
                        $opt = New-Object System.Management.Automation.Host.ChoiceDescription "$($subs[$subIdx])", "Selects the $($subs[$subIdx]) subscription."   
                        $subOptions.Add($opt)
                }
                $selectedSubIdx = $host.ui.PromptForChoice('Enter the desired Azure Subscription for this lab','Copy and paste the name of the subscription to make your choice.', $subOptions.ToArray(),0)
                $selectedSubName = $subs[$selectedSubIdx]
                Write-Information "Selecting the $selectedSubName subscription"
                Select-AzSubscription -SubscriptionName $selectedSubName
        }

        $resourceGroupName = Read-Host "Enter the resource group name";

        $userName = ((az ad signed-in-user show) | ConvertFrom-JSON).UserPrincipalName

        #$global:sqlPassword = Read-Host -Prompt "Enter the SQL Administrator password you used in the deployment" -AsSecureString
        #$global:sqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($sqlPassword))

        $artifactsPath = "..\.."
        $reportsPath = "..\reports"
        $templatesPath = "..\templates"
        $datasetsPath = "..\datasets"
        $dataflowsPath = "..\dataflows"
        $pipelinesPath = "..\pipelines"
        $sqlScriptsPath = "..\sql"
}


Write-Information "Using $resourceGroupName";

$uniqueId =  (Get-AzResourceGroup -Name $resourceGroupName).Tags["DeploymentId"]
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
        "1 - Clean Data" = "$artifactsPath\day-03\lab-06-machine-learning"
        "2 - Data Engineering" = "$artifactsPath\day-03\lab-06-machine-learning"
        "3 - Feature Engineering" = "$artifactsPath\day-03\lab-06-machine-learning"
        "4 - ML Model Building" = "$artifactsPath\day-03\lab-06-machine-learning" 
}

$notebookSparkPools = [ordered]@{
        "1 - Clean Data" = $sparkPoolName1
        "2 - Data Engineering" = $sparkPoolName1
        "3 - Feature Engineering" = $sparkPoolName1
        "4 - ML Model Building" = $sparkPoolName1
}

$storageAccounts = Get-AzResource -ResourceGroupName $resourceGroupName -ResourceType "Microsoft.Storage/storageAccounts"
$asadatalakename = $storageAccounts | Where-Object { $_.Name -Notlike 'ml*' }
$storagedatalake =$asadatalakename.Name


$cellParams = [ordered]@{
        "#data_lake_account_name#" = $storagedatalake
        "#file_system_name" = "source"
        "#full_dataset" = "rawdata"

}

foreach ($notebookName in $notebooks.Keys) {

        $notebookFileName = "$($notebooks[$notebookName])\$($notebookName).ipynb"
        Write-Information "Creating notebook $($notebookName) from $($notebookFileName)"
        $result = Create-SparkNotebook -TemplatesPath $templatesPath -SubscriptionId $SubscriptionId -ResourceGroupName $resourceGroupName `
                -WorkspaceName $workspaceName -SparkPoolName $notebookSparkPools[$notebookName] -Name $notebookName -NotebookFileName $notebookFileName -PersistPayload $false
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
