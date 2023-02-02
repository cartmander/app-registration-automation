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

function UpsertSecretToKeyVault
{
    param(
        [object] $clientSecret,
        [string] $clientSecretValue
    )
    
    $createdDate = (Get-Date).ToUniversalTime()
    $clientSecretName = "$($appRegistrationId)-$($createdDate)"

    $expiryDate = $createdDate.AddYears($secretDuration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    $secret = az keyvault secret set --name $clientSecretName --vault-name $keyVault --value $clientSecretValue | ConvertFrom-Json    
    az keyvault secret set-attributes --id $secret.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

function ProcessKeyVaultWrite
{
    param(
        [object] $clientSecret
    )
    
    $keyVaultSecretList = az keyvault secret list --vault-name $keyVaultName --query "[?starts_with(name, '$appRegistrationName')]" | ConvertFrom-Json
        
    if ($null -ne $keyVaultSecretList)
    {
        $keyVaultSecret = $keyVaultSecretList[0]
        $showKeyVaultSecret = az keyvault secret show --vault-name $keyVault --name $keyVaultSecret.name | ConvertFrom-Json

        UpsertClientSecretToKeyVault $keyVaultSecret $showKeyVaultSecret.value
    }

    else
    {
        UpsertClientSecretToKeyVault $clientSecret $clientSecret.password
    }

    return $appRegistrationList
}

function RenewAppRegistrationClientSecret
{
    $createdDate = (Get-Date).ToUniversalTime()
    $clientSecretName = "$($appRegistrationName)-$($createdDate)"

    $newClientSecret = az ad app credential reset --id $appRegistrationId --years $secretDuration  --display-name $clientSecretName --append | ConvertFrom-Json

    Write-Host "NEW Client Secret generated for App Registration: '$appRegistrationName'"

    #ProcessKeyVaultWrite $newClientSecret
}

function IsAppRegistrationForRenewal
{
    $clientSecretList = az ad app credential list --id $appRegistrationId | ConvertFrom-Json

    if(![string]::IsNullOrEmpty($clientSecretList) -or $null -ne $clientSecretList)
    {
        $isForRenewal = $true

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