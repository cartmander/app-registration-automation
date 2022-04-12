param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,

    [Parameter(Mandatory=$true)]
    [string] $name,

    [Parameter(Mandatory=$true)]
    [string[]] $owners,

    [Parameter(Mandatory=$true)]
    [string] $keyVault,

    [string[]] $apiPermissions,

    [string[]] $replyUrls
)

function UploadCertificateToKeyVault
{
    param(
        [object] $certificate,
        [string] $appId
    )
    
    $clientId = $name + "-AzureAD--ClientId"
    $clientSecret = $name + "-AzureAD--ClientSecret"

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears(1).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    #AzureAD--ClientId Secret
    az keyvault secret set --name $clientId --vault-name $keyVault --value $appId

    #AzureAD--ClientSecret Secret
    $secret = az keyvault secret set --name $clientSecret --vault-name $keyVault --value $certificate.password | ConvertFrom-Json    
    az keyvault secret set-attributes --id $secret.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

function AddCertificate
{
    param(
        [string] $appId
    )

    $certificate = az ad app credential reset --id $appId --years 1 | ConvertFrom-Json

    UploadCertificateToKeyVault $certificate $appId
}

function AddReplyUrls
{
    param(
        [string] $appId
    )

    if ($replyUrls.Count -gt 0)
    {
        foreach ($replyUrl in $replyUrls)
        {
            az ad app update --id $appId --add replyUrls $replyUrl
        }
    }

    else
    {
        az ad app update --id $appId --reply-urls "https://admin.indigo.willistowerswatson.com/signin-oidc"
    }
}

function UpdatePermissionsAndApis
{
    az ad app update --id $appId --set oauth2Permissions[0].isEnabled=false
    az ad app update --id $appId --set oauth2Permissions=[]
    az ad app update --id $appId --set oauth2Permissions=@OAuth2Permissions.json

    #Identifier URI
    az ad app update --id $appId --identifier-uris "api://$appId"
}

function AddApiPermissions
{
    param(
        [string] $appId
    )

    $api = "00000003-0000-0000-c000-000000000000"

    if ($apiPermissions.Count -gt 0)
    {
        foreach ($apiPermission in $apiPermissions)
        {
            az ad app permission add --id $appId --api $api --api-permissions $apiPermission
        }
    }

    else
    {
        az ad app permission add --id $appId --api $api --api-permissions 14dad69e-099b-42c9-810b-d002981feec1=Scope
        az ad app permission add --id $appId --api $api --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
        az ad app permission add --id $appId --api $api --api-permissions b340eb25-3456-403f-be2f-af7a0d370277=Scope
    }
}

function AddOwners
{
    param(
        [string] $appId
    )

    foreach ($owner in $owners)
    {
        $appOwner = az ad user show --id $owner | ConvertFrom-Json

        if($null -ne $appOwner)
        {
            $ownerObjectId = $appOwner.ObjectId
            az ad app owner add --id $appId --owner-object-id $ownerObjectId
        }
    }
}

try
{
    az account set --subscription $subscription

    $getAADApplication = Get-AzureADApplication -Filter "DisplayName eq '$name'"
    $getKeyVault = az keyvault show --name $keyVault | ConvertFrom-Json

    if ($null -eq $getKeyVault)
    {
        Write-Host "Key Vault '$getKeyVault' does not exist."
        exit 1
    }

    if ($null -ne $getAADApplication)
    {
        Write-Host "App Registration '$name' already exists."
        exit 1
    }

    else
    {
        $createAADApplication = az ad app create --display-name $name | ConvertFrom-Json
    
        $appId = $createAADApplication.AppId
    
        #Owners
        AddOwners $appId
    
        #API Permissions
        AddApiPermissions $appId
    
        # Expose an API
        UpdatePermissionsAndApis
    
        # Authentication
        AddReplyUrls $appId
    
        # App Roles
        az ad app update --id $appId --app-roles `@AppRoles.json

        # Certificate
        AddCertificate $appId

        Write-Host "App Registration '$name' has been created successfully."
    }
}

catch {}