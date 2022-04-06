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

    return $duration
}

function SetClientSecretName
{
    param(
        [string] $clientIdName
    )

    if ($clientIdName.Contains("AzureAd--ClientId"))
    {
        $suffix = "AzureAd--ClientId"
        $prefix = $clientIdName.Substring(0, $clientIdName.IndexOf($suffix))
        $clientSecretName = "$prefix-AzureAd--ClientSecret"
    }

    elseif ($clientIdName.Contains("AzureAD--ClientId"))
    {
        $suffix = "AzureAD--ClientId"
        $prefix = $clientIdName.Substring(0, $clientIdName.IndexOf($suffix))
        $clientSecretName = "$prefix-AzureAD--ClientSecret"
    }   
    
    return $clientSecretName
}

function UploadCertificateToKeyVault
{
    param(
        [object] $appRegistrationCredential,
        [object] $certificate,
        [string] $keyVaultclientId
    )

    $keyVaultClientSecret = SetClientSecretName $keyVaultclientId

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    $certificate = az keyvault secret set --name $keyVaultClientSecret --vault-name $appRegistrationCredential.KeyVault --value $certificate.password | ConvertFrom-Json    
    az keyvault secret set-attributes --id $certificate.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

function AddOrRenewAppRegistrationCredentials
{
    param(
        [object[]] $appRegistrationCredentialList
    )

    foreach ($appRegistrationCredential in $appRegistrationCredentialList)
    {
        $duration = GetClientSecretDuration

        $certificate = az ad app credential reset --id $appRegistrationKey.AppRegistrationId --years $duration | ConvertFrom-Json
        
        UploadCertificateToKeyVault $certificate $appRegistrationCredential.KeyVaultClientId
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
            $certificateList = az ad app credential list --id $appRegistration.AppRegistrationId | ConvertFrom-Json

            if(![string]::IsNullOrEmpty($certificateList))
            {
                foreach($certificate in $certificateList)
                {
                    $currentDate = Get-Date
                    $certificateEndDate = $certificate.endDate

                    $timeDifference = New-TimeSpan -Start $currentDate -End $certificateEndDate
                    $timeDifferenceInDays = $timeDifference.Days

                    if(![string]::IsNullOrEmpty($certificateEndDate) -and $timeDifferenceInDays -le 30)
                    {   
                        $appRegistrationForRenewal = New-Object -Type PSObject -Property @{
                            'AppRegistrationId'   = $appRegistration.AppRegistrationId
                            'AppRegistrationName' = $appRegistration.AppRegistrationName
                            'KeyVault' = $appRegistration.KeyVault
                            'KeyVaultClientId' = $appRegistration.KeyVaultClientId
                            'CredentialKeyId' = $certificate.keyId
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
                    $keyVaultClientIdName = $keyVaultSecret.name
                    $keyVaultClientIdValue = az keyvault secret show --vault-name $keyVaultName --name $keyVaultClientIdName | ConvertFrom-Json
                
                    $AADApplication = az ad app show --id $keyVaultClientIdValue.value | ConvertFrom-Json
                    
                    if(![string]::IsNullOrEmpty($AADApplication))
                    {
                        $appRegistration = New-Object -Type PSObject -Property @{
                            'AppRegistrationId'   = $AADApplication.appId
                            'AppRegistrationName' = $AADApplication.displayName
                            'KeyVault' = $keyVaultName
                            'KeyVaultClientId' = $keyVaultClientIdName
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
    az account set --subscription $subscription
    
    $appRegistrationList = GetAppRegistrationList

    $appRegistrationForRenewalList = GetAppRegistrationListForRenewal $appRegistrationList

    if($true -eq $shouldUpdate)
    {
        AddOrRenewAppRegistrationCredentials $appRegistrationForRenewalList
    }
}

catch {}