<#
.SYNOPSIS
    Runs the Semarchy Design CLI (sem-design) for the Azure DevOps pipeline.

.DESCRIPTION
    Wraps Semarchy Design CLI 2.x `sem-design data-product build` and
    `sem-design data-product deploy` so that the pipeline step fails reliably:
      * on a non-zero exit code, and
      * when the CLI prints a failure message ("=> FAILED", "Error executing
        command", ...). Design CLI 2.x can exit 0 on some failures.
      * when the CLI does not print its success message ("Build successful" /
        "Deployment successful").
    Also checks the inputs up front so misconfiguration gives a clear message
    instead of an obscure CLI error.

    Client credentials are read from the SDP_CLIENT_ID / SDP_CLIENT_SECRET
    environment variables (mapped from the pipeline's variable group), never
    from parameters, so they are not written to logs.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    ./Invoke-SemDesign.ps1 -Action Build -RootFolder src

.EXAMPLE
    $env:SDP_CLIENT_ID = '...'; $env:SDP_CLIENT_SECRET = '...'
    ./Invoke-SemDesign.ps1 -Action Deploy -RootFolder src `
        -InstanceUrl https://adpg-mdm-dev.eu.semarchy.net `
        -DataSource datasource1 -DataLocation adpg_model1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Build', 'Deploy')]
    [string] $Action,

    # Data product folder (contains the DataProductProfile and all .seml files)
    [string] $RootFolder = 'src',

    [string] $InstanceUrl,
    [string] $DataSource,
    [string] $DataLocation,

    # Optional. Base URL the data product is deployed to, e.g.
    # https://<tenant-url>/dpc  (passed as --overwrite-deployment-url).
    # When empty, the CLI default (<InstanceUrl>/dm/...) is used.
    [string] $DeploymentUrl
)

$ErrorActionPreference = 'Continue'

function Write-PipelineError([string] $Message) {
    if ($env:TF_BUILD) { Write-Host "##vso[task.logissue type=error]$Message" }
    else { Write-Host "ERROR: $Message" -ForegroundColor Red }
}

function Test-Missing([string] $Value) {
    # Unset pipeline variables are passed through literally as "$(NAME)".
    return [string]::IsNullOrWhiteSpace($Value) -or
           $Value -match '^\$\(.+\)$' -or
           $Value -match 'CHANGE_ME'
}

# --- Pre-flight checks -------------------------------------------------------
if (-not (Get-Command 'sem-design' -ErrorAction SilentlyContinue)) {
    Write-PipelineError "sem-design is not on PATH. Run the 'Install Semarchy Design CLI' step first."
    exit 1
}

if (-not (Test-Path -Path $RootFolder -PathType Container)) {
    Write-PipelineError "Root folder '$RootFolder' not found (working directory: $(Get-Location))."
    exit 1
}

$cliArgs = @()
$display = ''

if ($Action -eq 'Build') {
    $cliArgs = @('data-product', 'build', '--data-product-folder', $RootFolder)
    $display = "sem-design data-product build --data-product-folder $RootFolder"
}
else {
    $problems = @()
    if (Test-Missing $InstanceUrl)  { $problems += 'InstanceUrl' }
    elseif ($InstanceUrl -match '/dm/?$') {
        $problems += "InstanceUrl ends in /dm; Design CLI 2.x expects https://<tenant-url> without /dm"
    }
    if (Test-Missing $DataSource)   { $problems += 'DataSource' }
    if (Test-Missing $DataLocation) { $problems += 'DataLocation' }
    if ($DeploymentUrl -match '^\$\(.+\)$') { $DeploymentUrl = '' }   # pipeline variable not set
    if ($DeploymentUrl -match 'CHANGE_ME') { $problems += 'DeploymentUrl' }
    if (Test-Missing $env:SDP_CLIENT_ID)     { $problems += 'SDP_CLIENT_ID (variable group secret)' }
    if (Test-Missing $env:SDP_CLIENT_SECRET) { $problems += 'SDP_CLIENT_SECRET (variable group secret)' }
    if ($problems.Count -gt 0) {
        Write-PipelineError ("Deployment settings missing or still placeholders: " + ($problems -join ', ') +
            ". See ci-cd/README.md.")
        exit 1
    }

    $cliArgs = @(
        'data-product', 'deploy',
        '--data-product-folder', $RootFolder,
        '--data-source',   $DataSource,
        '--data-location', $DataLocation,
        '--instance-url',  $InstanceUrl,
        '--client-id',     $env:SDP_CLIENT_ID,
        '--client-secret', $env:SDP_CLIENT_SECRET
    )
    if (-not [string]::IsNullOrWhiteSpace($DeploymentUrl)) {
        $cliArgs += @('--overwrite-deployment-url', $DeploymentUrl.TrimEnd('/'))
    }
    $display = "sem-design data-product deploy --data-product-folder $RootFolder --data-source $DataSource " +
               "--data-location $DataLocation --instance-url $InstanceUrl --client-id *** --client-secret ***"
    if (-not [string]::IsNullOrWhiteSpace($DeploymentUrl)) {
        $display += " --overwrite-deployment-url $($DeploymentUrl.TrimEnd('/'))"
    }
}

# --- Run ---------------------------------------------------------------------
Write-Host "> $display"
if ($Action -eq 'Deploy') {
    # Remember when this deployment started, for the post-deploy check.
    $startedUtc = (Get-Date).ToUniversalTime().ToString('o')
    if ($env:TF_BUILD) { Write-Host "##vso[task.setvariable variable=SDP_DEPLOY_STARTED]$startedUtc" }
}
$lines = New-Object System.Collections.Generic.List[string]

& sem-design @cliArgs 2>&1 | ForEach-Object {
    $line = "$_"
    $lines.Add($line)
    Write-Host $line
}
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 0 }

# Design CLI 2.x can exit with code 0 even when a command fails (settings or
# login errors, unexpected exceptions). So a step only passes when the exit code
# is 0, no failure message was printed, AND the CLI printed its success message.
$failurePatterns = @('=>\s*FAILED', '^Error executing command', '^Build failed', 'Deployment failed',
                     'Problem during import', 'Unexpected http response', 'Failed to fetch')
$successMarker = 'Build successful'
if ($Action -eq 'Deploy') { $successMarker = 'Deployment successful' }

$failureLines = @($lines | Where-Object { $l = $_; ($failurePatterns | Where-Object { $l -match $_ }).Count -gt 0 })
$succeeded    = ($lines | Where-Object { $_ -match [regex]::Escape($successMarker) }).Count -gt 0

# A gateway timeout (502/503/504) means the instance's front door stopped waiting,
# not that Semarchy rejected the model: the deployment usually carries on in the
# background. Hand over to the post-deploy check, which waits for the data
# location to finish and fails the run if the deployment does not complete.
$gatewayTimeout = @($lines | Where-Object { $_ -match 'code:\s*(502|503|504)\b' -or $_ -match 'Gateway Time-?out' }).Count -gt 0
if ($Action -eq 'Deploy' -and $gatewayTimeout) {
    $msg = "The instance answered with a gateway timeout (see above). Semarchy normally keeps deploying in the background; " +
           "the 'Check what is on ...' step will wait for it and fail the run if it does not complete."
    if ($env:TF_BUILD) {
        Write-Host "##vso[task.logissue type=warning]$msg"
        Write-Host "##vso[task.setvariable variable=SDP_DEPLOY_PENDING]true"
    } else { Write-Host "WARNING: $msg" -ForegroundColor Yellow }
    exit 0
}

if ($exitCode -ne 0 -or $failureLines.Count -gt 0 -or -not $succeeded) {
    if ($exitCode -eq 0) { $exitCode = 1 }
    $reason = "exit code $exitCode"
    if ($failureLines.Count -gt 0) { $reason = "$reason; " + $failureLines[0] }
    elseif (-not $succeeded)       { $reason = "$reason; '$successMarker' was not reported" }
    Write-PipelineError "sem-design $Action failed ($reason). See the log above for details."
    exit $exitCode
}

Write-Host "sem-design $Action completed successfully."
exit 0
