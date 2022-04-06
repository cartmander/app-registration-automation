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
        [string] $clientId
    )

    if ($clientId.Contains("AzureAd--ClientId"))
    {
        $suffix = "AzureAd--ClientId"
        $prefix = $clientId.Substring(0, $clientId.IndexOf($suffix))
        $clientSecretName = "$prefix-AzureAd--ClientSecret"
    }

    elseif ($clientId.Contains("AzureAD--ClientId"))
    {
        $suffix = "AzureAD--ClientId"
        $prefix = $clientId.Substring(0, $clientId.IndexOf($suffix))
        $clientSecretName = "$prefix-AzureAD--ClientSecret"
    }   

    return $clientSecretName
}

function UploadCertificateToKeyVault
{
    param(
        [object] $appRegistrationCredential,
        [object] $certificate,
        [string] $keyVaultClientId
    )
    
    $keyVaultClientSecret = SetClientSecretName $keyVaultClientId #umay

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

        $keyVaultClientId = $appRegistrationCredential.KeyVaultClientId.ToString()

        $certificate = az ad app credential reset --id $appRegistrationCredential.AppRegistrationId --years $duration | ConvertFrom-Json
        
        UploadCertificateToKeyVault $certificate $keyVaultClientId
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

            if(![string]::IsNullOrEmpty($certificateList) -or $null -ne $certificateList)
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
    az account set --subscription $subscription
    
    $appRegistrationList = GetAppRegistrationList

    $appRegistrationForRenewalList = GetAppRegistrationListForRenewal $appRegistrationList

    if($true -eq $shouldUpdate)
    {
        AddOrRenewAppRegistrationCredentials $appRegistrationForRenewalList
    }
}

catch {}