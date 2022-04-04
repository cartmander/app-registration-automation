# Azure App Registration Automation with Secret Renewal

App Registration - Running this Powershell script will allow us to create an App registration by simply providing its name. Optionally, we can include a list of Owners and Redirect URIs that will be used by the App registration.

App Registration Credential Renewal - Running this Powershell script will look for App registration ids from the secrets of all Key Vault found under a specified subscription. By default, the duration for the secret is set to 1 year (minimum).

## Powershell Parameters

Provide the following values as arguments:

AppRegistration.ps1
- name - (string) Name of App registration
- owners - (array of strings) List of owners to be included on App registration creation
- subscription - (string) - Azure subscription
- replyUrls - (array of strings) (Optional) List of Redirect URIs to be included on App registration creation

AppRegistrationCredentialRenewal.ps1
- subscription - (string) - Azure subscription
- duration - (int) (Optional) Duration of the secret (expiration)

## Expected Output

After running these scripts, we should be able to create an App registration and we should also be able to update App registration credentials and upload them to their specific Key Vaults.