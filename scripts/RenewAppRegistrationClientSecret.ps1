param(
    [Parameter(Mandatory=$true)]
    [string] $appRegistrationId,

    [Parameter(Mandatory=$true)]
    [string] $appRegistrationName,

    [Parameter(Mandatory=$true)]
    [bool] $shouldRenew
)

$NEW_SECRET_DURATION_IN_YEARS = 1
$SPAN_OF_DAYS_FOR_RENEWAL = 211

function ProcessSecretData
{
    param(
        [string] $secretName,
        [string] $secretValue,
        [string] $startDate,
        [string] $endDate
    )

    try
    {
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

    catch
    {
        Write-Host "##[error]Unable to update Secrets.csv file"
        exit 1
    }
}

function GenerateAppRegistrationClientSecret
{
    try 
    {
        $createdDate = (Get-Date).ToUniversalTime()
        $expiryDate = $createdDate.AddYears($NEW_SECRET_DURATION_IN_YEARS).ToUniversalTime()
    
        $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
        $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    
        $clientSecretName = "$($appRegistrationName)-$($appRegistrationId)"
    
        $newClientSecret = az ad app credential reset --id $appRegistrationId --years $NEW_SECRET_DURATION_IN_YEARS --display-name $clientSecretName --append | ConvertFrom-Json
    
        Write-Host "##[section]NEW Client Secret generated for App Registration: '$appRegistrationName'"
    
        ProcessSecretData $clientSecretName $newClientSecret.password $setSecretCreatedDate $setSecretExpiryDate
    }
    
    catch 
    {
        Write-Host "##[error]Unable to generate new Client Secret for App Registration: '$appRegistrationName'"
        exit 1
    }
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

            if ($timeDifferenceInDays -gt $SPAN_OF_DAYS_FOR_RENEWAL)
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
            GenerateAppRegistrationClientSecret
        }
    }

    else
    {
        Write-Host "##[warning]App Registration: '$appRegistrationName' is not for Client Secret renewal"
    }
}

catch 
{
    exit 1
}