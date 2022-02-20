param(
        [string]$displayName
    )

    function AzureLogin
    {
        $context = Get-AzContext
        $token = Get-AzAccessToken -ResourceTypeName AadGraph
        Connect-AzureAD -AadAccessToken $token.Token -AccountId $context.Account.Id -TenantId $context.Tenant.Id
    }

    function GetAzureADApplicationAppId
    {
        $aadApplication = Get-AzureADApplication -Filter "DisplayName eq $displayName"
        $appId = $aadApplication.AppId
    
        return $appId
    }
    
    function GetAzureADApplicationObjectId
    {
        $aadApplication = Get-AzureADApplication -Filter "DisplayName eq $displayName"
        $appObjectId = $aadApplication.ObjectId
    
        return $appObjectId
    }
    
    function CreateAppRegistration
    {
        $aadApplication = New-AzureADApplication -DisplayName $displayName #"IndigoMonitorApp-Automation"
        $appId = $aadApplication.AppId
        $appObjectId = $aadApplication.ObjectId

        Add-AzureADApplicationOwner -ObjectId $appObjectId -RefObjectId "50a092f7-3eb3-4d89-b431-ebf8d1dbb447"
    }
    
    function AddApiPermissions
    {
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
        
        $appObjectId = GetAzureADApplicationObjectId $displayName
        Set-AzureADApplication -ObjectId $appObjectId -RequiredResourceAccess $requiredResourcesAccess
    }
    
    function AddApplicationRoles
    {
        $applicationRoles = New-Object System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.AppRole]
    
        $administratorAppRole = [Microsoft.Open.AzureAD.Model.AppRole]::new()
        $administratorAppRole.AllowedMemberTypes = New-Object System.Collections.Generic.List[string]
        $administratorAppRole.AllowedMemberTypes.Add("User")
        $administratorAppRole.DisplayName = "Administrator"
        $administratorAppRole.Description = "Administrators have the ability to manage the entire system"
        $administratorAppRole.Value = "administrator"
        $administratorAppRole.Id = "d1c2ade8-98f8-45fd-aa4a-6d06b947c66f"
        $administratorAppRole.IsEnabled = $true
    
        $monitorAppRole = [Microsoft.Open.AzureAD.Model.AppRole]::new()
        $monitorAppRole.AllowedMemberTypes = New-Object System.Collections.Generic.List[string]
        $monitorAppRole.AllowedMemberTypes.Add("User")
        $monitorAppRole.DisplayName = "Monitor"
        $monitorAppRole.Description = "Monitors have the ability to view system metrics"
        $monitorAppRole.Value = "monitor"
        $monitorAppRole.Id = "46c57e1b-a3ad-4647-8a18-c8da203fe70f"
        $monitorAppRole.IsEnabled = $true
    
        $applicationRoles.Add($administratorAppRole)
        $applicationRoles.Add($monitorAppRole)
    
        $appObjectId = GetAzureADApplicationObjectId $displayName
        Set-AzureADApplication -ObjectId $appObjectId -AppRoles $applicationRoles
    }
    
    #Main Program
    AzureLogin
    CreateAppRegistration
    AddApiPermissions
    AddApplicationRoles
    
    # Expose an API
    az ad app update --id $appId --set oauth2Permissions[0].isEnabled=false
    az ad app update --id $appId --set oauth2Permissions=[]
    az create
    
    Set-AzureADApplication -ObjectId $appObjectId -IdentifierUris "api://$appId"
    
    # Certificates and secrets
    #New-AzureADApplicationPasswordCredential -CustomKeyIdentifier IndigoMonitorApp-Secret -ObjectId $appObjectId -EndDate ((Get-Date).AddMonths(12))