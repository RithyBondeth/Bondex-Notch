'use client';

import { useState } from 'react';

export default function CopyLicenseKey({ licenseKey }: { licenseKey: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(licenseKey);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
      setCopied(false);
    }
  };

  return (
    <div className="license-key-box" style={{
      background: 'rgba(255, 255, 255, 0.05)',
      border: '1px solid rgba(255, 255, 255, 0.15)',
      borderRadius: '12px',
      padding: '16px',
      margin: '20px 0',
      textAlign: 'center',
    }}>
      <p style={{ margin: '0 0 8px 0', fontSize: '13px', color: 'rgba(255, 255, 255, 0.6)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
        Your Lifetime Licence Key
      </p>
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '12px',
        flexWrap: 'wrap',
      }}>
        <code style={{
          fontFamily: 'var(--mono, monospace)',
          fontSize: '18px',
          fontWeight: 700,
          letterSpacing: '0.08em',
          color: '#3CC1F6',
          padding: '6px 12px',
          background: 'rgba(0, 0, 0, 0.4)',
          borderRadius: '8px',
          border: '1px solid rgba(60, 193, 246, 0.3)',
          userSelect: 'all',
        }}>
          {licenseKey}
        </code>
        <button
          type="button"
          onClick={handleCopy}
          className="btn"
          style={{
            padding: '8px 16px',
            fontSize: '13px',
            cursor: 'pointer',
          }}
        >
          {copied ? '✓ Copied' : 'Copy Key'}
        </button>
      </div>
    </div>
  );
}
