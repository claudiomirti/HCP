import React, { useState, useRef, useEffect } from 'react';
import { AGENT_API_URL } from '../config.js';

const SUGGESTED_QUESTIONS = [
  'Which prescribers have the highest total drug cost?',
  'What are the top 10 drugs by total claim count?',
  'Show average cost per beneficiary by specialty.',
  'Compare opioid prescribing rates across states.',
];

const API_VERSION = '2024-05-01-preview';
const POLL_INTERVAL_MS = 2500;
const POLL_TIMEOUT_MS = 120_000;

export default function DataAgentChat({ accessToken }) {
  const [messages, setMessages]     = useState([]);
  const [input, setInput]           = useState('');
  const [loading, setLoading]       = useState(false);
  const [statusText, setStatusText] = useState('');
  // Persist assistant + thread across messages in this session
  const assistantId = useRef(null);
  const threadId    = useRef(null);
  const bottomRef   = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, statusText]);

  const apiFetch = (path, opts = {}) => {
    const url = `${AGENT_API_URL}${path}${path.includes('?') ? '&' : '?'}api-version=${API_VERSION}`;
    return fetch(url, {
      ...opts,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
        'OpenAI-Beta': 'assistants=v2',
        ...(opts.headers || {}),
      },
    });
  };

  // Initialise assistant + thread (once per session)
  const ensureSession = async () => {
    if (!assistantId.current) {
      setStatusText('Initializing agent…');
      const res = await apiFetch('/assistants', { method: 'POST', body: JSON.stringify({ model: 'not used' }) });
      if (!res.ok) throw new Error(`Assistant create failed: ${res.status} ${await res.text()}`);
      assistantId.current = (await res.json()).id;
    }
    if (!threadId.current) {
      const res = await apiFetch('/threads', { method: 'POST', body: '{}' });
      if (!res.ok) throw new Error(`Thread create failed: ${res.status} ${await res.text()}`);
      threadId.current = (await res.json()).id;
    }
  };

  const sendMessage = async (text) => {
    const question = text || input.trim();
    if (!question || !accessToken) return;

    setInput('');
    setMessages(prev => [...prev, { role: 'user', content: question }]);
    setLoading(true);
    setStatusText('');

    try {
      await ensureSession();

      // Add user message to thread
      setStatusText('Sending message…');
      const msgRes = await apiFetch(`/threads/${threadId.current}/messages`, {
        method: 'POST',
        body: JSON.stringify({ role: 'user', content: question }),
      });
      if (!msgRes.ok) throw new Error(`Message add failed: ${msgRes.status} ${await msgRes.text()}`);

      // Create run
      setStatusText('Running agent…');
      const runRes = await apiFetch(`/threads/${threadId.current}/runs`, {
        method: 'POST',
        body: JSON.stringify({ assistant_id: assistantId.current }),
      });
      if (!runRes.ok) throw new Error(`Run create failed: ${runRes.status} ${await runRes.text()}`);
      const run = await runRes.json();

      // Poll until terminal state
      const deadline = Date.now() + POLL_TIMEOUT_MS;
      let status = run.status;
      let runId  = run.id;

      while (!['completed', 'failed', 'cancelled', 'expired'].includes(status)) {
        if (Date.now() > deadline) throw new Error('Agent timed out after 2 minutes.');
        await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));
        const pollRes = await apiFetch(`/threads/${threadId.current}/runs/${runId}`);
        if (!pollRes.ok) throw new Error(`Poll failed: ${pollRes.status} ${await pollRes.text()}`);
        status = (await pollRes.json()).status;
        setStatusText(`Agent status: ${status}…`);
      }

      if (status !== 'completed') throw new Error(`Run ended with status: ${status}`);

      // Get latest assistant message
      setStatusText('Retrieving answer…');
      const msgsRes = await apiFetch(`/threads/${threadId.current}/messages?order=desc&limit=1`);
      if (!msgsRes.ok) throw new Error(`Messages fetch failed: ${msgsRes.status} ${await msgsRes.text()}`);
      const msgsData = await msgsRes.json();
      const reply = msgsData.data?.[0]?.content?.[0]?.text?.value || 'No response received.';

      setMessages(prev => [...prev, { role: 'assistant', content: reply }]);
    } catch (e) {
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: `⚠️ Error: ${e.message}`,
        isError: true,
      }]);
    } finally {
      setLoading(false);
      setStatusText('');
    }
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  };

  return (
    <div className="chat">
      <div className="chat-messages">
        {messages.length === 0 && (
          <div className="chat-welcome">
            <div className="chat-welcome-icon">🔬</div>
            <h3>Drug Intelligence Agent</h3>
            <p>Ask questions about CMS Medicare Part D prescriber and drug data.</p>
            <div className="suggestions">
              {SUGGESTED_QUESTIONS.map((q, i) => (
                <button
                  key={i}
                  className="suggestion-chip"
                  onClick={() => sendMessage(q)}
                  disabled={!accessToken}
                >
                  {q}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((msg, i) => (
          <div key={i} className={`message message-${msg.role} ${msg.isError ? 'message-error' : ''}`}>
            <div className="message-avatar">
              {msg.role === 'user' ? '👤' : '🤖'}
            </div>
            <div className="message-bubble">
              <pre className="message-text">{msg.content}</pre>
            </div>
          </div>
        ))}

        {loading && (
          <div className="message message-assistant">
            <div className="message-avatar">🤖</div>
            <div className="message-bubble">
              <div className="typing-dots">
                <span /><span /><span />
              </div>
              {statusText && <p className="status-text">{statusText}</p>}
            </div>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      <div className="chat-input-area">
        {!accessToken && (
          <p className="chat-token-warn">Acquiring Fabric token…</p>
        )}
        <div className="chat-input-row">
          <textarea
            className="chat-input"
            rows={2}
            placeholder="Ask about prescribers, drugs, costs, or geography…"
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            disabled={!accessToken || loading}
          />
          <button
            className="btn-send"
            onClick={() => sendMessage()}
            disabled={!accessToken || loading || !input.trim()}
          >
            <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
              <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
            </svg>
          </button>
        </div>
      </div>
    </div>
  );
}
