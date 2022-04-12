# Azure App Registration Automation with Client Secret Renewal

Create App Registration - Running this Powershell script will allow us to create an App registration by simply providing its name. Optionally, we can include a list of Owners and Redirect URIs that will be used by the App registration.

Renew App Registration Client Secret - Running this Powershell script will look for App registration ids from the secrets of all Key Vault found under a specified subscription. By default, the duration for the secret is set to 1 year (minimum).

## Powershell Parameters

Provide the following values as arguments:

CreateAppRegistration.ps1
- subscription - (string) - Azure subscription
- name - (string) Name of App registration
- owners - (array of strings) List of owners
- keyVault - (string) - Key vault where the application IDs and initial client secrets will be saved
- apiPermissions - (array of strings) (Optional) List of Api Permissions (please check: https://docs.microsoft.com/en-us/graph/permissions-reference)
- replyUrls - (array of strings) (Optional) List of Redirect URIs

UpdateAppRegistration.ps1
- appId - (string) App ID of App registration
-

RenewAppRegistrationClientSecret.ps1
- subscription - (string) - Azure subscription
- shouldUpdate - (bool) - Checks if client secrets should be renewed or not
- duration - (int) (Optional) Duration of the secret (expiration)

## Expected Output

After running these scripts, we should be able to create an App registration and we should also be able to update App registration client secrets and upload them to their specific Key Vaults.