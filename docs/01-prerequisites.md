# 01 · Prerequisites

## 1. Tooling

| Tool | Version | Check |
|---|---|---|
| PowerShell | 7.0+ | `pwsh --version` |
| Azure CLI | 2.60+ | `az version` |
| Node.js | 20+ | `node --version` |
| Git | any | `git --version` |

```powershell
az login
az account show
```

Your signed-in identity must be at least a **Member** (ideally **Admin**) of the target
Fabric workspace.

## 2. Fabric capacity and workspace

1. Create or reuse a workspace backed by a **Fabric capacity (F2 or larger)** or a
   [Fabric trial](https://learn.microsoft.com/fabric/fundamentals/fabric-trial).
2. Note the workspace GUID — it is in the portal URL:
   `https://app.powerbi.com/groups/<WORKSPACE_ID>/list`.

> Notebook 01 downloads the full CMS dataset. Budget several GB of OneLake storage and
> 1–3 hours of Spark runtime on a small capacity.

### Required tenant settings

An admin must enable these in the **Fabric Admin portal → Tenant settings**:

| Setting | Why |
|---|---|
| *Service principals can use Fabric APIs* (only if you deploy with a service principal) | REST deployment |
| *Users can create Fabric items* | Item creation |
| *Copilot and Azure OpenAI Service* | Required for Fabric Data Agents |
| *Users can create Data Agent items* | Data agent |
| *Embed content in apps* | Power BI embedding in the SPA |

## 3. Entra ID app registration (for the web app)

The SPA signs users in with MSAL and calls Power BI and Fabric on their behalf.

1. **Entra admin center → App registrations → New registration**
   - Name: `HCP Analytics SPA`
   - Supported account types: *Accounts in this organizational directory only*
   - Redirect URI: **Single-page application** → `http://localhost:5173`
2. Record the **Application (client) ID** and **Directory (tenant) ID**.
3. **API permissions → Add a permission → Delegated**:

   | API | Permission |
   |---|---|
   | Power BI Service | `Report.Read.All` |
   | Power BI Service | `Dataset.Read.All` |
   | Microsoft Fabric | `DataAgent.Execute.All` |
   | Microsoft Fabric | `DataAgent.Read.All` |
   | Microsoft Fabric | `Item.ReadWrite.All` |
   | Microsoft Graph | `User.Read` |

4. Click **Grant admin consent**.
5. After you deploy the app (step 3 of the quickstart), come back and add the
   `https://<name>.webapp.fabricapps.net` URL as an additional SPA redirect URI.

## 4. Clone the repository

```powershell
git clone https://github.com/claudiomirti/HCP.git
cd HCP
```

Next: [02 · Deploy the Fabric items](02-deploy-fabric.md)
