param(
    [string] $secretName,
    [string] $secretValue,
    [string] $createdDate,
    [string] $expiryDate,

    [string] $keyVault = "ae-expiring-secrets-kv"
)

function UpsertSecretToKeyVault
{
    $secret = az keyvault secret set --name $secretName --vault-name $keyVault --value $secretValue | ConvertFrom-Json    
    az keyvault secret set-attributes --id $secret.id --not-before $createdDate --expires $expiryDate

    Write-Host "Client Secret: '$secretName' has been uploaded/updated to Key Vault: $keyVault"
}

function ValidateArguments
{
    if ([string]::IsNullOrEmpty($secretName) -or 
    [string]::IsNullOrEmpty($secretValue) -or 
    [string]::IsNullOrEmpty($createdDate) -or
    [string]::IsNullOrEmpty($expiryDate))
    {
        Write-Host "##[error]Required parameters for uploading secrets to key vault were not properly supplied with arguments"
        exit 1
    }
}

try
{
    $secretName
    ValidateArguments
    UpsertSecretToKeyVault
}

catch
{
    exit 1
}