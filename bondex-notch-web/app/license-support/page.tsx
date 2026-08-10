import type { Metadata } from 'next';
import LegalPage from '@/components/LegalPage';

export const metadata: Metadata = {
  title: 'Licence Support — Bondex Notch',
  description: 'Help with the Bondex Notch trial, licence keys, activation, and purchases.',
  alternates: { canonical: '/license-support/' },
};

export default function LicenseSupportPage() {
  return (
    <LegalPage
      currentPath="/license-support/"
      eyebrow="Activation help"
      title="Licence Support"
      intro="Help with the 24-hour trial, activating a purchased licence, moving to another Mac, and resolving an invalid key."
    >
      <section className="legal-callout">
        <h2>Production licences are not on sale yet</h2>
        <p>
          The website checkout is currently a preview and does not charge a card
          or issue a production licence. Until sales open, never send real card
          details through the preview or to support. Early-access questions are
          welcome by email.
        </p>
      </section>

      <section>
        <h2>Start and check your trial</h2>
        <p>
          The complete 24-hour trial starts automatically the first time Bondex
          Notch launches. Open the menu-bar icon, choose <b>Settings</b>, then
          select <b>License</b> to see whether the app is in trial, expired, or
          licensed state and how much trial time remains.
        </p>
      </section>

      <section>
        <h2>Activate a licence</h2>
        <ol>
          <li>Copy the complete licence key from your future purchase confirmation.</li>
          <li>Open Bondex Notch → Settings → License.</li>
          <li>Paste the key into the License key field and choose Apply.</li>
          <li>Confirm that the status changes to Licensed with full access.</li>
        </ol>
        <p>
          If the trial has already expired, open the notch and choose <b>Activate
          licence</b> to reach the same screen.
        </p>
      </section>

      <section>
        <h2>If a key is rejected</h2>
        <ul>
          <li>Copy and paste the key rather than typing it manually.</li>
          <li>Remove spaces before or after the key.</li>
          <li>Make sure you are using the key for Bondex Notch, not an order number.</li>
          <li>Download the current supported build before trying again.</li>
        </ul>
        <p>
          If it still fails, email support from the purchase address with your
          order number, macOS version, Bondex version, and a screenshot of the
          error. For security, do not post your full licence key publicly.
        </p>
      </section>

      <section>
        <h2>Reinstalling or moving to another Mac</h2>
        <p>
          Keep your purchase confirmation and licence key somewhere safe. Install
          the latest compatible Bondex build on the replacement Mac and apply the
          key again. If the purchase terms for your licence include a device limit
          or activation transfer and the key is rejected, contact support so the
          old activation can be reviewed.
        </p>
      </section>

      <section>
        <h2>Contact licence support</h2>
        <p>
          Email{' '}
          <a href="mailto:rithybondeth999@gmail.com?subject=Bondex%20Notch%20licence%20support">
            rithybondeth999@gmail.com
          </a>{' '}
          with the subject “Bondex Notch licence support.” Include the order
          number and technical details, but never include card details or account
          passwords. Support is provided in English and Khmer as availability
          permits.
        </p>
      </section>
    </LegalPage>
  );
}
