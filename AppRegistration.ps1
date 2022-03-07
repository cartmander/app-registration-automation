param(
    [string]$name,
    [string[]] $owners,
    [string[]] $replyUrls
)

function AddApiPermissions
{
    param(
        [string]$objectId
    )

    $graphServicePrincipal =  Get-AzureADServicePrincipal -All $true | Where-Object {$_.DisplayName -eq "Microsoft Graph"}
        
    $requiredGraphAccess = New-Object Microsoft.Open.AzureAD.Model.RequiredResourceAccess
    $requiredGraphAccess.ResourceAppId = $graphServicePrincipal.AppId
    $requiredGraphAccess.ResourceAccess = New-Object System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.ResourceAccess]
    
    $delegatedPermissions = @('profile', 'User.Read', 'User.ReadBasic.All')
        
    foreach ($permission in $delegatedPermissions) 
    {
        $requestPermission = $null
        $requestPermission = $graphServicePrincipal.Oauth2Permissions | Where-Object {$_.Value -eq $permission}
    
        if($requestPermission)
        {
            $resourceAccess = New-Object Microsoft.Open.AzureAD.Model.ResourceAccess
            $resourceAccess.Type = "Scope"
            $resourceAccess.Id = $requestPermission.Id    
    
            $requiredGraphAccess.ResourceAccess.Add($resourceAccess)
        }
    
        else
        {
            Write-Host "Delegated permission $permission not found in the Graph Resource API" -ForegroundColor Red
        }
    }
    
    $requiredResourcesAccess = New-Object System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.RequiredResourceAccess]
    $requiredResourcesAccess.Add($requiredGraphAccess)
        
    Set-AzureADApplication -ObjectId $objectId -RequiredResourceAccess $requiredResourcesAccess
}

function AddOwners
{
    param(
        [string]$appId
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

function AddReplyUrls
{
    if ($replyUrls.Count -gt 0)
    {
        foreach($replyUrl in $replyUrls)
        {
            az ad app update --id $appId --add replyUrls $replyUrl
        }
    }

    else
    {
        az ad app update --id $appId --reply-urls "https://admin.indigo.willistowerswatson.com/signin-oidc"
    }
}


$getAADApplication = Get-AzureADApplication -Filter "DisplayName eq '$name'"

if ($getAADApplication -eq $null)
{
    $createAADApplication = az ad app create --display-name $name | ConvertFrom-Json

    $appId = $createAADApplication.AppId
    $objectId = $createAADApplication.ObjectId

    #Owners
    AddOwners $appId

    #API Permissions
    #AddApiPermissions $objectId

    # Expose an API
    az ad app update --id $appId --set oauth2Permissions[0].isEnabled=false
    az ad app update --id $appId --set oauth2Permissions=[]
    az ad app update --id $appId --set oauth2Permissions=@OAuth2Permissions.json

    #Identifier URI
    az ad app update --id $appId --identifier-uris "api://$appId"

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