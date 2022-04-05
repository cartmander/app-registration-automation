param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,
    [Parameter(Mandatory=$true)]
    [bool] $shouldUpdate,
    [int] $duration
)

function GetAppIdsFromKeyVaults
{
    $appIdsDictionary = @{}
  
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
                        $appIdsDictionary.Add("$keyVaultName ~ $keyVaultClientIdName", $AADApplication.appId)
                    }
                }
            }
        }

        catch
        {
        }
    }

    return $appIdsDictionary
}

function GetClientSecretDuration
{
    if ($null -eq $duration -or $duration -lt 1)
    {
        $duration = 1
    }

    return $duration
}

function AddOrRenewAppRegistrationCredentials
{
    param(
        [object] $appRegistrations
    )

    foreach ($appRegistration in $appRegistrations)
    {
        $appId = GetFirstIndexSplitByDelimeter $appRegistration
        $clientIdName = GetSecondIndexSplitByDelimeter $appRegistration

        $duration = GetClientSecretDuration
        $certificate = az ad app credential reset --id $appId --years $duration | ConvertFrom-Json

        UploadCertificateToKeyVault $certificate $clientIdName
    }
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

function GetFirstIndexSplitByDelimeter
{
    param(
        [string] $key
    )

    $splittedKey = $key.Split("~")
    $firstIndex = $splittedKey[0].Replace(' ', '')
    
    return $firstIndex
}

function GetSecondIndexSplitByDelimeter
{
    param(
        [string] $key
    )

    $splittedKey = $key.Split("~")
    $secondIndex = $splittedKey[1].Replace(' ', '')
    
    return $secondIndex
}

function UploadCertificateToKeyVault
{
    param(
        [object] $certificate,
        [string] $clientIdName
    )

    $clientSecretName = SetClientSecretName $clientIdName
    $keyVaultName = GetFirstIndexSplitByDelimeter $clientIdName

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    $certificate = az keyvault secret set --name $clientSecretName --vault-name $keyVaultName --value $certificate.password | ConvertFrom-Json    
    az keyvault secret set-attributes --id $certificate.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

function GetAppRegistrationCredentialsDictionary
{
    param(
        [hashtable] $appRegistrationCredentialsDictionary,
        [string] $appId,
        [string] $clientIdName
    )

    $certificateList = az ad app credential list --id $appId | ConvertFrom-Json

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
                $appRegistrationCredentialsDictionary.Add("$appId ~ $clientIdName", "$timeDifferenceInDays days")
            }
        }
    }

    else
    {
        $appRegistrationCredentialsDictionary.Add("$appId ~ --", "No certificate yet")
    }

    return $appRegistrationCredentialsDictionary
}

function GetAppRegistrationCredentialsForRenewal
{
    param(
        [hashtable] $appIdsDictionary
    )

    $appRegistrationCredentialsDictionary = @{}

    foreach ($appIdKeyPair in $appIdsDictionary.GetEnumerator())
    {
        $clientIdName = $appIdKeyPair.Key
        $appId = $appIdKeyPair.Value

        $appRegistrationCredentialsDictionary = GetAppRegistrationCredentialsDictionary $appRegistrationCredentialsDictionary $appId $clientIdName
    }

    return $appRegistrationCredentialsDictionary
}

try
{
    az account set --subscription $subscription
    
    $appIds = GetAppIdsFromKeyVaults

    $appRegistrationCredentials = GetAppRegistrationCredentialsForRenewal $appIds

    if($true -eq $shouldUpdate)
    {
        AddOrRenewAppRegistrationCredentials $appRegistrationCredentials.Keys
    }
}

catch
{
}