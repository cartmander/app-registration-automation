param(
    [bool] $shouldRenew=$true,
    [string] $SUBSCRIPTION = "43ca9934-1ab8-48a2-a8e8-723d126a4a00", #SolutoHome1
    [string] $TENANT = "prodhome1services.onmicrosoft.com"
)

function ValidateJobState
{
    param(
        [object] $childJob
    )

    Write-Host "##[command]=================================================="
    Write-Host "##[command]Job output for $($childJob.Name)"
    Write-Host "##[command]=================================================="

    $childJob | Receive-Job -Keep
    Write-Host "##[section]$($childJob.Name) finished executing with `"$($childJob.State)`" state"
}

function JobLogging
{
    Write-Host "##[command]Waiting for jobs to finish executing..."

    $JobTable = Get-Job | Wait-Job | Where-Object {$_.Name -like "*AutomationJob"}
    $JobTable | ForEach-Object -Process {
        $_.ChildJobs[0].Name = $_.Name.Replace("AutomationJob", "ChildJob")
    }

    $ChildJobs = Get-Job -IncludeChildJob | Where-Object {$_.Name -like "*ChildJob"}
    $ChildJobs | ForEach-Object -Process {
        ValidateJobState $_
    }

    $ChildJobs | Select-Object -Property Id, Name, State, PSBeginTime, PSEndTime | Format-Table
}


function ProcessAppRegistrationClientSecretRenewal
{
    param(
        [object] $csv
    )

    $csv | ForEach-Object -Process {

        $appRegistrationId = $_.AppRegistrationId
        $showAppRegistration = az ad app show --id $appRegistrationId | ConvertFrom-Json
        $appRegistrationName = $showAppRegistration.displayName

        $AppRegClientSecretRenewalArguments = @(
            $appRegistrationId
            $appRegistrationName
            $shouldRenew
        )

        Start-Job -Name "$($appRegistrationName)-AutomationJob" -FilePath .\RenewAppRegistrationClientSecret.ps1 -ArgumentList $AppRegClientSecretRenewalArguments
    }

    JobLogging
}

function ProcessSecretUpsertToKeyVault
{
    param(
        [object] $csv
    )

    $csv | ForEach-Object -Process {

        $secretName = $_.SecretName

        $SecretUpsertToKeyVaultArguments = @(
            $secretName,
            $_.SecretValue
            $_.CreatedDate
            $_.ExpiryDate
        )

        Start-Job -Name "$($secretName)-AutomationJob" -FilePath .\UpsertSecretToKeyVault.ps1 -ArgumentList $SecretUpsertToKeyVaultArguments
    }

    JobLogging
}

function ValidateCsv
{
    param(
        [object] $csv
    )

    $requiredHeaders = "AppRegistrationId", "SecretName", "SecretValue", "CreatedDate", "ExpiryDate"
    $csvHeaders = $csv[0].PSObject.Properties.Name.Split()

    foreach ($header in $csvHeaders)
    {
        if (-not $requiredHeaders.Contains($header))
        {
            Write-Host "##[error]CSV: CSV contains invalid headers"
            exit 1
        }
    }
}

try 
{
    $ErrorActionPreference = 'Continue'

    Write-Host "##[section]Initializing automation..."
    
    #----Renew App Registration Secrets----#
    $csv = Import-Csv "..\.\csv\AppRegistrations.csv"
    ValidateCsv $csv

    az login --allow-no-subscriptions --tenant $TENANT
    ProcessAppRegistrationClientSecretRenewal $csv
    az logout

    Get-Job | Remove-Job

    #----Upload Secrets to Key Vault----#
    $csv = Import-Csv "..\.\csv\AppRegistrations.csv"
    ValidateCsv $csv

    az login
    az account set --subscription $SUBSCRIPTION
    ProcessSecretUpsertToKeyVault $csv
    az logout

    Get-Job | Remove-Job

    Write-Host "##[section]Done running the automation..."
}

catch 
{
    exit 1
}