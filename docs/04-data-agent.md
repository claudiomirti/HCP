# 04 · The Fabric Data Agent

`hcp-agent` answers natural-language questions by generating SQL against the gold tables in
`cms_lakehouse`. Its behaviour is driven by the AI instructions and few-shot examples that
ship in `fabric/DataAgent/hcp-agent/`.

## Deployed structure

```
DataAgent/hcp-agent/
├── .platform
└── Files/Config/
    ├── data_agent.json
    ├── publish_info.json
    ├── draft/
    │   ├── stage_config.json                     # aiInstructions
    │   └── lakehouse-tables-cms_lakehouse/
    │       ├── datasource.json                   # selected tables + columns
    │       └── fewshots.json                     # question → SQL examples
    └── published/                                # same, for the published stage
```

## Publish it

The REST deployment creates the agent in **draft**. To make it callable from the web app:

1. Open the workspace in the Fabric portal and select `hcp-agent`.
2. Confirm the data source points at your `cms_lakehouse` and that the five gold tables are
   selected.
3. Ask a test question, then press **Publish**.

Until it is published, the app's chat panel returns a `404` from the assistants endpoint.

## AI instructions (summary)

The agent is primed with a domain briefing so it produces clinically sensible SQL:

- **Schema map** — which table and column answers questions about drugs, prescribers, years,
  geography and costs, and that `cms_provider_drug_costs_star` is the fact table joined via
  `drug_key`, `geo_key`, `provider_key` and `Year`.
- **Measures** — `Tot_Benes` (beneficiaries), `Tot_Clms` (claims), `Tot_Day_Suply` (day
  supply), `Tot_Drug_Cst` (cost, formatted as USD).
- **Drug class heuristics** on `Gnrc_Name`:

  | Class | Pattern |
  |---|---|
  | ACE inhibitors | contains `pril` |
  | Quinolone antibiotics | contains `floxacin` |
  | ARBs | contains `sartan` |
  | Statins | contains `statin` |
  | Benzodiazepines | contains `zolam` or `zepam` |
  | Beta blockers | contains `olol` (excluding carvedilol) |

- **Specialties** — "internists" / "internal medicine" map to `Prscrbr_Type LIKE '%Internal Medicine%'`.

To change the behaviour, edit `aiInstructions` in
`fabric/DataAgent/hcp-agent/Files/Config/draft/stage_config.json`, re-run
`deploy-fabric.ps1`, and publish again.

## Example questions

- Which prescribers have the highest total drug cost?
- What are the top 10 drugs by total claim count?
- Show average cost per beneficiary by specialty.
- How has statin prescribing changed by year in MN?
- Which states have the highest benzodiazepine claims per beneficiary?

## The second agent

`HCP-DataOneAgent` targets `hcp_semantic_model` instead of the lakehouse tables, so it
answers with DAX over the Direct Lake model. It is optional — the web app uses `hcp-agent`.

Next: [05 · Troubleshooting](05-troubleshooting.md)
