param(
    [Parameter(Mandatory=$true)]
    [string] $name,

    [Parameter(Mandatory=$true)]
    [string[]] $owners,

    [Parameter(Mandatory=$true)]
    [string] $subscription,

    [string[]] $replyUrls,
)

function AddOwners
{
    param(
        [string] $appId
    )

    foreach ($owner in $owners)
    {
        $appOwner = az ad user show --id $owner | ConvertFrom-Json

        if($appOwner -ne $null)
        {
            $ownerObjectId = $appOwner.ObjectId
            az ad app owner add --id $appId --owner-object-id $ownerObjectId
        }
    }
}

function AddApiPermissions
{
    param(
        [string] $appId
    )

    $api = "00000003-0000-0000-c000-000000000000"

    az ad app permission add --id $appId --api $api --api-permissions 14dad69e-099b-42c9-810b-d002981feec1=Scope
    az ad app permission add --id $appId --api $api --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
    az ad app permission add --id $appId --api $api --api-permissions b340eb25-3456-403f-be2f-af7a0d370277=Scope
}

function UpdatePermissionsAndApis
{
    az ad app update --id $appId --set oauth2Permissions[0].isEnabled=false
    az ad app update --id $appId --set oauth2Permissions=[]
    az ad app update --id $appId --set oauth2Permissions=@OAuth2Permissions.json

    #Identifier URI
    az ad app update --id $appId --identifier-uris "api://$appId"
}

function AddReplyUrls
{
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

try
{
    az account set --subscription $subscription

    $getAADApplication = Get-AzureADApplication -Filter "DisplayName eq '$name'"
    
    if ($getAADApplication -eq $null)
    {
        $createAADApplication = az ad app create --display-name $name | ConvertFrom-Json
    
        $appId = $createAADApplication.AppId
        $objectId = $createAADApplication.ObjectId
    
        #Owners
        AddOwners $appId
    
        #API Permissions
        AddApiPermissions $appId
    
        # Expose an API
        UpdatePermissionsAndApis
    
        # Authentication
        AddReplyUrls
    
        # App Roles
        az ad app update --id $appId --app-roles `@AppRoles.json
    }
    
    else
    {
        Write-Host "App registration with a name of '$name' already exists"
        exit 1
    }
}

catch
{
    exit 1
}