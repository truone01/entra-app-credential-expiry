<#
.SYNOPSIS
  Lists client secrets and certificates of Entra ID app registrations and enterprise apps
  (service principals) that are expired or expire within N days.

.DESCRIPTION
  Read-only. Uses Microsoft Graph PowerShell with the delegated scope Application.Read.All.
  Graph never returns secret values, only metadata (name, key id, start and end dates),
  so this script cannot see or change any secret.

.PARAMETER Days
  Report credentials that expire within this many days (default 30). Expired ones are always included.

.PARAMETER All
  Report every credential, whatever its expiry date.

.PARAMETER IncludeOwners
  Add the owners of each app registration (one extra Graph call per reported app).

.PARAMETER CsvPath
  Also write the report to this CSV file.

.PARAMETER TenantId
  Tenant to connect to (default: your home tenant).

.EXAMPLE
  ./Get-EntraCredentialExpiry.ps1 -Days 60 -IncludeOwners -CsvPath ./expiring.csv

.LINK
  https://github.com/truone01/entra-app-credential-expiry
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 3650)][int]$Days = 30,
    [switch]$All,
    [switch]$IncludeOwners,
    [string]$CsvPath,
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'

foreach ($module in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Module $module is missing. Install it with: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
}

$connectArgs = @{ Scopes = 'Application.Read.All'; NoWelcome = $true }
if ($TenantId) { $connectArgs.TenantId = $TenantId }
Connect-MgGraph @connectArgs

$now = (Get-Date).ToUniversalTime()
$properties = 'id', 'appId', 'displayName', 'passwordCredentials', 'keyCredentials'

function Get-CredentialRows {
    param($Object, [string]$ObjectType)

    $credentials = @()
    foreach ($c in @($Object.PasswordCredentials)) { if ($c) { $credentials += [pscustomobject]@{ Kind = 'Secret'; Cred = $c } } }
    foreach ($c in @($Object.KeyCredentials)) { if ($c) { $credentials += [pscustomobject]@{ Kind = 'Certificate'; Cred = $c } } }

    foreach ($item in $credentials) {
        $c = $item.Cred
        if (-not $c.EndDateTime) { continue }
        $end = ([datetime]$c.EndDateTime).ToUniversalTime()
        $daysLeft = [math]::Floor(($end - $now).TotalDays)
        if (-not $All -and $daysLeft -gt $Days) { continue }
        [pscustomobject]@{
            Status         = if ($end -le $now) { 'Expired' } else { 'Expiring' }
            DaysLeft       = $daysLeft
            ExpiresUtc     = $end.ToString('yyyy-MM-dd HH:mm')
            ObjectType     = $ObjectType
            DisplayName    = $Object.DisplayName
            AppId          = $Object.AppId
            ObjectId       = $Object.Id
            CredentialType = $item.Kind
            CredentialName = $c.DisplayName
            KeyId          = $c.KeyId
            Owners         = ''
        }
    }
}

Write-Verbose 'Reading app registrations...'
$apps = Get-MgApplication -All -Property $properties
Write-Verbose 'Reading enterprise apps (service principals)...'
$servicePrincipals = Get-MgServicePrincipal -All -Property $properties

$rows = @(
    foreach ($a in $apps) { Get-CredentialRows -Object $a -ObjectType 'AppRegistration' }
    foreach ($sp in $servicePrincipals) { Get-CredentialRows -Object $sp -ObjectType 'EnterpriseApp' }
)

if ($IncludeOwners) {
    $ownerCache = @{}
    foreach ($row in $rows | Where-Object ObjectType -eq 'AppRegistration') {
        if (-not $ownerCache.ContainsKey($row.ObjectId)) {
            $owners = Get-MgApplicationOwner -ApplicationId $row.ObjectId -All
            $ownerCache[$row.ObjectId] = ($owners | ForEach-Object {
                    $p = $_.AdditionalProperties
                    if ($p.userPrincipalName) { $p.userPrincipalName } elseif ($p.displayName) { $p.displayName } else { $_.Id }
                }) -join '; '
        }
        $row.Owners = $ownerCache[$row.ObjectId]
    }
}

$rows = @($rows | Sort-Object DaysLeft)
$expired = @($rows | Where-Object Status -eq 'Expired').Count
$expiring = @($rows | Where-Object Status -eq 'Expiring').Count
$window = if ($All) { 'all dates' } else { "within $Days days" }
Write-Host "Expired: $expired   Expiring ($window): $expiring   Apps checked: $($apps.Count) registrations, $($servicePrincipals.Count) enterprise apps"

if ($CsvPath) {
    $rows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding utf8
    Write-Host "Saved $($rows.Count) rows to $CsvPath"
}

$rows | Format-Table Status, DaysLeft, ExpiresUtc, ObjectType, DisplayName, CredentialType, CredentialName, Owners -AutoSize
