# Runs the report against stubbed Graph cmdlets (no tenant needed): pwsh ./tests/mock-test.ps1
$ErrorActionPreference = 'Stop'
function Get-Module { param([switch]$ListAvailable, $Name) [pscustomobject]@{ Name = $Name } }
function Connect-MgGraph { param($Scopes, $TenantId, [switch]$NoWelcome) }
$n = (Get-Date).ToUniversalTime()
function New-Obj($id, $name, $pw, $key) { [pscustomobject]@{ Id = $id; AppId = "app-$id"; DisplayName = $name; PasswordCredentials = $pw; KeyCredentials = $key } }
function Cred($name, $days) { [pscustomobject]@{ DisplayName = $name; KeyId = [guid]::NewGuid(); EndDateTime = $n.AddDays($days) } }
function Get-MgApplication { param([switch]$All, $Property)
    New-Obj 'a1' 'Payroll sync' @((Cred 'prod' 5), (Cred 'old' -3)) @()
    New-Obj 'a2' 'Backup job' @((Cred 'long' 400)) @((Cred 'cert' 20))
    New-Obj 'a3' 'No creds' @() @()
}
function Get-MgServicePrincipal { param([switch]$All, $Property)
    New-Obj 's1' 'SAML app' @() @((Cred 'saml signing' 10))
    New-Obj 's2' 'Plain SP' $null $null
}
function Get-MgApplicationOwner { param($ApplicationId, [switch]$All)
    [pscustomobject]@{ Id = 'u1'; AdditionalProperties = @{ userPrincipalName = 'admin@contoso.example' } }
}
$csv = Join-Path ([IO.Path]::GetTempPath()) "entra-expiry-test.csv"
& "$PSScriptRoot/../Get-EntraCredentialExpiry.ps1" -Days 30 -IncludeOwners -CsvPath $csv | Out-Null
$rows = Import-Csv $csv
$fail = 0
function Check($cond, $msg) { if ($cond) { "ok   $msg" } else { "FAIL $msg"; $script:fail++ } }
Check ($rows.Count -eq 4) "4 rows within 30 days (got $($rows.Count))"
Check ($rows[0].Status -eq 'Expired' -and $rows[0].CredentialName -eq 'old') 'expired first'
Check (-not ($rows | Where-Object CredentialName -eq 'long')) '400-day secret excluded'
Check (($rows | Where-Object CredentialName -eq 'cert').CredentialType -eq 'Certificate') 'certificate typed'
Check (($rows | Where-Object CredentialName -eq 'saml signing').ObjectType -eq 'EnterpriseApp') 'service principal included'
Check (($rows | Where-Object CredentialName -eq 'prod').Owners -eq 'admin@contoso.example') 'owners resolved'
& "$PSScriptRoot/../Get-EntraCredentialExpiry.ps1" -All -CsvPath $csv | Out-Null
Check ((Import-Csv $csv).Count -eq 5) 'all credentials with -All'
Remove-Item $csv
if ($fail) { exit 1 }
