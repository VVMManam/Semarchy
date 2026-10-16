<#
.SYNOPSIS
    Deletes a data location on the Semarchy SDP **Test** instance, so the next
    pipeline deploy re-creates it through the data-product route (/dpc) and the
    model appears on the "Data products" page.

.DESCRIPTION
    Safety:
      * Works on the TEST instance only (https://adpg-mdm-test.eu.semarchy.net).
      * Lists the data locations first and shows the one that will be deleted.
      * Refuses to run while that data location is still deploying.
      * Asks you to type  DELETE <name>  before anything is removed.
      * Afterwards checks that the data location is really gone.

    It signs in with an SDP technical client (client ID + secret), the same way
    the Azure DevOps pipeline does - use the Test client from the variable group
    MDM-SDP-Test. The secret is typed in hidden and never written anywhere.

    WARNING: deleting a data location removes its model and ALL ITS DATA on Test.
    This cannot be undone.

    Works in Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    .\Remove-SdpDataLocation.ps1
    (deletes adpg_model1 on Test after asking for the client and confirmation)

.EXAMPLE
    .\Remove-SdpDataLocation.ps1 -DataLocation adpg_model1 -WhatIf
    (only shows what would be deleted)
#>
[CmdletBinding()]
param(
    [string] $DataLocation = 'adpg_model1',
    [string] $ClientId,
    [switch] $WhatIf
)

# ==============================================================================
#  >>> PUT YOUR TEST CLIENT VALUES HERE <<<
#  Paste the TEST technical client's values between the quotes (the same values as
#  SDP_CLIENT_ID / SDP_CLIENT_SECRET in the Azure DevOps variable group MDM-SDP-Test).
#  Leave the placeholders as they are to be asked for the values when the script runs.
#
#  !! Do NOT commit this file with real values in it. Put the placeholders back
#  !! (or delete your local copy) when you are done.
# ==============================================================================
$TestClientId     = '<PUT-TEST-CLIENT-ID-HERE>'
$TestClientSecret = '<PUT-TEST-CLIENT-SECRET-HERE>'

#  OR use an API key instead of the client (if you fill this in, the client ID /
#  secret above are not used). Sent as the 'API-Key' header.
$TestApiKey       = '<PUT-TEST-API-KEY-HERE>'
# ==============================================================================

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Fixed to TEST --------------------------------------------------------------
$InstanceUrl = 'https://adpg-mdm-test.eu.semarchy.net'
$TokenUrl    = 'https://eu.semarchy.net/auth/realms/adpg-mdm-test/protocol/openid-connect/token'
$ListUrl     = "$InstanceUrl/dm/api/rest/data-locations"

function Write-Title([string] $t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Write-Ok([string] $t)    { Write-Host "   [ok] $t" -ForegroundColor Green }
function Write-Bad([string] $t)   { Write-Host "   [!!] $t" -ForegroundColor Red }

function Get-HttpError($err) {
    # Returns "status: body" for Windows PowerShell 5.1 and PowerShell 7.
    $code = $null; $body = $null
    try { $code = [int]$err.Exception.Response.StatusCode } catch {}
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) { $body = $err.ErrorDetails.Message }
    elseif ($err.Exception.Response -and ($err.Exception.Response | Get-Member -Name GetResponseStream -ErrorAction SilentlyContinue)) {
        try { $body = (New-Object IO.StreamReader($err.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
    }
    if (-not $body) { $body = $err.Exception.Message }
    if ($body.Length -gt 400) { $body = $body.Substring(0, 400) + '...' }
    return [pscustomobject]@{ Code = $code; Body = $body }
}

function Invoke-Api([string] $Method, [string] $Uri, [string] $Token, [string] $Body = $null, [string] $ApiKey = $null) {
    # Sends one request with the Bearer token and follows redirects ITSELF, re-adding
    # the token each time. (Invoke-WebRequest in Windows PowerShell 5.1 drops the
    # Authorization header when it follows a redirect.)
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    try {
        $current = $Uri
        for ($hop = 0; $hop -le 5; $hop++) {
            $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method.ToUpper())), $current)
            if ($ApiKey) { [void]$req.Headers.TryAddWithoutValidation('API-Key', $ApiKey) }
            else { $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token) }
            [void]$req.Headers.TryAddWithoutValidation('Accept', 'application/json')
            if ($null -ne $Body) { $req.Content = New-Object System.Net.Http.StringContent($Body, [Text.Encoding]::UTF8, 'application/json') }
            $resp = $client.SendAsync($req).GetAwaiter().GetResult()
            $code = [int]$resp.StatusCode
            $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ($code -ge 300 -and $code -lt 400 -and $resp.Headers.Location) {
                $next = $resp.Headers.Location
                if (-not $next.IsAbsoluteUri) { $next = New-Object Uri((New-Object Uri($current)), $next) }
                Write-Host "   -> redirected ($code) to $next"
                $current = $next.AbsoluteUri
                continue
            }
            if ($text -and $text.Length -gt 400) { $text = $text.Substring(0, 400) + '...' }
            return [pscustomobject]@{ Code = $code; Body = $text; Uri = $current }
        }
        return [pscustomobject]@{ Code = 0; Body = 'Too many redirects'; Uri = $current }
    } finally { $client.Dispose() }
}

function Get-Locations([hashtable] $Headers) {
    $r = Invoke-RestMethod -Method Get -Uri $ListUrl -Headers $Headers
    if ($r -is [string]) { throw "Unexpected (non-JSON) response from $ListUrl" }
    return @($r | ForEach-Object { $_ })
}

Write-Host "Semarchy SDP - delete data location '$DataLocation' on TEST ($InstanceUrl)" -ForegroundColor Yellow

# --- 1. Credentials --------------------------------------------------------------
$useApiKey = -not ([string]::IsNullOrWhiteSpace($TestApiKey) -or $TestApiKey -match '^<PUT-.*-HERE>$')
$tok = [pscustomobject]@{ access_token = $null }
if ($useApiKey) {
    Write-Title 'Using the API key from the top of the script'
    $apiKeyValue = $TestApiKey.Trim()
    $headers = @{ 'API-Key' = $apiKeyValue; Accept = 'application/json' }
    Write-Ok "API key set ($($apiKeyValue.Substring(0, [Math]::Min(4, $apiKeyValue.Length)))***)."
} else {
Write-Title 'Sign in with the Test technical client (MDM-SDP-Test variable group)'
function Test-Placeholder([string] $v) { return [string]::IsNullOrWhiteSpace($v) -or $v -match '^<PUT-.*-HERE>$' }

if ([string]::IsNullOrWhiteSpace($ClientId) -and -not (Test-Placeholder $TestClientId)) {
    $ClientId = $TestClientId.Trim()
    Write-Host "   Using client ID from the top of the script: $($ClientId.Substring(0, [Math]::Min(4, $ClientId.Length)))***"
}
if ([string]::IsNullOrWhiteSpace($ClientId)) { $ClientId = Read-Host '   Test client ID' }

if (-not (Test-Placeholder $TestClientSecret)) {
    $secret = $TestClientSecret.Trim()
    Write-Host '   Using client secret from the top of the script.'
} else {
    $secure = Read-Host '   Test client secret (hidden)' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $secret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if ([string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($secret)) { Write-Bad 'Client ID and secret are required.'; exit 1 }

try {
    $tok = Invoke-RestMethod -Method Post -Uri $TokenUrl -ContentType 'application/x-www-form-urlencoded' -Body @{
        grant_type = 'client_credentials'; client_id = $ClientId; client_secret = $secret }
} catch {
    $e = Get-HttpError $_
    Write-Bad "Sign-in failed ($($e.Code)): $($e.Body)"
    Write-Host '   Check the client ID/secret are the TEST ones (Platform administration > Clients on Test).'
    exit 1
} finally { $secret = $null }
$headers = @{ Authorization = "Bearer $($tok.access_token)"; Accept = 'application/json' }
$apiKeyValue = $null
Write-Ok 'Signed in.'
}

# --- 2. Show what is there --------------------------------------------------------
Write-Title 'Data locations on TEST'
try { $locations = Get-Locations $headers }
catch { $e = Get-HttpError $_; Write-Bad "Could not list data locations ($($e.Code)): $($e.Body)"; exit 1 }
$locations | Select-Object name, status, modelName, dataSource, deploymentDate | Format-Table -AutoSize | Out-String | Write-Host

$target = @($locations | Where-Object { "$($_.name)" -eq $DataLocation }) | Select-Object -First 1
if (-not $target) { Write-Ok "Data location '$DataLocation' does not exist on Test - nothing to delete."; exit 0 }

$status = "$($target.status)"
if ($status -ne 'DL_READY' -and $status -notmatch 'ERROR|FAIL') {
    Write-Bad "'$DataLocation' is still busy (status '$status'). Wait until it is DL_READY (or failed), then run this again."
    exit 1
}

if ($WhatIf) {
    Write-Host "   WhatIf: would delete '$DataLocation' (model $($target.modelName), status $status). Nothing was changed." -ForegroundColor Yellow
    exit 0
}

# --- 3. Confirm --------------------------------------------------------------------
Write-Title 'Confirm'
Write-Host "   This permanently deletes '$DataLocation' on TEST, including its model and ALL its data." -ForegroundColor Yellow
$answer = Read-Host "   Type  DELETE $DataLocation  to continue"
if ($answer -cne "DELETE $DataLocation") { Write-Host '   Cancelled - nothing was changed.'; exit 0 }

# --- 4. Delete ---------------------------------------------------------------------
Write-Title 'Deleting'
$attempts = @(
    @{ Method = 'Post';   Uri = "$ListUrl/$DataLocation/delete" },
    @{ Method = 'Delete'; Uri = "$ListUrl/$DataLocation/delete" },
    @{ Method = 'Delete'; Uri = "$ListUrl/$DataLocation" }
)
$sent = $false
foreach ($a in $attempts) {
    Write-Host "   $($a.Method.ToUpper()) $($a.Uri)"
    try { $r = Invoke-Api -Method $a.Method -Uri $a.Uri -Token $tok.access_token -ApiKey $apiKeyValue }
    catch { Write-Bad "Request failed: $($_.Exception.Message)"; exit 1 }
    if ($r.Code -ge 200 -and $r.Code -lt 300) {
        Write-Ok "Accepted (HTTP $($r.Code)). $($r.Body)"
        $sent = $true
        break
    }
    if ($r.Code -in 404, 405) { Write-Host "   -> HTTP $($r.Code), trying the next form ..."; continue }
    Write-Bad "HTTP $($r.Code): $($r.Body)"
    if ($r.Code -eq 401) {
        Write-Host '   The instance did not accept the sign-in for this call. Send this output to your Semarchy admin /'
        Write-Host "   Semarchy support and ask them to delete '$DataLocation' on Test (or register it as a data product)."
    } elseif ($r.Code -eq 403) {
        Write-Host '   This client is signed in but not allowed to delete data locations. Ask your Semarchy platform admin /'
        Write-Host "   Semarchy support to delete '$DataLocation' on Test (or to register it as a data product)."
    } elseif ($r.Code -eq 400) {
        Write-Host '   The endpoint expects extra options. Check Documentation > API reference on Test for the data-location delete call.'
    }
    exit 1
}
if (-not $sent) { Write-Bad 'No delete endpoint accepted the request (all returned 404/405). Check Documentation > API reference on Test.'; exit 1 }

# --- 5. Verify -----------------------------------------------------------------------
Write-Title 'Checking it is gone'
$deadline = (Get-Date).AddMinutes(5)
do {
    Start-Sleep -Seconds 10
    try { $locations = Get-Locations $headers } catch { continue }
    $still = @($locations | Where-Object { "$($_.name)" -eq $DataLocation }) | Select-Object -First 1
    if (-not $still) {
        Write-Ok "'$DataLocation' has been deleted from Test."
        Write-Host ''
        Write-Host 'Next: run the Azure DevOps pipeline with only "Deploy to Test" ticked. It re-creates the data location'
        Write-Host 'through the data-product route; when it reaches DL_READY, "ADPG Data Model" appears under Data products.'
        exit 0
    }
    Write-Host "   $(Get-Date -Format HH:mm:ss)  still present (status $($still.status)) - waiting ..."
} while ((Get-Date) -lt $deadline)

Write-Bad "'$DataLocation' is still listed after 5 minutes. Check Log Explorer on Test or run this script again later."
exit 1
