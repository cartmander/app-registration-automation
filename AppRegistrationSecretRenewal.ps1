param(
    [string[]] $appRegistrationNames,
    [string] $keyVaultName,
    [int] $duration,
    [string] $subscription
)

function SecretDuration
{
    if ($duration -eq $null -or $duration -lt 1)
    {
        $duration = 1
    }

    return $duration
}

function GenerateSecretForAppRegistration
{
    param(
        [string] $appId
    )
    
    $duration = SecretDuration
    $AADSecret = az ad app credential reset --id $appId --years $duration | ConvertFrom-Json

    return $AADSecret
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

az account set --subscription $subscription

if ($appRegistrationNames.Count -gt 0)
{
    foreach ($name in $appRegistrationNames)
    {
        $getAADApplication = Get-AzureADApplication -Filter "DisplayName eq '$name'"

        if ($getAADApplication -ne $null)
        {    
            $appId = $getAADApplication.AppId
        
            $secret = GenerateSecretForAppRegistration $appId
        
            UploadSecretToKeyVault $secret $name
        }
    }
}
