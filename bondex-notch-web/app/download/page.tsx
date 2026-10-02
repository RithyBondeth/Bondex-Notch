import type { Metadata } from 'next';
import Link from 'next/link';
import BrandMark from '@/components/BrandMark';

export const metadata: Metadata = {
  title: 'Download Bondex Notch for macOS',
  description: 'Download Bondex Notch — turns the display notch into a live, Dynamic Island surface for macOS 14+.',
  alternates: { canonical: '/download/' },
};

export default function DownloadPage() {
  return (
    <main id="main" className="checkout-result-page">
      <div className="wrap checkout-result-card" style={{ maxWidth: '640px' }}>
        <BrandMark />
        <p className="label">macOS utility</p>
        <h1>Download Bondex Notch</h1>
        <p className="lede">
          Universal build for Apple Silicon and Intel Macs running macOS 14 or later.
        </p>

        <div className="actions actions--center" style={{ margin: '24px 0' }}>
          <a
            className="btn"
            style={{ padding: '14px 28px', fontSize: '15px' }}
            href="https://github.com/RithyBondeth/Bondex-Notch/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
          >
            Download Latest Release (.dmg)
          </a>
        </div>

        <div style={{
          textAlign: 'left',
          margin: '20px auto',
          fontSize: '13.5px',
          lineHeight: '1.6',
          background: 'rgba(255, 255, 255, 0.03)',
          borderRadius: '12px',
          padding: '20px 24px',
          border: '1px solid rgba(255, 255, 255, 0.08)'
        }}>
          <h3 style={{ margin: '0 0 12px 0', fontSize: '15px', color: '#fff' }}>Quick Install Guide</h3>
          <ol style={{ paddingLeft: '20px', margin: '0 0 16px 0' }}>
            <li>Open the downloaded <code>Bondex Notch.dmg</code> file.</li>
            <li>Drag <strong>Bondex Notch</strong> into the <strong>Applications</strong> shortcut.</li>
            <li>Launch Bondex Notch from Applications.</li>
          </ol>

          <h4 style={{ margin: '16px 0 6px 0', fontSize: '13px', color: 'rgba(255, 255, 255, 0.7)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
            First launch: allow the app once
          </h4>
          <p style={{ margin: '0 0 8px 0', color: 'rgba(255, 255, 255, 0.65)', fontSize: '12.5px' }}>
            Bondex Notch is independently developed and not yet notarized by Apple, so
            macOS asks you to confirm it the first time. You only do this once.
          </p>
          <p style={{ margin: '0 0 4px 0', color: 'rgba(255, 255, 255, 0.8)', fontSize: '12.5px' }}>
            <strong>macOS 15 Sequoia and later</strong>
          </p>
          <ol style={{ paddingLeft: '20px', margin: '0 0 12px 0', color: 'rgba(255, 255, 255, 0.65)', fontSize: '12.5px' }}>
            <li>Open Bondex Notch. When macOS says it cannot verify the app, choose <strong>Done</strong>.</li>
            <li>Open <strong>System Settings → Privacy &amp; Security</strong> and scroll down to <strong>Security</strong>.</li>
            <li>Next to the message about Bondex Notch, choose <strong>Open Anyway</strong>, then confirm with your password or Touch ID.</li>
          </ol>
          <p style={{ margin: '0 0 4px 0', color: 'rgba(255, 255, 255, 0.8)', fontSize: '12.5px' }}>
            <strong>macOS 14 Sonoma</strong>
          </p>
          <p style={{ margin: '0 0 12px 0', color: 'rgba(255, 255, 255, 0.65)', fontSize: '12.5px' }}>
            In Applications, Control-click <strong>Bondex Notch</strong>, choose <strong>Open</strong>, then choose <strong>Open</strong> again.
          </p>
          <p style={{ margin: 0, color: 'rgba(255, 255, 255, 0.5)', fontSize: '12px' }}>
            Comfortable with Terminal? This does the same thing on any version:
            <br />
            <code style={{ display: 'inline-block', margin: '6px 0', padding: '4px 8px', background: 'rgba(0,0,0,0.5)', borderRadius: '4px', color: '#3CC1F6', fontFamily: 'var(--mono, monospace)' }}>
              xattr -dr com.apple.quarantine &quot;/Applications/Bondex Notch.app&quot;
            </code>
          </p>
        </div>

        <div className="actions actions--center" style={{ marginTop: '16px' }}>
          <Link className="btn btn--ghost" href="/">Return to Homepage</Link>
          <Link className="btn btn--ghost" href="/license-support/">Licence Support</Link>
        </div>
      </div>
    </main>
  );
}
