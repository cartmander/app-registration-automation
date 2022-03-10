# Azure App Registration Automation

App Registration - Running this Powershell automation will allow you to create an App registration by simply providing its name. Optionally, you can include a list of Owners and Redirect URIs that will be used by the App registration.

Secret - There is also a dedicated script for appending / resetting App registration secrets using your specified list of App registrations and save these secrets to a Key Vault of your choice. By default, the duration for the secret is set to 1 year (minimum).

## Powershell Parameters

Provide the following values as arguments:

AppRegistration.ps1
- name - (string) Name of App registration
- owners - (array of strings) (Optional) List of owners to be included on App registration creation
- replyUrls - (array of strings) (Optional) List of Redirect URIs to be included on App registration creation

AppRegistrationSecret.ps1
- appRegistrationNames - (arry of strings) - List of App registrations you want their secrets to be updated
- keyVaultName - (string) (Optional) - The Key Vault where the secrets will be saved
- replyUrls - (int) Duration of the secret (expiration)


## Expected Output

Upon running these scripts, it should be able to create an App registration and we should also be able to update App registration secrets and upload them to a specific Key Vault.