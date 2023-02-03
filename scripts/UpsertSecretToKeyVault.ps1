param(
    [string] $secretName,
    [string] $secretValue,
    [string] $createdDate,
    [string] $expiryDate,

    [string] $KEYVAULT = "ae-expiring-secrets-kv"
)

function UpsertSecretToKeyVault
{
    try
    {
        $secret = az keyvault secret set --name $secretName --vault-name $KEYVAULT --value $secretValue | ConvertFrom-Json    
        az keyvault secret set-attributes --id $secret.id --not-before $createdDate --expires $expiryDate
    
        Write-Host "##[section]Client Secret: '$secretName' has been uploaded/updated to Key Vault: '$KEYVAULT'"
    }

    catch
    {
        Write-Host "##[error]Unable to upload/update Client Secret: '$secretName' to Key Vault: '$KEYVAULT'"
        exit 1
    }
}

function ValidateArguments
{
    if ([string]::IsNullOrEmpty($secretName) -or 
    [string]::IsNullOrEmpty($secretValue) -or 
    [string]::IsNullOrEmpty($createdDate) -or
    [string]::IsNullOrEmpty($expiryDate))
    {
        Write-Host "##[error]Required parameters for uploading/updating Client Secrets to Key Vault were not properly supplied with arguments"
        exit 1
    }
}

try
{
    ValidateArguments
    UpsertSecretToKeyVault
}

catch
{
    exit 1
}