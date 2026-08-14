# 03 · Deploy the web app

The app is a Vite + React 19 single-page application. It signs users in with MSAL
(Entra ID), embeds the Power BI report with a user-delegated AAD token, and talks to the
Fabric Data Agent through its OpenAI-compatible assistants endpoint.

```
app/
├── src/
│   ├── main.jsx                     MSAL bootstrap
│   ├── App.jsx                      Layout, login/logout, token acquisition
│   ├── config.js                    All IDs read from VITE_* env vars
│   └── components/
│       ├── PowerBIReport.jsx        powerbi-client embed
│       └── DataAgentChat.jsx        Assistants API: assistant → thread → run → poll
├── rayfin/rayfin.yml                Rayfin service manifest
└── .env.example
```

## 1. Configure

```powershell
cd app
Copy-Item .env.example .env.local
```

Fill in `.env.local` with the values printed by `deploy-fabric.ps1`:

```dotenv
VITE_ENTRA_TENANT_ID=<directory (tenant) id>
VITE_ENTRA_CLIENT_ID=<application (client) id of the SPA registration>
VITE_FABRIC_WORKSPACE_ID=<workspace guid>
VITE_POWERBI_REPORT_ID=<report item id>
VITE_FABRIC_DATA_AGENT_ID=<hcp-agent item id>
```

`.env.local` is git-ignored — never commit it.

## 2. Run locally

```powershell
npm install
npm run dev
```

Open <http://localhost:5173> and sign in. `http://localhost:5173` must already be listed as
a **single-page application** redirect URI on the app registration.

## 3. Deploy to Fabric with Rayfin

`rayfin/rayfin.yml` declares the app services:

```yaml
services:
  auth:            # Entra ID sign-in, Fabric-aware
  data:            # mssql-backed app database
  staticHosting:   # serves ./dist, built with `npm run build`
```

Deploy:

```powershell
npx rayfin up
```

Rayfin creates the `hcp-app` item in your workspace, builds `dist/` and publishes it. Note
the URL it prints, e.g. `https://<name>-<region>.webapp.fabricapps.net`.

## 4. Register the deployed URL

Two places need the production URL:

1. `app/rayfin/rayfin.yml`:

   ```yaml
   services:
     auth:
       allowedRedirectUris:
         - http://localhost:5173
         - https://<name>-<region>.webapp.fabricapps.net   # <- add this
   ```

   Then run `npx rayfin up` again.

2. Your Entra app registration → **Authentication → Single-page application** → add the same
   URL as a redirect URI.

## 5. Regenerate Rayfin env values

Rayfin writes its runtime configuration to `rayfin/.env` (git-ignored). To project those into
Vite variables:

```powershell
npx rayfin env --framework vite
```

This generates `.env.local` entries prefixed `VITE_RAYFIN_*` / `VITE_FABRIC_*`. Keep your own
`VITE_ENTRA_*`, `VITE_POWERBI_REPORT_ID` and `VITE_FABRIC_DATA_AGENT_ID` values in the file —
the generator only manages the Rayfin-owned keys.

## How the data agent call works

`DataAgentChat.jsx` uses the Assistants v2 shape against:

```
https://api.fabric.microsoft.com/v1/workspaces/{workspaceId}/dataagents/{agentId}/aiassistant/openai
```

1. `POST /assistants` — created once per browser session
2. `POST /threads` — one conversation thread
3. `POST /threads/{id}/messages` — the user question
4. `POST /threads/{id}/runs` — start the run
5. poll `GET /threads/{id}/runs/{runId}` until `completed`
6. `GET /threads/{id}/messages?order=desc&limit=1` — read the answer

All requests carry the delegated Fabric token with `DataAgent.Execute.All`.

Next: [04 · The data agent](04-data-agent.md)
