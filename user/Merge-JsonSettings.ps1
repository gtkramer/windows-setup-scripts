#Requires -Version 7.0
<#
.SYNOPSIS
  Merge the values of one JSON file into another, keeping everything else the target holds.
  Called through Set-JsonSettings in common.ps1; not a module.
.DESCRIPTION
  Objects are merged key by key, at any depth. Anything else (text, numbers, lists) replaces
  the target's value. The target is created when missing. A target that cannot be read as JSON,
  or whose shape disagrees with the kit's (a list where the kit has an object), is left alone.
  Comments in the target are accepted on reading but are not written back.
.PARAMETER Path
  The JSON file to update, for example VS Code's settings.json.
.PARAMETER Settings
  The kit's JSON file holding the values to set.
#>
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Settings
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Merge-Dictionary {
    param([Collections.IDictionary]$Target, [Collections.IDictionary]$Source, [string]$Where = '')
    foreach ($key in @($Source.Keys)) {
        $here = if ($Where) { "$Where.$key" } else { "$key" }
        if ($Source[$key] -is [Collections.IDictionary]) {
            if (-not $Target.Contains($key)) { $Target[$key] = [ordered]@{} }
            if ($Target[$key] -isnot [Collections.IDictionary]) {
                throw "'$here' is not an object in the existing file."
            }
            Merge-Dictionary $Target[$key] $Source[$key] $here
        } else {
            $Target[$key] = $Source[$key]
        }
    }
}

try {
    $wanted = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json -AsHashtable
    $current = [ordered]@{}
    if (Test-Path -LiteralPath $Path) {
        $text = Get-Content -LiteralPath $Path -Raw
        if ($text -and $text.Trim()) {
            $current = $text | ConvertFrom-Json -AsHashtable
            if ($current -isnot [Collections.IDictionary]) { throw 'the existing file is not a JSON object.' }
        }
    } else {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    }

    Merge-Dictionary $current $wanted
    $json = $current | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "INFO: Settings merged into $Path" -ForegroundColor Cyan
} catch {
    Write-Warning "Left $Path unchanged: $($_.Exception.Message)"
    exit 1
}
