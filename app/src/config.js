// All tenant-specific values come from environment variables.
// Copy `.env.example` to `.env.local` and fill in your own IDs.
const env = import.meta.env;

function required(name) {
  const value = env[name];
  if (!value) {
    throw new Error(
      `Missing ${name}. Copy .env.example to .env.local and set your own values.`
    );
  }
  return value;
}

export const TENANT_ID    = required('VITE_ENTRA_TENANT_ID');
export const CLIENT_ID    = required('VITE_ENTRA_CLIENT_ID');
export const WORKSPACE_ID = required('VITE_FABRIC_WORKSPACE_ID');
export const REPORT_ID    = required('VITE_POWERBI_REPORT_ID');
export const AGENT_ID     = required('VITE_FABRIC_DATA_AGENT_ID');

export const msalConfig = {
  auth: {
    clientId: CLIENT_ID,
    authority: `https://login.microsoftonline.com/${TENANT_ID}`,
    redirectUri: window.location.origin,
  },
  cache: {
    cacheLocation: 'sessionStorage',
    storeAuthStateInCookie: false,
  },
};

export const POWER_BI_SCOPES = ['https://analysis.windows.net/powerbi/api/Report.Read.All'];
export const FABRIC_SCOPES = [
  'https://api.fabric.microsoft.com/DataAgent.Execute.All',
  'https://api.fabric.microsoft.com/DataAgent.Read.All',
  'https://api.fabric.microsoft.com/Item.ReadWrite.All',
];

export const EMBED_URL = `https://app.powerbi.com/reportEmbed?reportId=${REPORT_ID}&groupId=${WORKSPACE_ID}`;

export const AGENT_API_URL = `https://api.fabric.microsoft.com/v1/workspaces/${WORKSPACE_ID}/dataagents/${AGENT_ID}/aiassistant/openai`;
