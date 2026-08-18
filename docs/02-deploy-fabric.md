# 02 · Deploy the Fabric items

## Run the deployment script

```powershell
az login
./scripts/deploy-fabric.ps1 -WorkspaceId <your-workspace-guid>
```

Optional switches:

| Switch | Effect |
|---|---|
| `-IncludePreview` | Also deploys `hcp-sql` (SQL database), `hcp_onto2` (ontology) and `GraphQL_1` |
| `-FabricPath <path>` | Use definitions from a different folder than `./fabric` |

## What the script does

1. **Lakehouse** – creates `cms_lakehouse`, then polls until its SQL analytics endpoint is
   provisioned (this can take a couple of minutes on a new workspace).
2. **Notebooks** – creates `01-DownloadCMSDataCsvFiles`, `02-CreateCMSDataTable` and
   `03-CreateCMSStarSchemaTables`, binding each to the new lakehouse as the default lakehouse.
3. **Pipeline** – creates `cms_data_pipeline` wired to the three new notebook IDs.
4. **Semantic model** – creates `hcp_semantic_model`, rewriting the `Sql.Database(...)`
   expression to your lakehouse SQL endpoint.
5. **Reports** – creates both Power BI reports, bound to the new semantic model.
6. **Data agents** – creates `hcp-agent` and `HCP-DataOneAgent` with their AI instructions
   and few-shot examples.

The script is **name-idempotent**: re-running it updates existing items instead of creating
duplicates, so it is safe to use for iterative deployments. The authoritative item name is
the `displayName` inside each folder's `.platform` file.

> **Order matters for `-IncludePreview`.** `GraphQL_1` resolves its schema at creation time,
> so it only succeeds once the gold tables exist. Deploy the core items, run the pipeline,
> then re-run with `-IncludePreview`. Failures there are reported as warnings and do not
> abort the deployment.

## Token substitution

Definitions in `fabric/` are stored with placeholders instead of workspace-specific GUIDs:

| Token | Replaced with |
|---|---|
| `<<WORKSPACE_ID>>` | Your workspace GUID |
| `<<WORKSPACE_NAME>>` | Your workspace display name |
| `<<CMS_LAKEHOUSE_ID>>` | The new `cms_lakehouse` item ID |
| `<<CMS_LAKEHOUSE_SQL_ENDPOINT_ID>>` | The lakehouse SQL endpoint database ID |
| `<<CMS_LAKEHOUSE_SQL_ENDPOINT_SERVER>>` | The `*.datawarehouse.fabric.microsoft.com` host |
| `<<NOTEBOOK_01_ID>>` … `<<NOTEBOOK_03_ID>>` | The new notebook item IDs |
| `<<SEMANTIC_MODEL_ID>>` | The new semantic model item ID |

If the script warns about an *unresolved token*, an item earlier in the chain failed to
create — check the error above the warning and re-run.

## Load the data

```powershell
./scripts/run-pipeline.ps1 -WorkspaceId <your-workspace-guid>
```

The pipeline runs the three notebooks in order:

```
DownloadCMSData → CreateCMSDataTable → CreateCMSStarSchemaTables
```

Expected result in `cms_lakehouse`:

| Object | Type |
|---|---|
| `Files/cms_raw/<year>.csv` | Raw CSV per year |
| `cms_provider_drug_costs` | Silver Delta table |
| `cms_provider_dim_drug` / `_provider` / `_geography` / `_year` | Gold dimensions |
| `cms_provider_drug_costs_star` | Gold fact table |

Verify with the lakehouse SQL endpoint:

```sql
SELECT COUNT(*) AS fact_rows FROM cms_provider_drug_costs_star;
SELECT TOP 10 Brnd_Name, Gnrc_Name FROM cms_provider_dim_drug;
```

## Refresh the semantic model

The Direct Lake model picks up new data automatically, but the SQL analytics endpoint
metadata may lag. If tables appear empty in the report, open the lakehouse SQL endpoint once
in the portal to force a metadata sync, then refresh `hcp_semantic_model`.

Next: [03 · Deploy the web app](03-deploy-app.md)
