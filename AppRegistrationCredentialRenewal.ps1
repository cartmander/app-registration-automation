param(
    [Parameter(Mandatory=$true)]
    [string] $subscription,

    [Parameter(Mandatory=$true)]
    [bool] $shouldUpdate,

    [int] $duration
)

function GetClientSecretDuration
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
        [string] $keyVaultClientId
    )

    if ($keyVaultClientId.Contains("AzureAd--ClientId"))
    {
        $suffix = "AzureAd--ClientId"
        $prefix = $keyVaultClientId.Substring(0, $keyVaultClientId.IndexOf($suffix))
        $keyVaultClientSecret = $prefix + "AzureAd--ClientSecret"
    }

    elseif ($keyVaultClientId.Contains("AzureAD--ClientId"))
    {
        $suffix = "AzureAD--ClientId"
        $prefix = $keyVaultClientId.Substring(0, $keyVaultClientId.IndexOf($suffix))
        $keyVaultClientSecret = $prefix + "AzureAD--ClientSecret"
    }

    return $keyVaultClientSecret
}

function UploadCertificateToKeyVault
{
    param(
        [object] $certificate,
        [object] $appRegistrationCertificate,
        [int] $duration
    )
    
    $keyVaultClientSecret = SetClientSecretName $appRegistrationCertificate.KeyVaultClientId

    $createdDate = (Get-Date).ToUniversalTime()
    $expiryDate = $createdDate.AddYears($duration).ToUniversalTime()

    $setSecretCreatedDate = $createdDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")
    $setSecretExpiryDate = $expiryDate.ToString("yyyy-MM-dd'T'HH:mm:ssZ")

    $secret = az keyvault secret set --name $keyVaultClientSecret --vault-name $appRegistrationCertificate.KeyVault --value $certificate.password | ConvertFrom-Json    
    az keyvault secret set-attributes --id $secret.id --not-before $setSecretCreatedDate --expires $setSecretExpiryDate
}

function DisplayAppRegistrationCertificatesForRenewal
{
    param(
        [object[]] $appRegistrationForRenewalList
    )

    if ($appRegistrationForRenewalList.Count -ne 0)
    {
        Write-Host "App Registration Certificates for Renewal (expiring within the next 30 days):"
        $appRegistrationForRenewalList | Select-Object -Property AppRegistrationId,AppRegistrationName,KeyVault,CertificateKeyId,DaysRemaining | Sort-Object -Property DaysRemaining | Format-Table
    }

    else
    {
        Write-Host "There are no App Registration Certificates expiring within the next 30 days."
    }
}

function AddOrRenewAppRegistrationCertificates
{
    param(
        [object[]] $appRegistrationCertificateList
    )

    foreach ($appRegistrationCertificate in $appRegistrationCertificateList)
    {
        $duration = GetClientSecretDuration

        $newCertificate = az ad app credential reset --id $appRegistrationCertificate.AppRegistrationId --years $duration | ConvertFrom-Json
        
        UploadCertificateToKeyVault $newCertificate $appRegistrationCertificate $duration
    }
}

function GetAppRegistrationListForRenewal
{
    param(
        [object[]] $appRegistrationList
    )

    $appRegistrationForRenewalList = @()

    foreach ($appRegistration in $appRegistrationList)
    {
        try
        {            
            $certificateList = az ad app credential list --id $appRegistration.AppRegistrationId | ConvertFrom-Json

            if(![string]::IsNullOrEmpty($certificateList) -or $null -ne $certificateList)
            {
                foreach($certificate in $certificateList)
                {
                    $currentDate = Get-Date
                    $certificateEndDate = $certificate.endDate

                    $timeDifference = New-TimeSpan -Start $currentDate -End $certificateEndDate
                    $timeDifferenceInDays = $timeDifference.Days

                    if(![string]::IsNullOrEmpty($certificateEndDate) -and $timeDifferenceInDays -le 30)
                    {   
                        $appRegistrationForRenewal = New-Object -Type PSObject -Property @{
                            'AppRegistrationId'   = $appRegistration.AppRegistrationId
                            'AppRegistrationName' = $appRegistration.AppRegistrationName
                            'KeyVault' = $appRegistration.KeyVault
                            'KeyVaultClientId' = $appRegistration.KeyVaultClientId
                            'CertificateKeyId' = $certificate.keyId
                            'DaysRemaining' = $timeDifferenceInDays
                        }

                        $appRegistrationForRenewalList += $appRegistrationForRenewal
                    }
                }
            }
        }

        catch {}
    }

    return $appRegistrationForRenewalList
}

function GetAppRegistrationList
{
    $appRegistrationList = @()
  
    $keyVaults = az keyvault list | ConvertFrom-Json

    foreach ($keyVault in $keyVaults)
    {
        $keyVaultName = $keyVault.name

        try
        {
            $keyVaultSecretList = az keyvault secret list --vault-name $keyVaultName --query "[?ends_with(name, 'AzureAD--ClientId') || ends_with(name, 'AzureAd--ClientId')]" | ConvertFrom-Json
        
            if ($null -ne $keyVaultSecretList)
            {
                foreach ($keyVaultSecret in $keyVaultSecretList)
                {
                    $keyVaultClientId = az keyvault secret show --vault-name $keyVaultName --name $keyVaultSecret.name | ConvertFrom-Json
                
                    $AADApplication = az ad app show --id $keyVaultClientId.value | ConvertFrom-Json
                    
                    if(![string]::IsNullOrEmpty($AADApplication))
                    {
                        $appRegistration = New-Object -Type PSObject -Property @{
                            'AppRegistrationId'   = $AADApplication.appId
                            'AppRegistrationName' = $AADApplication.displayName
                            'KeyVault' = $keyVaultName
                            'KeyVaultClientId' = $keyVaultSecret.name
                        }

                        $appRegistrationList += $appRegistration
                    }
                }
            }
        }

        catch {}
    }

    return $appRegistrationList
}

try
{
    az account set --subscription $subscription
    
    $appRegistrationList = GetAppRegistrationList

    $appRegistrationForRenewalList = GetAppRegistrationListForRenewal $appRegistrationList

    DisplayAppRegistrationCertificatesForRenewal $appRegistrationForRenewalList

    if($true -eq $shouldUpdate)
    {
        AddOrRenewAppRegistrationCertificates $appRegistrationForRenewalList
    }
}

catch {}