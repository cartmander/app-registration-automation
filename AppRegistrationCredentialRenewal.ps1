param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,
    [bool] $updateCredentials,
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

function AddOrRenewCertificate
{
    param(
        [object] $certificateList,
        [string] $appId
    )

    if(![string]::IsNullOrEmpty($certificateList))
    {
        foreach($certificate in $certificateList)
        {
            $currentDate = Get-Date
            $certificateEndDate = $certificate.endDate

            $timeDifference = New-TimeSpan -Start $currentDate -End $certificateEndDate

            if(![string]::IsNullOrEmpty($certificateEndDate) -and $timeDifference -le 7)
            {
                $duration = GetClientSecretDuration
                $certificate = az ad app credential reset --id $appId --years $duration | ConvertFrom-Json
            }
        }
    }

    else
    {
        $certificate = az ad app credential reset --id $appId --years $duration | ConvertFrom-Json
    }

    return $certificate
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

function SetKeyVaultName
{
    param(
        [string] $clientIdName
    )

    $split = $clientIdName.Split("~")
    $keyVaultName = $split[0].Replace(' ', '')
    
    return $keyVaultName
}

function UploadCertificateToKeyVault
{
    param(
        [object] $certificate,
        [string] $clientIdName
    )

    $clientSecretName = SetClientSecretName $clientIdName
    $keyVaultName = SetKeyVaultName $clientIdName

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
    $keyVaultName = SetKeyVaultName $clientIdName

    $AADApplication = az ad app show --id $appId | ConvertFrom-Json
    $AADApplicationName = $AADApplication.displayName

    if(![string]::IsNullOrEmpty($certificateList))
    {
        foreach($certificate in $certificateList)
        {
            $currentDate = Get-Date
            $certificateEndDate = $certificate.endDate
            $certificateKeyId = $certificate.keyId

            $timeDifference = New-TimeSpan -Start $currentDate -End $certificateEndDate
            $timeDifferenceInDays = $timeDifference.Days

            if(![string]::IsNullOrEmpty($certificateEndDate) -and $timeDifferenceInDays -le 30)
            {
                $appRegistrationCredentialsDictionary.Add("$keyVaultName - $AADApplicationName - $certificateKeyId", "$timeDifferenceInDays days")
            }
        }
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

        try
        {
            $appRegistrationCredentialsDictionary = GetAppRegistrationCredentialsDictionary $appRegistrationCredentialsDictionary $appId $clientIdName
        }

        catch
        {
        }
    }

    return $appRegistrationCredentialsDictionary
}

try
{
    az account set --subscription $subscription
    
    $appIds = GetAppIdsFromKeyVaults

    $appRegistrationCredentials = GetAppRegistrationCredentialsForRenewal $appIds

    Write-Host $appIds.Keys
    Write-Host $appIds.Values
    Write-Host " "
    Write-Host $appRegistrationCredentials.Keys
    Write-Host $appRegistrationCredentials.Values
}

catch
{
}