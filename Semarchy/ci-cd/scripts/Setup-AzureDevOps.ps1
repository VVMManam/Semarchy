<#
.SYNOPSIS
    One-time Azure DevOps setup for the Semarchy SDP CI/CD pipeline.

.DESCRIPTION
    Creates or updates everything the pipeline in ci-cd/azure-pipelines.yml needs.
    Safe to re-run: it adds what is missing and leaves existing items as they are.

      1. Environments   MDM-SDP-Dev, MDM-SDP-Test, MDM-SDP-Prod
      2. Approval check on MDM-SDP-Prod (the approvers you pass in)
      3. Variable groups MDM-SDP-Dev / -Test / -Prod with secret
         SDP_CLIENT_ID and SDP_CLIENT_SECRET (you are prompted for the values)
      4. The pipeline itself, pointing at /ci-cd/azure-pipelines.yml
      5. Grants the pipeline access to the environments and variable groups,
         so the first run does not stop on "needs permission"

    Run it AFTER the ci-cd folder has been pushed to the repository, and
    BEFORE the first pipeline run, so Prod is protected from the very first run.

    Needs a Personal Access Token (PAT) with these scopes:
      Build (Read & execute), Code (Read), Environment (Read & manage),
      Variable Groups (Read, create & manage), Project and Team (Read),
      Identity (Read). Use a "Full access" PAT if you get 401/403 errors.

    Works in Windows PowerShell 5.1 and PowerShell 7+.

.PARAMETER ProdApprovers
    E-mail addresses (users) or group names such as "[Semarchy]\Release Approvers"
    who can approve Prod deployments.

.EXAMPLE
    ./ci-cd/scripts/Setup-AzureDevOps.ps1 -ProdApprovers 'first.last@adports.ae','[Semarchy]\Release Approvers'
#>
[CmdletBinding()]
param(
    [string]   $Organization = 'abudhabiports',
    [string]   $Project      = 'Semarchy',
    [string]   $Repository   = 'Semarchy',
    [string]   $PipelineName = 'Semarchy-SDP-CICD',
    [string]   $YamlPath     = '/ci-cd/azure-pipelines.yml',
    [string]   $Branch       = 'main',

    [Parameter(Mandatory = $true)]
    [string[]] $ProdApprovers,

    [int]      $MinimumApprovers = 1,
    [int]      $ApprovalTimeoutMinutes = 4320,   # 3 days

    # Leave empty to be prompted (input is hidden).
    [string]   $Pat = $env:AZURE_DEVOPS_EXT_PAT
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Environments = @(
    @{ Name = 'MDM-SDP-Dev';  Group = 'MDM-SDP-Dev';  Label = 'Dev';  Approval = $false },
    @{ Name = 'MDM-SDP-Test'; Group = 'MDM-SDP-Test'; Label = 'Test'; Approval = $false },
    @{ Name = 'MDM-SDP-Prod'; Group = 'MDM-SDP-Prod'; Label = 'Prod'; Approval = $true  }
)

# --- Helpers -----------------------------------------------------------------
function ConvertTo-PlainText([Security.SecureString] $Secure) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if ([string]::IsNullOrWhiteSpace($Pat)) {
    $Pat = ConvertTo-PlainText (Read-Host -AsSecureString "Azure DevOps PAT for $Organization")
}
if ([string]::IsNullOrWhiteSpace($Pat)) { throw 'A PAT is required.' }

$auth    = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$Pat"))
$headers = @{ Authorization = "Basic $auth" }
$orgUrl  = "https://dev.azure.com/$Organization"
$projUrl = "$orgUrl/$([Uri]::EscapeDataString($Project))"

function Invoke-Ado {
    param(
        [string] $Method = 'GET',
        [Parameter(Mandatory = $true)] [string] $Uri,
        $Body
    )
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers; ContentType = 'application/json' }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 20
        $params.Body = [Text.Encoding]::UTF8.GetBytes($json)
    }
    try {
        return Invoke-RestMethod @params
    }
    catch {
        $detail = $_.ErrorDetails.Message
        if (-not $detail) { $detail = $_.Exception.Message }
        throw "Azure DevOps API call failed: $Method $Uri`n$detail"
    }
}

function Write-Step([string] $Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }
function Write-Ok([string] $Text)   { Write-Host "   [ok] $Text" -ForegroundColor Green }
function Write-Info([string] $Text) { Write-Host "   $Text" }

# --- 0. Project & repository -------------------------------------------------
Write-Step "Checking project '$Project' and repository '$Repository'"
$proj = Invoke-Ado -Uri "$orgUrl/_apis/projects/$([Uri]::EscapeDataString($Project))?api-version=7.1"
$repo = Invoke-Ado -Uri "$projUrl/_apis/git/repositories/$([Uri]::EscapeDataString($Repository))?api-version=7.1"
Write-Ok "Project id $($proj.id), repository id $($repo.id)"

try {
    $item = Invoke-Ado -Uri ("$projUrl/_apis/git/repositories/$($repo.id)/items?path=" +
        [Uri]::EscapeDataString($YamlPath) + "&versionDescriptor.version=$Branch&versionDescriptor.versionType=branch&api-version=7.1")
    Write-Ok "Found $YamlPath on branch $Branch"
}
catch {
    throw "Could not find $YamlPath on branch '$Branch'. Commit and push the ci-cd folder first."
}

# --- 1. Environments -----------------------------------------------------------
Write-Step 'Environments'
$envIds = @{}
foreach ($e in $Environments) {
    $existing = Invoke-Ado -Uri "$projUrl/_apis/distributedtask/environments?name=$([Uri]::EscapeDataString($e.Name))&api-version=7.1"
    $match = @($existing.value | Where-Object { $_.name -eq $e.Name })
    if ($match.Count -gt 0) {
        $envIds[$e.Name] = $match[0].id
        Write-Ok "$($e.Name) exists (id $($match[0].id))"
    }
    else {
        $created = Invoke-Ado -Method POST -Uri "$projUrl/_apis/distributedtask/environments?api-version=7.1" -Body @{
            name        = $e.Name
            description = "Semarchy SDP $($e.Label) - $(if ($e.Approval) { 'deploys after approval' } else { 'deploys automatically' })"
        }
        $envIds[$e.Name] = $created.id
        Write-Ok "$($e.Name) created (id $($created.id))"
    }
}

# --- 2. Approval check on Prod -----------------------------------------------
Write-Step 'Approval check on MDM-SDP-Prod'
$approvalTypeId = '8C6F20A7-A545-4486-9777-F762FAFE0D4D'   # built-in "Approval" check type

$approverRefs = @()
foreach ($a in $ProdApprovers) {
    $found = Invoke-Ado -Uri ("https://vssps.dev.azure.com/$Organization/_apis/identities?searchFilter=General&filterValue=" +
        [Uri]::EscapeDataString($a) + "&queryMembership=None&api-version=7.1")
    $ids = @($found.value)
    if ($ids.Count -eq 0) { throw "Approver '$a' was not found in organization '$Organization'." }
    $approverRefs += @{ id = $ids[0].id; displayName = $ids[0].providerDisplayName }
    Write-Info "Approver: $a -> $($ids[0].providerDisplayName)"
}

foreach ($e in $Environments) {
    $checks = Invoke-Ado -Uri ("$projUrl/_apis/pipelines/checks/configurations?resourceType=environment&resourceId=" +
        $envIds[$e.Name] + '&api-version=7.1-preview.1')
    $approvals = @($checks.value | Where-Object { $_.type.id -eq $approvalTypeId -or $_.type.name -eq 'Approval' })

    if ($e.Approval) {
        if ($approvals.Count -gt 0) {
            Write-Ok "$($e.Name) already has an approval check - left unchanged (edit it in Pipelines > Environments)."
        }
        else {
            Invoke-Ado -Method POST -Uri "$projUrl/_apis/pipelines/checks/configurations?api-version=7.1-preview.1" -Body @{
                type     = @{ id = $approvalTypeId; name = 'Approval' }
                settings = @{
                    approvers            = $approverRefs
                    executionOrder       = 'anyOrder'
                    minRequiredApprovers = $MinimumApprovers
                    instructions         = 'Approve deployment of the Semarchy SDP model to PRODUCTION (https://adpg-mdm.eu.semarchy.net/).'
                    blockedApprovers     = @()
                    requesterCannotBeApprover = $false
                }
                resource = @{ type = 'environment'; id = "$($envIds[$e.Name])"; name = $e.Name }
                timeout  = $ApprovalTimeoutMinutes
            } | Out-Null
            Write-Ok "Approval check added to $($e.Name) ($MinimumApprovers approver(s) required)"
        }
    }
    elseif ($approvals.Count -gt 0) {
        Write-Host "   [warn] $($e.Name) has an approval check, so it will NOT deploy automatically. Remove it in Pipelines > Environments if that is not intended." -ForegroundColor Yellow
    }
    else {
        Write-Ok "$($e.Name) has no approval check (automatic deployment)"
    }
}

# --- 3. Variable groups ------------------------------------------------------
Write-Step 'Variable groups (SDP technical client credentials)'
$groupIds = @{}
foreach ($e in $Environments) {
    $existing = Invoke-Ado -Uri "$projUrl/_apis/distributedtask/variablegroups?groupName=$([Uri]::EscapeDataString($e.Group))&api-version=7.1"
    $match = @($existing.value | Where-Object { $_.name -eq $e.Group })
    if ($match.Count -gt 0) {
        $groupIds[$e.Group] = $match[0].id
        Write-Ok "$($e.Group) exists (id $($match[0].id)) - values left unchanged"
        continue
    }

    Write-Info "Enter the SDP technical client for $($e.Label) (Platform Administration > Clients, role 'DM Admin')."
    Write-Info "Press Enter to skip and fill in later in Pipelines > Library."
    $clientId = ConvertTo-PlainText (Read-Host -AsSecureString "   $($e.Label) client ID")
    $secret   = ConvertTo-PlainText (Read-Host -AsSecureString "   $($e.Label) client secret")
    if ([string]::IsNullOrWhiteSpace($clientId)) { $clientId = 'CHANGE_ME' }
    if ([string]::IsNullOrWhiteSpace($secret))   { $secret   = 'CHANGE_ME' }

    $created = Invoke-Ado -Method POST -Uri "$orgUrl/_apis/distributedtask/variablegroups?api-version=7.1" -Body @{
        name        = $e.Group
        description = "Semarchy SDP $($e.Label) technical client used by the CI/CD pipeline"
        type        = 'Vsts'
        variables   = @{
            SDP_CLIENT_ID     = @{ value = $clientId; isSecret = $true }
            SDP_CLIENT_SECRET = @{ value = $secret;   isSecret = $true }
        }
        variableGroupProjectReferences = @(
            @{ name = $e.Group; projectReference = @{ id = $proj.id; name = $proj.name } }
        )
    }
    $groupIds[$e.Group] = $created.id
    $note = ''
    if ($clientId -eq 'CHANGE_ME' -or $secret -eq 'CHANGE_ME') { $note = ' - placeholders set, update them before deploying' }
    Write-Ok "$($e.Group) created (id $($created.id))$note"
}

# --- 4. Pipeline ---------------------------------------------------------------
Write-Step "Pipeline '$PipelineName'"
$pipelines = Invoke-Ado -Uri "$projUrl/_apis/pipelines?api-version=7.1&`$top=1000"
$pipeline = @($pipelines.value | Where-Object { $_.name -eq $PipelineName }) | Select-Object -First 1
if ($pipeline) {
    Write-Ok "Exists (id $($pipeline.id))"
}
else {
    $pipeline = Invoke-Ado -Method POST -Uri "$projUrl/_apis/pipelines?api-version=7.1" -Body @{
        name          = $PipelineName
        folder        = '\'
        configuration = @{
            type       = 'yaml'
            path       = $YamlPath
            repository = @{ id = $repo.id; name = $repo.name; type = 'azureReposGit' }
        }
    }
    Write-Ok "Created (id $($pipeline.id))"
}

# --- 5. Authorise the pipeline on environments and variable groups -------------
Write-Step 'Granting the pipeline access to environments and variable groups'
$permBody = @{ pipelines = @(@{ id = $pipeline.id; authorized = $true }) }
foreach ($e in $Environments) {
    Invoke-Ado -Method PATCH -Uri "$projUrl/_apis/pipelines/pipelinePermissions/environment/$($envIds[$e.Name])?api-version=7.1-preview.1" -Body $permBody | Out-Null
    Invoke-Ado -Method PATCH -Uri "$projUrl/_apis/pipelines/pipelinePermissions/variablegroup/$($groupIds[$e.Group])?api-version=7.1-preview.1" -Body $permBody | Out-Null
    Write-Ok "$($e.Name) / $($e.Group)"
}

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Pipeline: $projUrl/_build?definitionId=$($pipeline.id)"
Write-Host "Next: add a build-validation branch policy on '$Branch' (see ci-cd/README.md), then run the pipeline."
