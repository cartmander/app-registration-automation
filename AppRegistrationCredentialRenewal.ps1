param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,
    
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
                
                    $getAADApplication = az ad app show --id $keyVaultClientIdValue.value | ConvertFrom-Json
                    
                    if(![string]::IsNullOrEmpty($getAADApplication))
                    {
                        $appIdsDictionary.Add("$keyVaultClientIdName = $keyVaultName", $getAADApplication.appId)
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
        Write-Host "aw"
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

    $split = $clientIdName.Split("=")
    $keyVaultName = $split[1].Replace(' ', '')
    
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

function GetAppRegistrationCredentialsForRenewal
{
    param(
        [hashtable] $appIdsDictionary
    )

    foreach($appIdKeyPair in $appIdsDictionary.GetEnumerator())
    {
        $clientIdName = $appIdKeyPair.Key
        $appId = $appIdKeyPair.Value

        try
        {
            $certificateList = az ad app credential list --id $appId | ConvertFrom-Json
            $certificate = AddOrRenewCertificate $certificateList $appId

            UploadCertificateToKeyVault $certificate $clientIdName
        }

        catch
        {
        }
    }
}

try
{
    az account set --subscription $subscription
    
    $appIdsDictionary = GetAppIdsFromKeyVaults

    GetAppRegistrationCredentialsForRenewal $appIdsDictionary
}

catch
{
}