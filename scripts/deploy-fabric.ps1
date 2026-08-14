<#
.SYNOPSIS
    Deploys the HCP Analytics solution (lakehouse, notebooks, pipeline, semantic model,
    reports and data agents) into a Microsoft Fabric workspace.

.DESCRIPTION
    Reads the item definitions under ./fabric, replaces the <<TOKEN>> placeholders with
    the IDs of the resources it creates, and calls the Fabric REST API to create each item.

    The script is idempotent for names: if an item with the same display name already
    exists in the target workspace it is updated instead of re-created.

.EXAMPLE
    az login
    ./scripts/deploy-fabric.ps1 -WorkspaceId 11111111-2222-3333-4444-555555555555

.EXAMPLE
    ./scripts/deploy-fabric.ps1 -WorkspaceId <guid> -IncludePreview
#>
[CmdletBinding()]
param(
  # Target Fabric workspace (must already exist and be on a Fabric capacity).
  [Parameter(Mandatory = $true)][string]$WorkspaceId,

  # Root of the exported definitions. Defaults to ../fabric relative to this script.
  [string]$FabricPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'fabric'),

  # Also deploy the preview items: Ontology, GraphModel, GraphQL API, SQL database.
  [switch]$IncludePreview
)

$ErrorActionPreference = 'Stop'
$ApiBase = 'https://api.fabric.microsoft.com/v1'

# ---------------------------------------------------------------- helpers ----

function Get-FabricHeaders {
  $token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
  if (-not $token) { throw 'Could not acquire a Fabric token. Run "az login" first.' }
  return @{ Authorization = "Bearer $token" }
}

function Invoke-Fabric {
  param(
    [Parameter(Mandatory)][string]$Method,
    [Parameter(Mandatory)][string]$Path,
    $Body
  )
  $headers = Get-FabricHeaders
  $uri = "$ApiBase$Path"
  $json = if ($null -ne $Body) { $Body | ConvertTo-Json -Depth 100 } else { $null }

  $res = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers `
    -ContentType 'application/json' -Body $json -SkipHttpErrorCheck

  if ($res.StatusCode -eq 202) {
    $loc = $res.Headers['Location']; if ($loc -is [array]) { $loc = $loc[0] }
    for ($i = 0; $i -lt 120; $i++) {
      Start-Sleep -Seconds 3
      $state = Invoke-RestMethod -Uri $loc -Headers (Get-FabricHeaders)
      if ($state.status -eq 'Succeeded') {
        try { return Invoke-RestMethod -Uri "$loc/result" -Headers (Get-FabricHeaders) } catch { return $state }
      }
      if ($state.status -in @('Failed', 'Undefined')) { throw "Operation failed: $($state | ConvertTo-Json -Depth 10)" }
    }
    throw "Operation timed out: $Method $Path"
  }

  if ($res.StatusCode -ge 400) { throw "$Method $Path -> $($res.StatusCode): $($res.Content)" }
  if ([string]::IsNullOrWhiteSpace($res.Content)) { return $null }
  return $res.Content | ConvertFrom-Json
}

function Get-WorkspaceItems {
  (Invoke-Fabric GET "/workspaces/$WorkspaceId/items").value
}

function Find-Item {
  param([string]$Type, [string]$DisplayName, $Items)
  $Items | Where-Object { $_.type -eq $Type -and $_.displayName -eq $DisplayName } | Select-Object -First 1
}

# Builds the `definition.parts` payload from a folder on disk, applying token substitution.
function New-DefinitionPayload {
  param([string]$Folder, [hashtable]$Tokens)

  $parts = @()
  foreach ($file in Get-ChildItem -Recurse -File $Folder) {
    $relative = $file.FullName.Substring($Folder.Length).TrimStart('\', '/').Replace('\', '/')
    $bytes = [IO.File]::ReadAllBytes($file.FullName)

    # Only text files can contain tokens; binary parts (e.g. dacpac) pass through untouched.
    if ($file.Extension -in @('.json', '.ipynb', '.tmdl', '.pbir', '.pbism', '.platform', '.xml') -or $file.Name -eq '.platform') {
      $text = [Text.Encoding]::UTF8.GetString($bytes)
      foreach ($k in $Tokens.Keys) { $text = $text.Replace("<<$k>>", $Tokens[$k]) }
      if ($text -match '<<[A-Z0-9_]+>>') {
        Write-Warning "Unresolved token in $relative : $($Matches[0])"
      }
      $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    }

    $parts += @{ path = $relative; payload = [Convert]::ToBase64String($bytes); payloadType = 'InlineBase64' }
  }
  return @{ parts = $parts }
}

function Deploy-Item {
  param(
    [Parameter(Mandatory)][string]$Type,
    [Parameter(Mandatory)][string]$DisplayName,
    [string]$Folder,
    [hashtable]$Tokens = @{},
    [string]$Description
  )

  $items = Get-WorkspaceItems
  $existing = Find-Item -Type $Type -DisplayName $DisplayName -Items $items

  $definition = if ($Folder) { New-DefinitionPayload -Folder $Folder -Tokens $Tokens } else { $null }

  if ($existing) {
    Write-Host "  ~ updating $Type '$DisplayName'" -ForegroundColor DarkYellow
    if ($definition) {
      Invoke-Fabric POST "/workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition?updateMetadata=True" @{ definition = $definition } | Out-Null
    }
    return $existing.id
  }

  Write-Host "  + creating $Type '$DisplayName'" -ForegroundColor Green
  $body = @{ displayName = $DisplayName; type = $Type }
  if ($Description) { $body.description = $Description }
  if ($definition) { $body.definition = $definition }

  $created = Invoke-Fabric POST "/workspaces/$WorkspaceId/items" $body
  if ($created.id) { return $created.id }

  # Long-running create returns the item in the result body under a different shape.
  $items = Get-WorkspaceItems
  return (Find-Item -Type $Type -DisplayName $DisplayName -Items $items).id
}

# ------------------------------------------------------------------ main ----

Write-Host "`n=== HCP Analytics - Fabric deployment ===`n" -ForegroundColor Cyan

$workspace = Invoke-Fabric GET "/workspaces/$WorkspaceId"
$workspaceName = $workspace.displayName
Write-Host "Target workspace : $workspaceName ($WorkspaceId)"
Write-Host "Definitions      : $FabricPath`n"

# 1. Lakehouse -----------------------------------------------------------------
Write-Host '[1/7] Lakehouse' -ForegroundColor Cyan
$lakehouseId = Deploy-Item -Type 'Lakehouse' -DisplayName 'cms_lakehouse' `
  -Description 'Bronze/Silver/Gold storage for CMS Medicare Part D data'

Write-Host '      waiting for the SQL analytics endpoint to be provisioned...'
$sqlServer = $null; $sqlDatabaseId = $null
for ($i = 0; $i -lt 60; $i++) {
  $lh = Invoke-Fabric GET "/workspaces/$WorkspaceId/lakehouses/$lakehouseId"
  $ep = $lh.properties.sqlEndpointProperties
  if ($ep -and $ep.provisioningStatus -eq 'Success') {
    $sqlServer = $ep.connectionString
    $sqlDatabaseId = $ep.id
    break
  }
  Start-Sleep -Seconds 10
}
if (-not $sqlServer) { throw 'SQL analytics endpoint was not provisioned in time. Re-run the script in a few minutes.' }
Write-Host "      endpoint: $sqlServer"

$tokens = @{
  WORKSPACE_ID                   = $WorkspaceId
  WORKSPACE_NAME                 = $workspaceName
  CMS_LAKEHOUSE_ID               = $lakehouseId
  CMS_LAKEHOUSE_SQL_ENDPOINT_ID  = $sqlDatabaseId
  CMS_LAKEHOUSE_SQL_ENDPOINT_SERVER = $sqlServer
}

# 2. Notebooks -----------------------------------------------------------------
Write-Host "`n[2/7] Notebooks" -ForegroundColor Cyan
$notebookNames = @{
  '01-DownloadCMSDataCsvFiles'   = 'NOTEBOOK_01_ID'
  '02-CreateCMSDataTable'        = 'NOTEBOOK_02_ID'
  '03-CreateCMSStarSchemaTables' = 'NOTEBOOK_03_ID'
}
foreach ($name in $notebookNames.Keys | Sort-Object) {
  $id = Deploy-Item -Type 'Notebook' -DisplayName $name -Folder (Join-Path $FabricPath "Notebook/$name") -Tokens $tokens
  $tokens[$notebookNames[$name]] = $id
}

foreach ($extra in 'HCP-AI_Notebook', 'Notebook_1') {
  $folder = Join-Path $FabricPath "Notebook/$extra"
  if (Test-Path $folder) {
    Deploy-Item -Type 'Notebook' -DisplayName ($extra -replace '_', ' ') -Folder $folder -Tokens $tokens | Out-Null
  }
}

# 3. Pipeline ------------------------------------------------------------------
Write-Host "`n[3/7] Data pipeline" -ForegroundColor Cyan
Deploy-Item -Type 'DataPipeline' -DisplayName 'cms_data_pipeline' `
  -Folder (Join-Path $FabricPath 'DataPipeline/cms_data_pipeline') -Tokens $tokens | Out-Null

# 4. Semantic model ------------------------------------------------------------
Write-Host "`n[4/7] Semantic model" -ForegroundColor Cyan
$semanticModelId = Deploy-Item -Type 'SemanticModel' -DisplayName 'hcp_semantic_model' `
  -Folder (Join-Path $FabricPath 'SemanticModel/hcp_semantic_model') -Tokens $tokens
$tokens['SEMANTIC_MODEL_ID'] = $semanticModelId

# 5. Reports -------------------------------------------------------------------
Write-Host "`n[5/7] Reports" -ForegroundColor Cyan
$reports = @{
  'CMS_Medicare_Part_D_Star_Schema' = 'CMS Medicare Part D Star Schema'
  'Medicare_Services_Report'        = 'Medicare Services Report'
}
foreach ($folderName in $reports.Keys) {
  $folder = Join-Path $FabricPath "Report/$folderName"
  if (Test-Path $folder) {
    Deploy-Item -Type 'Report' -DisplayName $reports[$folderName] -Folder $folder -Tokens $tokens | Out-Null
  }
}

# 6. Data agents ---------------------------------------------------------------
Write-Host "`n[6/7] Data agents" -ForegroundColor Cyan
foreach ($agent in 'hcp-agent', 'HCP-DataOneAgent') {
  $folder = Join-Path $FabricPath "DataAgent/$agent"
  if (Test-Path $folder) {
    try { Deploy-Item -Type 'DataAgent' -DisplayName $agent -Folder $folder -Tokens $tokens | Out-Null }
    catch { Write-Warning "Data agent '$agent' could not be deployed automatically: $_" }
  }
}

# 7. Preview items -------------------------------------------------------------
Write-Host "`n[7/7] Preview items" -ForegroundColor Cyan
if ($IncludePreview) {
  $preview = @(
    @{ Type = 'SQLDatabase'; Name = 'hcp-sql'; Folder = 'SQLDatabase/hcp-sql' },
    @{ Type = 'Ontology'; Name = 'hcp_onto2'; Folder = 'Ontology/hcp_onto2' },
    @{ Type = 'GraphQLApi'; Name = 'GraphQL_1'; Folder = 'GraphQLApi/GraphQL_1' }
  )
  foreach ($p in $preview) {
    $folder = Join-Path $FabricPath $p.Folder
    if (-not (Test-Path $folder)) { continue }
    try { Deploy-Item -Type $p.Type -DisplayName $p.Name -Folder $folder -Tokens $tokens | Out-Null }
    catch { Write-Warning "Preview item '$($p.Name)' could not be deployed: $_" }
  }
} else {
  Write-Host '      skipped (pass -IncludePreview to deploy Ontology / GraphQL / SQL database)'
}

# ---------------------------------------------------------------- summary ----
Write-Host "`n=== Deployment complete ===" -ForegroundColor Cyan
$final = Get-WorkspaceItems
$agentId = (Find-Item -Type 'DataAgent' -DisplayName 'hcp-agent' -Items $final).id
$reportId = (Find-Item -Type 'Report' -DisplayName 'CMS Medicare Part D Star Schema' -Items $final).id

Write-Host @"

Next steps
  1. Run the pipeline to load the data (this downloads several GB from data.cms.gov):
       ./scripts/run-pipeline.ps1 -WorkspaceId $WorkspaceId

  2. Open 'hcp-agent' in Fabric and publish it once the gold tables exist.

  3. Configure the web app - put these into app/.env.local:
       VITE_FABRIC_WORKSPACE_ID=$WorkspaceId
       VITE_POWERBI_REPORT_ID=$reportId
       VITE_FABRIC_DATA_AGENT_ID=$agentId
"@ -ForegroundColor Yellow
