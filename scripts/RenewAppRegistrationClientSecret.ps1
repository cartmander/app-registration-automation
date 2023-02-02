param(
    [Parameter(Mandatory=$true)]
    [string] $appRegistrationId,

    [string] $spanOfDaysForRenewal = "211",
    [string] $keyVault = "ae-expiring-secrets-kv",
    [bool] $shouldUpdate = $false
)

function UpsertSecretToKeyVault
{
    param(
        [object] $clientSecret,
        [string] $clientSecretValue
    )
    
    $createdDate = (Get-Date).ToUniversalTime()
    $clientSecretName = "$($appRegistrationId)-$($createdDate)"

    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

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
    
    $keyVaultSecretList = az keyvault secret list --vault-name $keyVaultName --query "[?starts_with(name, '$appRegistration')]" | ConvertFrom-Json
        
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
    param(
        [string[]] $appRegistrationClientSecretList
    )

    foreach ($appRegistrationClientSecret in $appRegistrationClientSecretList)
    {
        $createdDate = (Get-Date).ToUniversalTime()
        $clientSecretName = "$($appRegistrationId)-$($createdDate)"

        $newClientSecret = az ad app credential reset --id $appRegistrationClientSecret.AppRegistrationId --years $duration  --display-name $clientSecretName --append | ConvertFrom-Json
        
        ProcessKeyVaultWrite $newClientSecret
    }
}

function GetAppRegistrationListForRenewal
{
    $appRegistrationForRenewalList = @()

    $clientSecretList = az ad app credential list --id $appRegistrationId | ConvertFrom-Json

    if(![string]::IsNullOrEmpty($clientSecretList) -or $null -ne $clientSecretList)
    {
        $forRenewal = $false

        foreach ($clientSecret in $clientSecretList)
        {
            $currentDate = Get-Date
            $clientSecretEndDate = $clientSecret.endDate

            $timeDifference = New-TimeSpan -Start $currentDate -End $clientSecretEndDate
            $timeDifferenceInDays = $timeDifference.Days

            if ($timeDifferenceInDays -le $spanOfDaysForRenewal)
            {   
                $forRenewal = $true
            }
        }

        if ($forRenewal)
        {
            $appRegistrationForRenewalList += $appRegistrationId
        }
    }

    return $appRegistrationForRenewalList
}

try
{    
    $appRegistrationForRenewalList = GetAppRegistrationListForRenewal $appRegistrationList

    if ($null -ne $appRegistrationForRenewalList)
    { 
        if($true -eq $shouldUpdate)
        {
            RenewAppRegistrationClientSecret $appRegistrationForRenewalList
        }
    }

    else
    {
        Write-Host "'$appRegistrationId' is not for renewal"
    }
}

catch {}