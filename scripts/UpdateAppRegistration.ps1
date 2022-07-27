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
        [string] $appId,
        [object] $AADApplication
    )

    if ($replyUrls.Count -gt 0 -and $null -ne $replyUrls)
    {
        if ($true -eq $resetProperties)
        {
            if ($AADApplication.replyUrls.Count -gt 0)
            {
                az ad app update --id $appId --remove replyUrls
            }
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
        [string] $appId,
        [object] $AADApplication
    )

    #For Api Permission Scoping, please check: https://docs.microsoft.com/en-us/graph/permissions-reference

    $api = "00000003-0000-0000-c000-000000000000"

    if ($apiPermissions.Count -gt 0 -and $null -ne $apiPermissions)
    {
        if ($true -eq $resetProperties)
        {
            if ($AADApplication.requiredResourceAccess.Count -gt 0)
            {
                az ad app update --id $appId --remove requiredResourceAccess
            }
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

    if ($owners.Count -gt 0 -and $null -ne $owners)
    {
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
}

try
{
    #az login --identity

    $getAADApplication = az ad app show --id $appId | ConvertFrom-Json

    $appId = $getAADApplication.appId
    $displayName = $getAADApplication.displayName

    if ($null -ne $getAADApplication)
    {    
        #Owners
        AddOwners $appId
    
        #API Permissions
        AddApiPermissions $appId $getAADApplication
    
        # Authentication
        AddReplyUrls $appId $getAADApplication

        Write-Host "App Registration '$displayName' has been updated successfully."
    }

    else
    {
        Write-Host "App Registration App Id '$appId' does not exist."
        exit 1
    }
}

catch {}