# Entra ID app credential expiry report

A free PowerShell script that lists **client secrets and certificates** of Microsoft Entra ID (Azure AD) **app registrations and enterprise apps** that have **expired or will expire soon**.

When an app registration's secret or certificate expires, whatever uses it stops working: SSO, mail connectors, backup jobs, integrations. Entra doesn't send an alert for this by default (the "Renew expiring application credentials" recommendation is a preview that needs Workload ID Premium). Run this to see what's coming up.

```text
Expired: 1   Expiring (within 30 days): 3   Apps checked: 42 registrations, 118 enterprise apps

Status   DaysLeft ExpiresUtc       ObjectType      DisplayName  CredentialType CredentialName Owners
------   -------- ----------       ----------      -----------  -------------- -------------- ------
Expired        -3 2026-11-23 09:00 AppRegistration Payroll sync Secret         old            admin@contoso.example
Expiring        5 2026-12-01 09:00 AppRegistration Payroll sync Secret         prod           admin@contoso.example
Expiring       10 2026-12-06 09:00 EnterpriseApp   SAML app     Certificate    saml signing
Expiring       20 2026-12-16 09:00 AppRegistration Backup job   Certificate    cert           admin@contoso.example
```
(Example output from the mock test, not a real tenant.)

Guides: [alerting options](https://truone01.github.io/entra-app-credential-expiry/alert-before-app-secret-expires.html) · [PowerShell details](https://truone01.github.io/entra-app-credential-expiry/find-expiring-client-secrets-powershell.html) · [rotation without downtime](https://truone01.github.io/entra-app-credential-expiry/rotate-app-registration-secret-without-downtime.html)

## Use

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser   # once
./Get-EntraCredentialExpiry.ps1                      # expired + expiring within 30 days
./Get-EntraCredentialExpiry.ps1 -Days 90 -IncludeOwners -CsvPath ./expiring.csv
./Get-EntraCredentialExpiry.ps1 -All                 # every credential
./Get-EntraCredentialExpiry.ps1 -TenantId contoso.onmicrosoft.com
```

- **Read-only.** It signs in with the delegated scope `Application.Read.All`. Microsoft Graph returns only credential metadata (name, key id, start and end date), never secret values, so the script can't see or change a secret.
- Checks both **app registrations** (`Get-MgApplication`) and **enterprise apps / service principals** (`Get-MgServicePrincipal`), which is where SAML signing certificates live.
- `-IncludeOwners` adds app-registration owners, so you know who to ask before you rotate.
- Tested on PowerShell 7 (mock test). It should also run in Windows PowerShell 5.1, but that is untested.

## Rotating a secret without downtime

1. Add a **new** secret or certificate to the app registration. Don't delete the old one yet.
2. Update every place that uses the app (Key Vault, app settings, connector config) to the new credential.
3. Check sign-in logs (Entra > Sign-in logs > Service principal sign-ins) to confirm that only the new key id is used.
4. Delete the old credential.

## Running it on a schedule

For one tenant you can run the script daily with an Azure Automation runbook or a scheduled task (app-only auth with a certificate), and email the CSV. Remember that the automation's own credential expires too.

If you look after **many tenants** (an MSP, or an IT team with several tenants), a hosted version is in development, **SecretLapse**: one read-only consent per tenant, daily checks, and one email digest plus alerts at 30/14/7/1 days, with nothing to run or maintain. It isn't available yet. Price and waitlist: https://secretlapse.2-29-18-178.sslip.io/?ref=github

## Test

`pwsh ./tests/mock-test.ps1` runs the report against stubbed Graph cmdlets (no tenant needed).

## Licence

MIT. Not affiliated with Microsoft. Issues and pull requests are welcome.
