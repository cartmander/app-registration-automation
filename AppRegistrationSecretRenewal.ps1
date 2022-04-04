param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,
    
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
        [string] $keyVaultName
    )

    $prefix = "AzureAD--ClientId"

    if ($keyVaultName.Contains("AzureAd--ClientId"))
    {
        
    }


    if ($keyVaultName.Contains("AzureAd--ClientId"))
    {
        $prefix = $keyVaultName.Substring(0, $keyVaultName.IndexOf('AzureAd--ClientId'))
        $clientSecret = "$prefix-AzureAd--ClientSecret"
        $appIdList += @{$virtualMachineId=$getAADApplication.appId}
    }

    elif ($keyVaultName.Contains("AzureAD--ClientId"))
    {
        $prefix = $keyVaultName.Substring(0, $keyVaultName.IndexOf('AzureAD--ClientId'))
        $clientSecret = "$prefix-AzureAD--ClientSecret"
        $appIdList += @{$clientSecret=$getAADApplication.appId}
    }
    
    return $clientSecretName
}

function GetAppIdsFromKeyVaults
{
    $appIdDictionary = @{}
    
    $keyVaults = az keyvault list | ConvertFrom-Json

    foreach ($keyVault in $keyVaults)
    {
        $keyVaultName = $keyVault.name

        try
        {
            $keyVaultSecretList = az keyvault secret list --vault-name $keyVaultName --query "[?ends_with(name, 'AzureAD--ClientId') || ends_with(name, 'AzureAd--ClientId')]" | ConvertFrom-Json

            if (!([string]::IsNullOrEmpty($keyVaultSecretList)))
            {
                foreach ($keyVaultSecret in $keyVaultSecretList)
                {
                    $keyVaultClientIdName = $keyVaultSecret.name
                    $keyVaultClientIdValue = az keyvault secret show --vault-name $keyVaultName --name $keyVaultClientIdName | ConvertFrom-Json
                
                    $getAADApplication = az ad app show --id $keyVaultClientIdValue.value | ConvertFrom-Json
                    
                    if(!([string]::IsNullOrEmpty($getAADApplication)))
                    {
                        $appIdDictionary.Add($keyVaultClientIdName, $getAADApplication.appId)
                    }
                }
            }
        }

        catch
        {
        }
    }

    return $appIdDictionary
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

            if(!([string]::IsNullOrEmpty($certificateEndDate)) -and $timeDifference -le 7)
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

function GetAppRegistrationCredentials
{
    param(
        [hashtable] $appIdDictionary
    )

    foreach($appIdKeyPair in $appIdDictionary.GetEnumerator())
    {
        $clientIdName = $appIdKeyPair.Key
        $appId = $appIdKeyPair.Value

        try
        {
            $certificateList = az ad app credential list --id $appId | ConvertFrom-Json

            AddOrRenewCertificate $certificateList $appId

        }

        catch
        {
        }
    }
}

function UploadSecretToKeyVault
{
    param(
        [object] $secret,
        [string] $name
    )

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    $secret = az keyvault secret set --name $name --vault-name $keyVaultName --value $secret.password | ConvertFrom-Json    
    az keyvault secret set-attributes --id $secret.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

try
{
    az account set --subscription $subscription
    
    $appIdDictionary = GetAppIdsFromKeyVaults

    AddOrRenewAppRegistrationsCertificate $appIdDictionary
}

catch
{

}