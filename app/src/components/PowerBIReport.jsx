import React, { useEffect, useRef, useState } from 'react';
import { models, service, factories } from 'powerbi-client';
import { EMBED_URL, REPORT_ID } from '../config.js';

function Skeleton() {
  return (
    <div className="pbi-skeleton">
      <div className="skeleton-topbar">
        <div className="skeleton-block w-40" />
        <div className="skeleton-block w-24" />
        <div className="skeleton-block w-24" />
      </div>
      <div className="skeleton-body">
        <div className="skeleton-chart tall" />
        <div className="skeleton-row">
          <div className="skeleton-chart short" />
          <div className="skeleton-chart short" />
        </div>
      </div>
    </div>
  );
}

export default function PowerBIReport({ accessToken }) {
  const containerRef = useRef(null);
  const reportRef    = useRef(null);
  const [loaded, setLoaded] = useState(false);
  const [error, setError]   = useState(null);

  useEffect(() => {
    if (!accessToken || !containerRef.current) return;

    const powerbiService = new service.Service(
      factories.hpmFactory,
      factories.wpmpFactory,
      factories.routerFactory
    );

    const config = {
      type: 'report',
      tokenType: models.TokenType.Aad,
      accessToken,
      embedUrl: EMBED_URL,
      id: REPORT_ID,
      permissions: models.Permissions.Read,
      settings: {
        panes: {
          filters: { visible: false },
          pageNavigation: { visible: true, position: models.PageNavigationPosition.Bottom },
        },
        background: models.BackgroundType.Transparent,
        navContentPaneEnabled: false,
      },
    };

    try {
      if (reportRef.current) powerbiService.reset(containerRef.current);
      const report = powerbiService.embed(containerRef.current, config);
      reportRef.current = report;
      report.on('loaded', () => setLoaded(true));
      report.on('error', (e) => {
        console.error('Power BI error', e.detail);
        setError('Failed to load report. Check your permissions.');
        setLoaded(true);
      });
    } catch (e) {
      setError(e.message);
      setLoaded(true);
    }

    return () => {
      if (reportRef.current) {
        powerbiService.reset(containerRef.current);
        reportRef.current = null;
      }
    };
  }, [accessToken]);

  return (
    <div className="pbi-wrapper">
      {/* Skeleton shown until report is fully loaded */}
      {!loaded && <Skeleton />}
      {error && (
        <div className="placeholder error" style={{ position: 'absolute', inset: 0 }}>
          <p>{error}</p>
        </div>
      )}
      <div
        ref={containerRef}
        className="pbi-container"
        style={{ opacity: loaded && !error ? 1 : 0, transition: 'opacity 0.4s' }}
      />
    </div>
  );
}
