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
        [object] $certificate,
        [string] $clientIdName
    )

    $clientSecretName = SetClientSecretName $clientIdName
    $keyVaultName = GetStringByDelimeter $clientIdName 1

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    $certificate = az keyvault secret set --name $clientSecretName --vault-name $keyVaultName --value $certificate.password | ConvertFrom-Json    
    az keyvault secret set-attributes --id $certificate.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

function AddOrRenewAppRegistrationCredentials
{
    param(
        [hashtable] $appRegistrations
    )

    foreach ($appRegistration in $appRegistrations.GetEnumerator())
    {
        $appRegistrationKey = $appRegistration.Key

        $appId = GetStringByDelimeter $appRegistrationKey 1
        $clientIdName = GetStringByDelimeter $appRegistrationKey 0

        $duration = GetClientSecretDuration
        $certificate = az ad app credential reset --id $appId --years $duration | ConvertFrom-Json #we need appid :(
        
        UploadCertificateToKeyVault $certificate $clientIdName
    }
}

function GetAppRegistrationListForRenewal
{
    $appRegistrationListForRenewal = @()

    param(
        [object[]] $appRegistrationList
    )

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
                        $appRegistration.CredentialKeyId = $certificate.keyId
                        $appRegistration.DaysRemaining = $timeDifferenceInDays

                        $appRegistrationListForRenewal += $appRegistration
                    }
                }
            }
        }

        catch {}
    }

    return $appRegistrationListForRenewal
}

function GetAppRegistrationListFromKeyVaults
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
                            'KeyVault'   = $keyVaultName
                            'KeyVaultClientId' = $keyVaultClientIdName
                            'KeyVaultClientSecret' = ""
                            'CredentialKeyId' = ""
                            'DaysRemaining' = 0
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
    
    $appRegistrationList = GetAppRegistrationListFromKeyVaults

    $appRegistrationListForRenewal = GetAppRegistrationListForRenewal $appRegistrationList

    if($true -eq $shouldUpdate)
    {
        AddOrRenewAppRegistrationCredentials $appRegistrationCredentials
    }
}

catch {}