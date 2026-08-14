import React, { useState, useEffect, useCallback } from "react";
import { useIsAuthenticated, useMsal } from "@azure/msal-react";
import { InteractionStatus, InteractionRequiredAuthError } from "@azure/msal-browser";
import PowerBIReport from "./components/PowerBIReport.jsx";
import DataAgentChat from "./components/DataAgentChat.jsx";
import { POWER_BI_SCOPES, FABRIC_SCOPES } from "./config.js";

export default function App() {
  const { instance, inProgress } = useMsal();
  const isAuthenticated = useIsAuthenticated();
  const [pbiToken, setPbiToken]     = useState(null);
  const [fabricToken, setFabricToken] = useState(null);
  const [user, setUser]             = useState(null);

  const acquireTokens = useCallback(async (account) => {
    try {
      const r = await instance.acquireTokenSilent({ scopes: POWER_BI_SCOPES, account });
      setPbiToken(r.accessToken);
    } catch (e) {
      if (e instanceof InteractionRequiredAuthError) {
        instance.acquireTokenRedirect({ scopes: POWER_BI_SCOPES, account });
        return;
      }
    }
    try {
      const r = await instance.acquireTokenSilent({ scopes: FABRIC_SCOPES, account });
      setFabricToken(r.accessToken);
    } catch (e) {
      if (e instanceof InteractionRequiredAuthError) {
        instance.acquireTokenRedirect({ scopes: FABRIC_SCOPES, account });
      }
    }
  }, [instance]);

  useEffect(() => {
    if (!isAuthenticated || inProgress !== InteractionStatus.None) return;
    const account = instance.getActiveAccount() || instance.getAllAccounts()[0];
    setUser(account);
    acquireTokens(account);
  }, [isAuthenticated, inProgress, instance, acquireTokens]);

  const handleLogin  = () => instance.loginRedirect({
    scopes: ["openid", "profile", "email", ...POWER_BI_SCOPES],
  });
  const handleLogout = () => instance.logoutRedirect({
    postLogoutRedirectUri: window.location.origin,
  });

  if (inProgress === InteractionStatus.HandleRedirect) {
    return (
      <div className="login-screen">
        <div className="login-card">
          <div className="spinner" style={{ width: 36, height: 36 }} />
          <p style={{ color: "var(--text-muted)", marginTop: 16, fontSize: "0.9rem" }}>Signing in...</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <div className="login-screen">
        <div className="login-card">
          <div className="login-logo">
            <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
              <rect width="22" height="22" fill="#F25022"/>
              <rect x="26" width="22" height="22" fill="#7FBA00"/>
              <rect y="26" width="22" height="22" fill="#00A4EF"/>
              <rect x="26" y="26" width="22" height="22" fill="#FFB900"/>
            </svg>
          </div>
          <h1>HCP Analytics</h1>
          <p>CMS Medicare Part D - Provider Drug Intelligence</p>
          <button className="btn-primary" onClick={handleLogin}>
            Sign in with Microsoft
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="topbar-brand">
          <svg width="24" height="24" viewBox="0 0 48 48" fill="none">
            <rect width="22" height="22" fill="#F25022"/>
            <rect x="26" width="22" height="22" fill="#7FBA00"/>
            <rect y="26" width="22" height="22" fill="#00A4EF"/>
            <rect x="26" y="26" width="22" height="22" fill="#FFB900"/>
          </svg>
          <span className="brand-name">HCP Analytics</span>
          <span className="brand-sub">CMS Medicare Part D</span>
        </div>
        <div className="topbar-user">
          <span className="user-name">{user?.name || user?.username}</span>
          <button className="btn-ghost" onClick={handleLogout}>Sign out</button>
        </div>
      </header>
      <main className="workspace">
        <section className="panel panel-report">
          <div className="panel-header">
            <h2>CMS Medicare Part D Star Schema</h2>
            <span className="badge">Power BI</span>
          </div>
          <div className="panel-body">
            <PowerBIReport accessToken={pbiToken} />
          </div>
        </section>
        <div className="divider" />
        <section className="panel panel-agent">
          <div className="panel-header">
            <h2>Drug Intelligence Agent</h2>
            <span className="badge badge-ai">AI</span>
          </div>
          <div className="panel-body">
            <DataAgentChat accessToken={fabricToken} />
          </div>
        </section>
      </main>
    </div>
  );
}
