param(
    [string[]] $appRegistrationNames,
    [string] $keyVaultName,
    [int] $duration
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
    $AADCertificate = az ad app credential reset --id $appId --years $duration | ConvertFrom-Json

    $secret = az keyvault secret set --name $name --vault-name $keyVaultName --value $AADCertificate.password | ConvertFrom-Json

    return $secret
}

function UploadSecretToKeyVault
{
    param(
        [object] $secret
    )

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
        
    az keyvault secret set-attributes --id $secret.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

foreach ($name in $appRegistrationNames)
{
    $getAADApplication = Get-AzureADApplication -Filter "DisplayName eq '$name'"

    if ($getAADApplication -ne $null)
    {    
        $appId = $getAADApplication.AppId
        
        $secret = GenerateSecretForAppRegistration $appId
        
        UploadSecretToKeyVault $secret
    }
}