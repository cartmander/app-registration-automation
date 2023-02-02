param(
    [Parameter(Mandatory=$true)]
    [string] $appRegistrationId,

    [Parameter(Mandatory=$true)]
    [string] $appRegistrationName,

    [Parameter(Mandatory=$true)]
    [bool] $shouldRenew,

    [int] $secretDuration = 1,
    [int] $spanOfDaysForRenewal = 211,
    [string] $keyVault = "ae-expiring-secrets-kv"
)

function ProcessSecretData
{
    param(
        [string] $secretName,
        [string] $secretValue,
        [string] $startDate,
        [string] $endDate
    )

    $file = "..\.\csv\AppRegistrations.csv"
    $csv = Import-Csv $file

    foreach ($record in $csv) 
    {
        if ($record.AppRegistrationId -eq $appRegistrationId)
        {
            $record.SecretName = $secretName
            $record.SecretValue = $secretValue
            $record.CreatedDate = $startDate
            $record.ExpiryDate = $endDate
        }
    }

    $csv | Export-Csv $file -NoTypeInformation
}

function RenewAppRegistrationClientSecret
{
    $createdDateToAppend = Get-Date –format "yyyyMMdd"
    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($secretDuration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    $clientSecretName = "$($appRegistrationName)-$($createdDateToAppend)"

    $newClientSecret = az ad app credential reset --id $appRegistrationId --years $secretDuration --display-name $clientSecretName --append | ConvertFrom-Json

    Write-Host "Client Secret generated for App Registration: '$appRegistrationName'"

    ProcessSecretData $clientSecretName $newClientSecret.password $setSecretCreatedDate $setSecretExpiryDate
}

function IsAppRegistrationForRenewal
{
    $clientSecretList = az ad app credential list --id $appRegistrationId | ConvertFrom-Json

    $isForRenewal = $true

    if(![string]::IsNullOrEmpty($clientSecretList) -or $null -ne $clientSecretList)
    {
        foreach ($clientSecret in $clientSecretList)
        {
            $currentDate = Get-Date
            $clientSecretEndDate = $clientSecret.endDateTime

            $timeDifference = New-TimeSpan -Start $currentDate -End $clientSecretEndDate
            $timeDifferenceInDays = $timeDifference.Days

            if ($timeDifferenceInDays -gt $spanOfDaysForRenewal)
            {   
                $isForRenewal = $false
            }
        }
    }

    return $isForRenewal
}

try
{  
    $appRegistrationForRenewal = IsAppRegistrationForRenewal

    if ($appRegistrationForRenewal)
    { 
        if($shouldRenew)
        {
            RenewAppRegistrationClientSecret
        }
    }

    else
    {
        Write-Host "App Registration: '$appRegistrationName' is not for renewal"
    }
}

catch {}