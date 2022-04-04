param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,
    
    [int] $duration
)

function SecretDuration
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
    $appIdList = @{}
    
    $keyVaults = az keyvault list | ConvertFrom-Json

    foreach ($keyVault in $keyVaults)
    {
        $keyVaultName = $keyVault.name

        $keyVaultSecrets = az keyvault secret list --vault-name $keyVaultName --query "[?ends_with(name, 'AzureAD--ClientId') || ends_with(name, 'AzureAd--ClientId')]" | ConvertFrom-Json

        if ($null -ne $keyVaultSecrets)
        {
            foreach ($keyVaultSecret in $keyVaultSecrets)
            {
                $keyVaultClientIdName = $keyVaultSecret.name
                $showKeyVaultSecret = az keyvault secret show --vault-name $keyVaultName --name $keyVaultClientIdName | ConvertFrom-Json
                
                $getAADApplication = az ad app show --id $showKeyVaultSecret.value | ConvertFrom-Json
                    
                if($null -ne $getAADApplication)
                {
                    $appIdList.Add($keyVaultClientIdName, $getAADApplication.appId)
                }
            }
        }
    }

    return $appIdList
}

function AddOrRenewAppRegistrationsCertificate
{
    param(
        [string[]] $appIdList
    )

    foreach($appId in $appIdList)
    {
        $certificateList = az ad app credential list --id $appId | ConvertFrom-Json

        foreach ($certificate in $certificateList)
        {
            
        }
    }

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

try
{
    az account set --subscription $subscription
    
    $appIdList = GetAppIdsFromKeyVaults
    Write-Host "eto na"
    Write-Host $appIdList
}

catch
{

}