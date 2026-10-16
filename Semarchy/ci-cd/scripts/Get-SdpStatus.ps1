<#
.SYNOPSIS
    Read-only check of what a Semarchy SDP instance actually contains after a deploy.

.DESCRIPTION
    Signs in with the pipeline's technical client (SDP_CLIENT_ID / SDP_CLIENT_SECRET,
    OAuth2 client credentials - the same way the Design CLI does) and lists the
    data locations on the instance with their status and deployed model edition.
    Prints the result to the log and to the run's Summary tab.

    It changes nothing on the instance and never fails the pipeline: any problem
    is reported as a warning.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    $env:SDP_CLIENT_ID = '...'; $env:SDP_CLIENT_SECRET = '...'
    ./Get-SdpStatus.ps1 -InstanceUrl https://adpg-mdm-test.eu.semarchy.net -DataLocation adpg_model1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $InstanceUrl,
    [string] $DataLocation,
    [string] $EnvironmentName = '',

    # Semarchy finishes a deployment in the background (DEPLOYING_ME_AND_JOBS,
    # then INSTALL_JOB_RUNNING, ...). Wait up to this many minutes for the data
    # location to reach DL_READY (0 = don't wait).
    [int] $WaitMinutes = 45,
    [int] $PollSeconds = 30,

    # When the deploy step hit a gateway timeout it sets SDP_DEPLOY_PENDING=true and
    # SDP_DEPLOY_STARTED. This check then waits for a deployment newer than that
    # start time to reach DL_READY, and FAILS the run if it does not.
    [string] $DeployStarted = $env:SDP_DEPLOY_STARTED,
    [switch] $VerifyPending = ($env:SDP_DEPLOY_PENDING -eq 'true')
)

$ErrorActionPreference = 'Stop'
if ($DeployStarted -match '^\$\(.+\)$') { $DeployStarted = '' }
$startedAt = $null
if ($DeployStarted) { try { $startedAt = ([DateTimeOffset]::Parse($DeployStarted)).UtcDateTime.AddMinutes(-2) } catch { $startedAt = $null } }
function Get-DeployDate($dl) {
    try { return ([DateTimeOffset]::Parse("$($dl.deploymentDate)")).UtcDateTime } catch { return [datetime]::MinValue }
}
$exitCode = 0
function Test-InProgress([string] $Status) {
    # DEPLOYING_ME_AND_JOBS, INSTALL_JOB_RUNNING, ... = still working.
    # DL_READY = done. Anything mentioning ERROR/FAIL = stopped with a problem.
    return ($Status -ne 'DL_READY') -and ($Status -notmatch 'ERROR|FAIL') -and ($Status -ne '')
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Warn([string] $Message) {
    if ($env:TF_BUILD) { Write-Host "##vso[task.logissue type=warning]$Message" }
    else { Write-Host "WARNING: $Message" -ForegroundColor Yellow }
}

try {
    $InstanceUrl = $InstanceUrl.TrimEnd('/')
    $uri = [Uri] $InstanceUrl
    # Same rule as the Design CLI: <env>.<host>  ->  token at https://<host>/auth/realms/<env>
    $dot = $uri.Host.IndexOf('.')
    if ($dot -lt 1) { throw "Cannot read the tenant name from '$InstanceUrl'." }
    $realm   = $uri.Host.Substring(0, $dot)
    $authUrl = "$($uri.Scheme)://$($uri.Host.Substring($dot + 1))/auth/realms/$realm/protocol/openid-connect/token"

    if ([string]::IsNullOrWhiteSpace($env:SDP_CLIENT_ID) -or [string]::IsNullOrWhiteSpace($env:SDP_CLIENT_SECRET)) {
        throw 'SDP_CLIENT_ID / SDP_CLIENT_SECRET are not set.'
    }

    Write-Host "Signing in to $authUrl as client $($env:SDP_CLIENT_ID.Substring(0, [Math]::Min(4, $env:SDP_CLIENT_ID.Length)))***"
    $token = Invoke-RestMethod -Method Post -Uri $authUrl -ContentType 'application/x-www-form-urlencoded' -Body @{
        grant_type    = 'client_credentials'
        client_id     = $env:SDP_CLIENT_ID
        client_secret = $env:SDP_CLIENT_SECRET
    }
    $headers = @{ Authorization = "Bearer $($token.access_token)"; Accept = 'application/json' }

    $listUrl = "$InstanceUrl/dm/api/rest/data-locations"
    function Get-Locations {
        # Pipe through ForEach-Object so a JSON array is unrolled into its items
        # (PowerShell 7 returns the whole array as one object otherwise).
        $r = Invoke-RestMethod -Method Get -Uri $listUrl -Headers $headers
        if ($r -is [string]) { throw "Unexpected (non-JSON) response from $listUrl" }
        return @($r | ForEach-Object { $_ })
    }

    Write-Host "GET $listUrl"
    $locations = Get-Locations

    if ($DataLocation -and $WaitMinutes -gt 0) {
        $deadline = (Get-Date).AddMinutes($WaitMinutes)
        while ($true) {
            $dl = @($locations | Where-Object { "$($_.name)" -eq $DataLocation }) | Select-Object -First 1
            $isNew = (-not $VerifyPending) -or (-not $startedAt) -or ($dl -and (Get-DeployDate $dl) -ge $startedAt)
            if ($dl -and $isNew -and -not (Test-InProgress "$($dl.status)")) { break }
            if (-not $dl -and -not $VerifyPending) { break }
            if ((Get-Date) -ge $deadline) {
                Write-Warn "'$DataLocation' is still '$($dl.status)' after $WaitMinutes minutes. Semarchy is still processing the deployment; it appears in Data products once it reaches DL_READY."
                break
            }
            $state = if ($dl) { "status: $($dl.status), deployed: $($dl.deploymentDate)" } else { 'not created yet' }
            Write-Host "$(Get-Date -Format 'HH:mm:ss')  '$DataLocation' $state - waiting $PollSeconds s ..."
            Start-Sleep -Seconds $PollSeconds
            $locations = Get-Locations
        }
    }

    Write-Host ""
    Write-Host "Data locations on $InstanceUrl : $($locations.Count)"
    Write-Host ($locations | ConvertTo-Json -Depth 6)

    $md = New-Object System.Text.StringBuilder
    [void]$md.AppendLine("### Semarchy instance check $EnvironmentName")
    [void]$md.AppendLine("Instance: $InstanceUrl  ")
    [void]$md.AppendLine("Data locations found: **$($locations.Count)**")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('```json')
    [void]$md.AppendLine(($locations | ConvertTo-Json -Depth 6))
    [void]$md.AppendLine('```')

    if ($DataLocation) {
        $found = @($locations | Where-Object { "$($_.name)" -eq $DataLocation })
        if ($found.Count -eq 0) {
            Write-Warn "Data location '$DataLocation' was NOT found on $InstanceUrl after the deploy. The deployment was accepted but did not create it - check Log Explorer on the instance."
            [void]$md.AppendLine("**:warning: Data location ``$DataLocation`` not found.**")
            if ($VerifyPending) {
                Write-Host "##vso[task.logissue type=error]The deploy step timed out at the gateway and data location '$DataLocation' was not created."
                $exitCode = 1
            }
        } else {
            $st = "$($found[0].status)"
            Write-Host "Data location '$DataLocation' exists. Status: $st, model: $($found[0].modelName), deployed: $($found[0].deploymentDate)"
            [void]$md.AppendLine("Data location ``$DataLocation``: status **$st**")
            if (Test-InProgress $st) {
                Write-Warn "Data location '$DataLocation' is still being installed on the instance (status '$st'). It becomes visible in Data products when the status reaches DL_READY."
            } elseif ($st -ne 'DL_READY') {
                Write-Warn "Data location '$DataLocation' status is '$st' (expected DL_READY). Check Log Explorer on the instance for the deployment error."
            }
            if ($VerifyPending) {
                $isNew = (-not $startedAt) -or ((Get-DeployDate $found[0]) -ge $startedAt)
                if ($st -eq 'DL_READY' -and $isNew) {
                    Write-Host "The deployment that timed out at the gateway has completed: '$DataLocation' is DL_READY (deployed $($found[0].deploymentDate))."
                    [void]$md.AppendLine("Deployment completed after the gateway timeout.")
                } else {
                    $why = if (-not $isNew) { "no new deployment was registered after $DeployStarted" } else { "status is '$st'" }
                    Write-Host "##vso[task.logissue type=error]The deploy step timed out at the gateway and the deployment did not complete ($why). Check Log Explorer on the instance, then run the pipeline again."
                    $exitCode = 1
                }
            }
        }
    }

    if ($env:TF_BUILD -and $env:AGENT_TEMPDIRECTORY) {
        $file = Join-Path $env:AGENT_TEMPDIRECTORY "sdp-status-$EnvironmentName.md"
        [IO.File]::WriteAllText($file, $md.ToString())
        Write-Host "##vso[task.uploadsummary]$file"
    }
}
catch {
    $detail = $_.ErrorDetails.Message
    if (-not $detail) { $detail = $_.Exception.Message }
    Write-Warn "Instance check could not complete: $detail"
    if ($VerifyPending) {
        Write-Host "##vso[task.logissue type=error]Could not confirm the deployment that timed out at the gateway: $detail"
        $exitCode = 1
    }
}
exit $exitCode
