<#
.SYNOPSIS
    Lists and checks every Semarchy model element in the project folder before
    it is built and deployed.

.DESCRIPTION
    `sem-design data-product deploy --data-product-folder src` (Design CLI 2.x)
    deploys the WHOLE data product under the folder as one model edition: the
    data model (data product profile,
    entities, references, lists of values, diagrams), match rules (inside each
    entity's matcher), survivorship rules, duplicate managers, validations and
    enrichers, workflows and jobs, applications, forms, collection views, display
    cards, business views, steppers, action sets, named queries and privilege
    grants.

    This script makes that visible and catches files that would silently NOT be
    part of the deployment:

      ERROR  (always fails the step)
        - a .seml file with no top-level `_type`
        - unresolved git merge-conflict markers (<<<<<<<, =======, >>>>>>>)
        - two elements with the same package + name + type
        - not exactly one DataProductProfile, or no entities
        - Design CLI 1.x element types that 2.x does not recognise
          (Model, ModelJob, ModelPrivGrant, ModelVariable). Run
          scripts/Convert-ToDataProduct.ps1 to convert them.

      WARNING (fails the step only with -Strict)
        - files in the model folder that are not *.seml (e.g. *.seml.disabled):
          these are excluded from the build and deploy
        - file name suffix does not match `_type` (e.g. X.Modelob.seml holding a
          ModelJob, or ContactPurposeForm.seml with no .Form suffix)
        - a fuzzy-matched entity with no match rules, or no ID survivorship rule

    It prints an inventory table, writes model-inventory.md / .json to
    -OutputFolder, and (on Azure DevOps) attaches the table to the run summary.

    Compatible with Windows PowerShell 5.1 and PowerShell 7+.

.EXAMPLE
    ./ci-cd/scripts/Test-ModelInventory.ps1 -RootFolder src
#>
[CmdletBinding()]
param(
    [string] $RootFolder = 'src',
    [switch] $Strict,
    [string] $SummaryTitle = 'Semarchy model inventory',
    [string] $OutputFolder
)

$ErrorActionPreference = 'Stop'
$onAdo = [bool] $env:TF_BUILD

function Write-Issue([string] $Level, [string] $Message) {
    if ($onAdo) { Write-Host "##vso[task.logissue type=$Level]$Message" }
    else {
        $color = 'Yellow'; if ($Level -eq 'error') { $color = 'Red' }
        Write-Host ("{0}: {1}" -f $Level.ToUpper(), $Message) -ForegroundColor $color
    }
}

if (-not (Test-Path -Path $RootFolder -PathType Container)) {
    Write-Issue 'error' "Root folder '$RootFolder' not found."
    exit 1
}
$root = (Resolve-Path $RootFolder).Path

# ---------------------------------------------------------------------------
# Element types, grouped the way people talk about them
# ---------------------------------------------------------------------------
$categories = [ordered]@{
    'Data model'           = @('DataProductProfile', 'Entity', 'Reference', 'LOVType', 'ModelDiagram', 'DataRetentionPolicy', 'DynamicVariable')
    'Match & merge'        = @('(match rules)', 'IDSurvivorshipRule', 'StandardSurvivorshipRule', 'DupsManager')
    'Data quality'         = @('SemQLValidation', 'PluginValidation', 'SemQLEnricher', 'JavaPluginEnricher', 'RestClientEnricher')
    'Flows & jobs'         = @('Workflow', 'CertificationJob')
    'Applications & UI'    = @('Application', 'Form', 'CollectionView', 'DisplayCard', 'BusinessView', 'Stepper', 'ActionSet')
    'Queries & security'   = @('NamedQuery', 'DataProductPrivGrant')
}

function Get-RelPath([string] $Full) {
    return $Full.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-TopValue([string[]] $Lines, [string] $Key) {
    foreach ($l in $Lines) {
        if ($l -match ('^' + [regex]::Escape($Key) + ':\s*(.*?)\s*$')) {
            return $Matches[1].Trim("'", '"')
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------
$errors   = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$counts   = @{}
$elements = New-Object System.Collections.Generic.List[object]
$excluded = New-Object System.Collections.Generic.List[string]

$allFiles = Get-ChildItem -Path $root -Recurse -File | Sort-Object FullName
foreach ($f in $allFiles) {
    $rel = Get-RelPath $f.FullName
    if ($f.Name -notlike '*.seml') {
        $excluded.Add($rel)
        continue
    }

    $text  = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $lines = $text -split "`r?`n"
    $type  = Get-TopValue $lines '_type'
    $name  = Get-TopValue $lines '_name'
    $pkg   = Get-TopValue $lines '_package'

    $conflictLines = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(<{7}|={7}|>{7})(\s|$)') { $conflictLines += ($i + 1) }
    }
    if ($conflictLines.Count -gt 0) {
        $errors.Add("$rel contains unresolved git merge-conflict markers (line(s) $($conflictLines -join ', ')). Resolve the conflict before deploying.")
    }

    if (-not $type) {
        $errors.Add("$rel has no top-level _type - Semarchy cannot load it.")
        continue
    }

    if (-not $counts.ContainsKey($type)) { $counts[$type] = 0 }
    $counts[$type]++

    if ($f.Name -notlike "*.$type.seml") {
        $warnings.Add("$rel contains a '$type' but its file name does not end in '.$type.seml'. Rename it to '$name.$type.seml' so Design XP and the CLI treat it consistently.")
    }

    $matchRules = 0
    $hasMatcher = $false
    if ($type -eq 'Entity') {
        $hasMatcher = [bool]($lines | Where-Object { $_ -match '^matcher:' })
        $matchRules = @($lines | Where-Object { $_ -match '^\s*(-\s*)?_type:\s*\w*MatchRule\s*$' }).Count
    }

    $elements.Add([pscustomobject]@{
        Path       = $rel
        Type       = $type
        Name       = $name
        Package    = $pkg
        Entity     = Get-TopValue $lines 'entity'
        EntityType = Get-TopValue $lines 'entityType'
        HasMatcher = $hasMatcher
        MatchRules = $matchRules
    })
}

$totalMatchRules = 0
foreach ($e in $elements) { $totalMatchRules += $e.MatchRules }
$counts['(match rules)'] = $totalMatchRules

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
$legacyTypes = @{
    'Model'          = 'DataProductProfile'
    'ModelJob'       = 'CertificationJob'
    'ModelPrivGrant' = 'DataProductPrivGrant'
    'ModelVariable'  = 'DynamicVariable'
}
foreach ($e in ($elements | Where-Object { $legacyTypes.ContainsKey($_.Type) })) {
    $errors.Add("$($e.Path) uses _type '$($e.Type)', which Design CLI 2.x does not recognise; it must be '$($legacyTypes[$e.Type])'. Run ci-cd/scripts/Convert-ToDataProduct.ps1.")
}
$profileCount = 0; if ($counts.ContainsKey('DataProductProfile')) { $profileCount = $counts['DataProductProfile'] }
if ($profileCount -ne 1) { $errors.Add("Expected exactly one DataProductProfile in the data product folder, found $profileCount.") }
if (-not $counts.ContainsKey('Entity')) { $errors.Add('No entities (*.Entity.seml) found under the root folder.') }

$dupes = $elements | Group-Object { "$($_.Package)|$($_.Name)|$($_.Type)" } | Where-Object { $_.Count -gt 1 }
foreach ($d in $dupes) {
    $errors.Add("Duplicate element '$($d.Group[0].Name)' ($($d.Group[0].Type)) in: " + (($d.Group | ForEach-Object { $_.Path }) -join ', '))
}

foreach ($x in $excluded) {
    $warnings.Add("$x is not a .seml file, so it is NOT deployed. Rename it to *.seml if it should be part of the model.")
}

$idRuleEntities = @{}
foreach ($e in ($elements | Where-Object { $_.Type -eq 'IDSurvivorshipRule' -and $_.Entity })) { $idRuleEntities[$e.Entity] = $true }

$fuzzy = @($elements | Where-Object { $_.Type -eq 'Entity' -and $_.EntityType -eq 'FUZZY_MATCHED' })
foreach ($e in $fuzzy) {
    $qualified = "$($e.Package).$($e.Name)"
    if (-not $e.HasMatcher -or $e.MatchRules -eq 0) {
        $warnings.Add("Fuzzy-matched entity '$($e.Name)' has no match rules.")
    }
    if (-not $idRuleEntities.ContainsKey($qualified)) {
        $warnings.Add("Fuzzy-matched entity '$($e.Name)' has no ID survivorship rule.")
    }
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$known = @{}
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine("| Area | Element | Count |")
[void]$md.AppendLine("|---|---|---:|")

Write-Host ''
Write-Host ("{0,-20} {1,-26} {2,6}" -f 'Area', 'Element', 'Count')
Write-Host ('-' * 54)
foreach ($cat in $categories.Keys) {
    foreach ($t in $categories[$cat]) {
        $known[$t] = $true
        $n = 0; if ($counts.ContainsKey($t)) { $n = $counts[$t] }
        if ($n -eq 0 -and $t -in @('PluginValidation', 'RestClientEnricher', 'DynamicVariable')) { continue }
        Write-Host ("{0,-20} {1,-26} {2,6}" -f $cat, $t, $n)
        [void]$md.AppendLine("| $cat | $t | $n |")
    }
}
foreach ($t in ($counts.Keys | Where-Object { -not $known.ContainsKey($_) } | Sort-Object)) {
    Write-Host ("{0,-20} {1,-26} {2,6}" -f 'Other', $t, $counts[$t])
    [void]$md.AppendLine("| Other | $t | $($counts[$t]) |")
}
$semlCount = $elements.Count
Write-Host ('-' * 54)
Write-Host ("{0,-47} {1,6}" -f 'Model files deployed (*.seml)', $semlCount)
Write-Host ("{0,-47} {1,6}" -f 'Files excluded (not *.seml)', $excluded.Count)
Write-Host ("{0,-47} {1,6}" -f 'Fuzzy-matched entities', $fuzzy.Count)
Write-Host ''

[void]$md.AppendLine('')
[void]$md.AppendLine("**$semlCount model files** will be built and deployed from ``$RootFolder``; $($excluded.Count) file(s) excluded; $($fuzzy.Count) fuzzy-matched entities.")

if ($errors.Count -gt 0 -or $warnings.Count -gt 0) {
    [void]$md.AppendLine('')
    [void]$md.AppendLine('**Findings**')
    [void]$md.AppendLine('')
    foreach ($e in $errors)   { [void]$md.AppendLine("- :x: $e") }
    foreach ($w in $warnings) { [void]$md.AppendLine("- :warning: $w") }
}

foreach ($e in $errors)   { Write-Issue 'error' $e }
foreach ($w in $warnings) { Write-Issue 'warning' $w }

if (-not $OutputFolder) {
    if ($env:BUILD_ARTIFACTSTAGINGDIRECTORY) { $OutputFolder = $env:BUILD_ARTIFACTSTAGINGDIRECTORY }
    elseif ($env:AGENT_TEMPDIRECTORY)       { $OutputFolder = $env:AGENT_TEMPDIRECTORY }
    else                                    { $OutputFolder = (Get-Location).Path }
}
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
$safeTitle = ($SummaryTitle -replace '[^\w\-]+', '-').Trim('-')
$mdPath   = Join-Path $OutputFolder "$safeTitle.md"
$jsonPath = Join-Path $OutputFolder "$safeTitle.json"
[IO.File]::WriteAllText($mdPath, $md.ToString(), (New-Object Text.UTF8Encoding($false)))
$inventory = [ordered]@{
    rootFolder = $RootFolder
    counts     = $counts
    excluded   = $excluded
    errors     = $errors
    warnings   = $warnings
    elements   = $elements
}
[IO.File]::WriteAllText($jsonPath, ($inventory | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
if ($onAdo) { Write-Host "##vso[task.addattachment type=Distributedtask.Core.Summary;name=$SummaryTitle;]$mdPath" }

if ($errors.Count -gt 0) {
    Write-Issue 'error' "$($errors.Count) model error(s) found - nothing will be deployed."
    exit 1
}
if ($warnings.Count -gt 0) {
    if ($Strict) {
        Write-Issue 'error' "$($warnings.Count) warning(s) and strict model checking is on (MODEL_CHECK_STRICT)."
        exit 1
    }
    if ($onAdo) { Write-Host '##vso[task.complete result=SucceededWithIssues;]Model inventory has warnings' }
}
Write-Host "Model inventory complete: $semlCount model files."
exit 0
