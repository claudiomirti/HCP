# 05 · Troubleshooting

## Deployment

**`Could not acquire a Fabric token`**
Run `az login`, then confirm with `az account show`. If you have several tenants, use
`az login --tenant <tenant-id>`.

**`401` / `403` from the Fabric API**
Your identity needs at least the **Member** role on the workspace. Item creation also
requires the tenant setting *Users can create Fabric items*.

**`SQL analytics endpoint was not provisioned in time`**
Endpoint provisioning for a brand-new lakehouse can exceed the script's 10-minute wait.
Wait a few minutes and re-run `deploy-fabric.ps1` — it is idempotent and will pick up the
existing lakehouse.

**`Unresolved token in ...`**
An item earlier in the dependency chain failed. Check the error above the warning, fix it,
and re-run the script.

**Notebook creation fails with `PyToIPynbFailure`**
The notebook definition must declare `format: "ipynb"`. `deploy-fabric.ps1` does this
automatically — if you call the REST API yourself, include it.

**Semantic model fails with `TMDL Format Error ... control characters are not allowed in names`**
A column display name contains a tab or newline. Fabric exports such names but refuses to
import them. Find it with:

```powershell
Get-ChildItem -Recurse -Filter *.tmdl fabric/SemanticModel |
  ForEach-Object { Select-String -Path $_.FullName -Pattern "'[^']*\t[^']*'" }
```

Remove the control character from the name — the `sourceColumn` binding underneath is
unaffected, so no data or report reference breaks.

**`GraphQL_1` fails with `DataSourceMetadataNotFoundKeyFieldsEmpty`**
The GraphQL API resolves its schema when it is created, so the gold tables must already
exist. Run the pipeline first, then re-run `deploy-fabric.ps1 -IncludePreview`.

**Duplicate items appear after re-running the script**
`updateDefinition?updateMetadata=True` renames an item to the `displayName` inside its
`.platform` file. `deploy-fabric.ps1` therefore treats `.platform` as the authoritative name.
If you add new items, keep the folder's `.platform` display name consistent.

**Data agent creation fails**
`DataAgent` requires the Copilot / Azure OpenAI tenant settings to be enabled and an F2+
capacity in a supported region. The script warns and continues; create the agent manually in
the portal and copy the instructions from
`fabric/DataAgent/hcp-agent/Files/Config/draft/stage_config.json`.

## Pipeline

**Notebook 01 fails with HTTP 429 or a timeout**
`data.cms.gov` rate-limits downloads. The notebook already retries three times with a
randomised back-off; simply re-run the pipeline — completed files are overwritten, not
duplicated.

**Notebook 01 runs for hours**
Expected. The dataset is one multi-GB CSV per year from 2013 onwards. On an F2 capacity a
cold run of 1–3 hours is normal.

**`Path does not exist: Files/cms_raw/*.csv` in notebook 02**
Notebook 01 did not finish, or the notebook is bound to a different default lakehouse. Open
the notebook and confirm the lakehouse pane shows `cms_lakehouse`.

**Out-of-memory in notebook 02 or 03**
Increase the Spark pool size, or restrict the year range by deleting older CSVs from
`Files/cms_raw` before re-running.

## Semantic model and reports

**Report shows "Couldn't load the data for this visual"**
The Direct Lake model still points at the old SQL endpoint, or the endpoint metadata is
stale. Open the lakehouse SQL analytics endpoint once in the portal, then refresh
`hcp_semantic_model`.

**Report opens but every visual is empty**
The pipeline has not been run yet, or it failed at the gold step. Check
`SELECT COUNT(*) FROM cms_provider_drug_costs_star`.

## Web app

**`Missing VITE_...` error on startup**
`app/.env.local` is absent or incomplete. Copy `app/.env.example` and fill in every value.
Vite only reads env vars at build/dev-server start — restart after editing.

**`AADSTS50011: redirect URI mismatch`**
The origin you opened the app from is not registered. Add it as a **single-page application**
redirect URI on the Entra app registration (both `http://localhost:5173` and the deployed
`*.webapp.fabricapps.net` URL).

**Report panel stays on the skeleton**
The Power BI token was not acquired. Confirm `Report.Read.All` (delegated) is granted with
admin consent, and that the signed-in user has at least **Viewer** on the workspace.

**Chat panel returns `404` on `/assistants`**
`hcp-agent` has not been published, or `VITE_FABRIC_DATA_AGENT_ID` points at the wrong item.

**Chat panel returns `403`**
The delegated scope `DataAgent.Execute.All` is missing or not consented.

**`npx rayfin up` fails on auth**
Run `npx rayfin login` first, and make sure the workspace is on a Fabric capacity.

## Keeping the repo in sync

After editing items in the portal:

```powershell
./scripts/export-fabric.ps1 -WorkspaceId <guid>
```

Then re-apply the placeholders before committing — replace your workspace GUID, lakehouse
GUID, SQL endpoint host, notebook GUIDs and semantic model GUID with the corresponding
`<<TOKEN>>` values listed in [02 · Deploy the Fabric items](02-deploy-fabric.md).
