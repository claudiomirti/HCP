<#
.SYNOPSIS
    Re-exports every item definition from a Fabric workspace into ./fabric.

.DESCRIPTION
    Use this after changing items in the Fabric portal so the repository stays in sync.
    Remember to re-run the tokenisation step (see docs/05-troubleshooting.md) if you
    export from a workspace other than a fresh deployment.

.EXAMPLE
    ./scripts/export-fabric.ps1 -WorkspaceId <guid>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$WorkspaceId,
  [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'fabric')
)

$ErrorActionPreference = 'Stop'
$ApiBase = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId"

function Get-Headers {
  $token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
  if (-not $token) { throw 'Could not acquire a Fabric token. Run "az login" first.' }
  @{ Authorization = "Bearer $token" }
}

function Get-Definition {
  param([string]$ItemId, [string]$Format)
  $url = "$ApiBase/items/$ItemId/getDefinition"
  if ($Format) { $url += "?format=$Format" }

  $res = Invoke-WebRequest -Uri $url -Method Post -Headers (Get-Headers) `
    -ContentType 'application/json' -Body '{}' -SkipHttpErrorCheck

  if ($res.StatusCode -eq 200) { return $res.Content | ConvertFrom-Json }
  if ($res.StatusCode -ne 202) { return $null }

  $loc = $res.Headers['Location']; if ($loc -is [array]) { $loc = $loc[0] }
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 3
    $state = Invoke-RestMethod -Uri $loc -Headers (Get-Headers)
    if ($state.status -eq 'Succeeded') { return Invoke-RestMethod -Uri "$loc/result" -Headers (Get-Headers) }
    if ($state.status -eq 'Failed') { return $null }
  }
  return $null
}

$items = (Invoke-RestMethod -Uri "$ApiBase/items" -Headers (Get-Headers)).value

foreach ($item in $items) {
  # SQL endpoints are derived items and system items are not portable.
  if ($item.type -eq 'SQLEndpoint' -or $item.displayName -eq '__fabric_plan_sys') { continue }

  $safeName = ($item.displayName -replace '[^A-Za-z0-9_.-]', '_')
  $format = if ($item.type -eq 'Notebook') { 'ipynb' } else { $null }
  $definition = Get-Definition -ItemId $item.id -Format $format

  if (-not $definition) { Write-Host "skip $($item.type)/$($item.displayName)" -ForegroundColor DarkGray; continue }

  $dir = Join-Path $OutDir "$($item.type)/$safeName"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  foreach ($part in $definition.definition.parts) {
    $target = Join-Path $dir $part.path
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    [IO.File]::WriteAllBytes($target, [Convert]::FromBase64String($part.payload))
  }
  Write-Host "ok   $($item.type)/$($item.displayName)" -ForegroundColor Green
}
