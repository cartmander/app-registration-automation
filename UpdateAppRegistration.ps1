param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,

    [Parameter(Mandatory=$true)]
    [string] $appId,

    [Parameter(Mandatory=$true)]
    [bool] $resetProperties,

    [string[]] $owners,

    [string[]] $apiPermissions,

    [string[]] $replyUrls
)

function AddReplyUrls
{
    param(
        [string] $appId
    )

    if ($replyUrls.Count -gt 0)
    {
        if ($true -eq $resetProperties)
        {
            az ad app update --id $appId --remove requiredResourceAccess
        }

        foreach ($replyUrl in $replyUrls)
        {
            az ad app update --id $appId --add replyUrls $replyUrl
        }
    }
}

function AddApiPermissions
{
    param(
        [string] $appId
    )

    #For Api Permission Scoping, please check: https://docs.microsoft.com/en-us/graph/permissions-reference

    $api = "00000003-0000-0000-c000-000000000000"

    if ($apiPermissions.Count -gt 0)
    {
        if ($true -eq $resetProperties)
        {
            az ad app update --id $appId --remove replyUrls
        }

        foreach ($apiPermission in $apiPermissions)
        {
            az ad app permission add --id $appId --api $api --api-permissions $apiPermission
        }
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

    $getAADApplication = az ad app show --id $appId

    if ($null -ne $getAADApplication)
    {
        $appId = $getAADApplication.AppId
    
        #Owners
        AddOwners $appId
    
        #API Permissions
        AddApiPermissions $appId
    
        # Authentication
        AddReplyUrls $appId

        Write-Host "$name App Registration has been updated successfully."
    }

    else
    {
        Write-Host "App Registration App Id '$appId' does not exist."
        exit 1
    }
}

catch {}