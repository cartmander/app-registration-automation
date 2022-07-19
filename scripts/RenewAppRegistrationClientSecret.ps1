param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,

    [Parameter(Mandatory=$true)]
    [bool] $shouldUpdate,

    [int] $duration
)

function GetClientSecretDuration
{
    if ($null -eq $duration -or $duration -lt 1)
    {
        $duration = 1
    }

    if ($duration -gt 100)
    {
        $duration = 100
    }

    return $duration
}

function SetClientSecretName
{
    param(
        [string] $keyVaultClientId
    )

    if ($keyVaultClientId.Contains("AzureAd--ClientId"))
    {
        $suffix = "AzureAd--ClientId"
        $prefix = $keyVaultClientId.Substring(0, $keyVaultClientId.IndexOf($suffix))
        $keyVaultClientSecret = $prefix + "AzureAd--ClientSecret"
    }

    elseif ($keyVaultClientId.Contains("AzureAD--ClientId"))
    {
        $suffix = "AzureAD--ClientId"
        $prefix = $keyVaultClientId.Substring(0, $keyVaultClientId.IndexOf($suffix))
        $keyVaultClientSecret = $prefix + "AzureAD--ClientSecret"
    }

    return $keyVaultClientSecret
}

function UploadClientSecretToKeyVault
{
    param(
        [object] $clientSecret,
        [object] $appRegistrationClientSecret,
        [int] $duration
    )
    
    $keyVaultClientSecret = SetClientSecretName $appRegistrationClientSecret.KeyVaultClientId

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    
    $appRegistrationId = $appRegistrationClientSecret.AppRegistrationId
    $clientSecretId = $appRegistrationClientSecret.ClientSecretId

    $secret = az keyvault secret set --name $keyVaultClientSecret --vault-name $appRegistrationClientSecret.KeyVault --value $clientSecret.password --tags AppRegistrationId=$appRegistrationId ClientSecretId=$clientSecretId | ConvertFrom-Json    
    az keyvault secret set-attributes --id $secret.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

function DisplayAppRegistrationClientSecretsForRenewal
{
    param(
        [object[]] $appRegistrationForRenewalList
    )

    if ($appRegistrationForRenewalList.Count -ne 0)
    {
        Write-Host "App Registration Client Secrets for Renewal (expiring within the next 30 days):"
        $appRegistrationForRenewalList | Select-Object -Property AppRegistrationId,AppRegistrationName,KeyVault,ClientSecretId,DaysRemaining | Sort-Object -Property DaysRemaining | Format-Table
    }

    else
    {
        Write-Host "There are no App Registration Client Secrets expiring within the next 30 days."
    }
}

function AddOrRenewAppRegistrationClientSecrets
{
    param(
        [object[]] $appRegistrationClientSecretList
    )

    foreach ($appRegistrationClientSecret in $appRegistrationClientSecretList)
    {
        $duration = GetClientSecretDuration

        $newClientSecret = az ad app credential reset --id $appRegistrationClientSecret.AppRegistrationId --years $duration | ConvertFrom-Json
        
        UploadClientSecretToKeyVault $newClientSecret $appRegistrationClientSecret $duration
    }
}

function GetAppRegistrationListForRenewal
{
    param(
        [object[]] $appRegistrationList
    )

    $appRegistrationForRenewalList = @()

    foreach ($appRegistration in $appRegistrationList)
    {
        try
        {            
            $clientSecretList = az ad app credential list --id $appRegistration.AppRegistrationId | ConvertFrom-Json

            if(![string]::IsNullOrEmpty($clientSecretList) -or $null -ne $clientSecretList)
            {
                foreach($clientSecret in $clientSecretList)
                {
                    $currentDate = Get-Date
                    $clientSecretEndDate = $clientSecret.endDate

                    $timeDifference = New-TimeSpan -Start $currentDate -End $clientSecretEndDate
                    $timeDifferenceInDays = $timeDifference.Days

                    if(![string]::IsNullOrEmpty($clientSecretEndDate) -and $timeDifferenceInDays -le 30)
                    {   
                        $appRegistrationForRenewal = New-Object -Type PSObject -Property @{
                            'AppRegistrationId'   = $appRegistration.AppRegistrationId
                            'AppRegistrationName' = $appRegistration.AppRegistrationName
                            'KeyVault' = $appRegistration.KeyVault
                            'KeyVaultClientId' = $appRegistration.KeyVaultClientId
                            'ClientSecretId' = $clientSecret.keyId
                            'DaysRemaining' = $timeDifferenceInDays
                        }

                        $appRegistrationForRenewalList += $appRegistrationForRenewal
                    }
                }
            }
        }

        catch {}
    }

    return $appRegistrationForRenewalList
}

function GetAppRegistrationList
{
    $appRegistrationList = @()
  
    $keyVaults = az keyvault list | ConvertFrom-Json

    foreach ($keyVault in $keyVaults)
    {
        $keyVaultName = $keyVault.name

        try
        {
            $keyVaultSecretList = az keyvault secret list --vault-name $keyVaultName --query "[?ends_with(name, 'AzureAD--ClientId') || ends_with(name, 'AzureAd--ClientId')]" | ConvertFrom-Json
        
            if ($null -ne $keyVaultSecretList)
            {
                foreach ($keyVaultSecret in $keyVaultSecretList)
                {
                    $keyVaultClientId = az keyvault secret show --vault-name $keyVaultName --name $keyVaultSecret.name | ConvertFrom-Json
                
                    $AADApplication = az ad app show --id $keyVaultClientId.value | ConvertFrom-Json
                    
                    if(![string]::IsNullOrEmpty($AADApplication))
                    {
                        $appRegistration = New-Object -Type PSObject -Property @{
                            'AppRegistrationId'   = $AADApplication.appId
                            'AppRegistrationName' = $AADApplication.displayName
                            'KeyVault' = $keyVaultName
                            'KeyVaultClientId' = $keyVaultSecret.name
                        }

                        $appRegistrationList += $appRegistration
                    }
                }
            }
        }

        catch {}
    }

    return $appRegistrationList
}

try
{
    az login --identity
    
    $appRegistrationList = GetAppRegistrationList

    $appRegistrationForRenewalList = GetAppRegistrationListForRenewal $appRegistrationList

    DisplayAppRegistrationClientSecretsForRenewal $appRegistrationForRenewalList

    if($true -eq $shouldUpdate)
    {
        AddOrRenewAppRegistrationClientSecrets $appRegistrationForRenewalList
    }
}

catch {}