<#
.SYNOPSIS
    Triggers the cms_data_pipeline in a Fabric workspace and waits for it to finish.

.EXAMPLE
    ./scripts/run-pipeline.ps1 -WorkspaceId <guid>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$WorkspaceId,
  [string]$PipelineName = 'cms_data_pipeline',
  # The download + Spark transforms can take a long time on small capacities.
  [int]$TimeoutMinutes = 240
)

$ErrorActionPreference = 'Stop'
$ApiBase = 'https://api.fabric.microsoft.com/v1'

function Get-Headers {
  $token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
  if (-not $token) { throw 'Could not acquire a Fabric token. Run "az login" first.' }
  @{ Authorization = "Bearer $token" }
}

$items = (Invoke-RestMethod -Uri "$ApiBase/workspaces/$WorkspaceId/items" -Headers (Get-Headers)).value
$pipeline = $items | Where-Object { $_.type -eq 'DataPipeline' -and $_.displayName -eq $PipelineName } | Select-Object -First 1
if (-not $pipeline) { throw "Pipeline '$PipelineName' not found in workspace $WorkspaceId. Run deploy-fabric.ps1 first." }

Write-Host "Starting '$PipelineName' ($($pipeline.id))..." -ForegroundColor Cyan
$res = Invoke-WebRequest -Uri "$ApiBase/workspaces/$WorkspaceId/items/$($pipeline.id)/jobs/instances?jobType=Pipeline" `
  -Method Post -Headers (Get-Headers) -ContentType 'application/json' -Body '{}' -SkipHttpErrorCheck

if ($res.StatusCode -ge 400) { throw "Failed to start pipeline: $($res.StatusCode) $($res.Content)" }

$location = $res.Headers['Location']; if ($location -is [array]) { $location = $location[0] }
Write-Host "Job accepted. Polling status (timeout ${TimeoutMinutes}m)..." -ForegroundColor Cyan

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$lastStatus = ''
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 30
  $job = Invoke-RestMethod -Uri $location -Headers (Get-Headers)
  if ($job.status -ne $lastStatus) {
    Write-Host ("  [{0:HH:mm:ss}] {1}" -f (Get-Date), $job.status)
    $lastStatus = $job.status
  }
  if ($job.status -in @('Completed', 'Failed', 'Cancelled', 'Deduped')) {
    if ($job.status -ne 'Completed') { throw "Pipeline ended with status '$($job.status)': $($job.failureReason | ConvertTo-Json -Depth 5)" }
    Write-Host "`nPipeline completed successfully." -ForegroundColor Green
    Write-Host 'Gold tables in cms_lakehouse: cms_provider_dim_drug, cms_provider_dim_provider, cms_provider_dim_geography, cms_provider_dim_year, cms_provider_drug_costs_star'
    return
  }
}
throw "Pipeline did not finish within $TimeoutMinutes minutes. Check the run in the Fabric portal."
