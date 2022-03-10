param(
    [string[]] $names,
    [int] $duration
)


foreach ($name in $names)
{
    $getAADApplication = Get-AzureADApplication -Filter "DisplayName eq '$name'"

    if ($getAADApplication -ne $null)
    {
        $createAADApplication = az ad app create --display-name $name | ConvertFrom-Json
    
        $appId = $createAADApplication.AppId
        $objectId = $createAADApplication.ObjectId
    
        New-AzureADApplicationPasswordCredential -CustomKeyIdentifier IndigoMonitorApp-Secret -ObjectId $appObjectId -EndDate ((Get-Date).AddMonths(12))
    }
}