<#
.SYNOPSIS
    Converts a Semarchy Design CLI 1.x SEML project to the Design CLI 2.x
    data-product format, in place.

.DESCRIPTION
    Design CLI 2.0.1 renamed four element types. Files that still use the old
    names are rejected ("couldn't find any indexer", "Unknown _type", "Missing
    mandatory model file"). This script changes the top-level `_type` of every
    affected file:

        Model          ->  DataProductProfile
        ModelJob       ->  CertificationJob
        ModelPrivGrant ->  DataProductPrivGrant
        ModelVariable  ->  DynamicVariable

    With -FixFileNames (on by default) it also renames every .seml file to
    <_name>.<_type>.seml when its name does not match. It uses `git mv` inside a
    git repository, so file history is kept. The CLI does not need this, but it
    keeps the project consistent for Design XP.

    Line endings (CRLF/LF) and a UTF-8 BOM, if present, are preserved.
    Nothing else in the files is changed. Safe to re-run.

    Use -WhatIf to see what would change without changing anything.

.EXAMPLE
    # From the repository root
    .\ci-cd\scripts\Convert-ToDataProduct.ps1 -DataProductFolder src -WhatIf
    .\ci-cd\scripts\Convert-ToDataProduct.ps1 -DataProductFolder src
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $DataProductFolder = 'src',
    [bool]   $FixFileNames = $true
)

$ErrorActionPreference = 'Stop'

$typeMap = [ordered]@{
    'Model'          = 'DataProductProfile'
    'ModelJob'       = 'CertificationJob'
    'ModelPrivGrant' = 'DataProductPrivGrant'
    'ModelVariable'  = 'DynamicVariable'
}

if (-not (Test-Path $DataProductFolder -PathType Container)) {
    throw "Folder '$DataProductFolder' not found."
}
$root = (Resolve-Path $DataProductFolder).Path

$useGit = $false
if ($FixFileNames -and (Get-Command git -ErrorAction SilentlyContinue)) {
    Push-Location $root
    try {
        $inside = (& git rev-parse --is-inside-work-tree 2>$null)
        $useGit = ($LASTEXITCODE -eq 0 -and "$inside".Trim() -eq 'true')
    } finally { Pop-Location }
}

$typeChanges = 0
$renames     = 0
$skipped     = New-Object System.Collections.Generic.List[string]

$files = Get-ChildItem -Path $root -Recurse -File -Filter '*.seml' | Sort-Object FullName
foreach ($f in $files) {
    $bytes  = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text   = [Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom) { $text = $text.Substring(1) }

    $rel = $f.FullName.Substring($root.Length).TrimStart('\', '/')

    # --- 1. _type conversion -------------------------------------------------
    $m = [regex]::Match($text, '(?m)^_type:[ \t]*(\w+)[ \t]*(\r?)$')
    if (-not $m.Success) { continue }
    $type = $m.Groups[1].Value

    if ($typeMap.Contains($type)) {
        $newType = $typeMap[$type]
        $newText = $text.Substring(0, $m.Index) + "_type: $newType" + $m.Groups[2].Value +
                   $text.Substring($m.Index + $m.Length)
        if ($PSCmdlet.ShouldProcess($rel, "_type $type -> $newType")) {
            $enc = New-Object Text.UTF8Encoding($hasBom)
            [IO.File]::WriteAllText($f.FullName, $newText, $enc)
        }
        Write-Host ("  _type  {0,-15} -> {1,-21} {2}" -f $type, $newType, $rel)
        $typeChanges++
        $type = $newType
    }

    # --- 2. File name ---------------------------------------------------------
    if (-not $FixFileNames) { continue }
    $nm = [regex]::Match($text, '(?m)^_name:[ \t]*[''"]?([\w\-]+)[''"]?[ \t]*\r?$')
    if (-not $nm.Success) { continue }
    $expectedName = "$($nm.Groups[1].Value).$type.seml"
    if ($f.Name -ceq $expectedName) { continue }

    $target = Join-Path $f.DirectoryName $expectedName
    if ((Test-Path $target) -and ($f.FullName -ine $target)) {
        $skipped.Add("$rel (target $expectedName already exists)")
        continue
    }
    if ($PSCmdlet.ShouldProcess($rel, "rename to $expectedName")) {
        if ($useGit) {
            Push-Location $f.DirectoryName
            try {
                & git mv -f -- $f.Name $expectedName 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    # Untracked file: plain rename instead
                    Move-Item -LiteralPath $f.FullName -Destination $target -Force
                }
            } finally { Pop-Location }
        } else {
            Move-Item -LiteralPath $f.FullName -Destination $target -Force
        }
    }
    Write-Host ("  rename {0} -> {1}" -f $rel, $expectedName)
    $renames++
}

Write-Host ''
Write-Host "Type changes: $typeChanges   Renames: $renames   (git mv: $useGit)"
foreach ($s in $skipped) { Write-Host "  skipped: $s" -ForegroundColor Yellow }
if ($WhatIfPreference) { Write-Host 'WhatIf: nothing was changed.' }
