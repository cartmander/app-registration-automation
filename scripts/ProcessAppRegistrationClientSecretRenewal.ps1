param(
    [Parameter(Mandatory=$true)]
    [string] $username,
    
    [Parameter(Mandatory=$true)]
    [string] $password,

    [bool] $shouldRenew=$false
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
        $AppRegClientSecretRenewalArguments = @(
            $_.AppRegistrationId,
            $shouldRenew
        )

        Start-Job -Name "$($_.AppRegistrationId)-AutomationJob" -FilePath .\scripts\RenewAppRegistrationClientSecret.ps1 -ArgumentList $AppRegClientSecretRenewalArguments
    }

    JobLogging
}

function ValidateCsv
{
    param(
        [object] $csv
    )

    $requiredHeaders = "AppRegistrationId"
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
    az login -u $username -p $password

    $ErrorActionPreference = 'Continue'

    Write-Host "##[section]Initializing automation..."
    
    $csv = Import-Csv ".\csv\AppRegistrations.csv"
    
    ValidateCsv $csv

    ProcessAppRegistrationClientSecretRenewal $csv
    
    Write-Host "##[section]Done running the automation..."
}

catch 
{
    exit 1
}