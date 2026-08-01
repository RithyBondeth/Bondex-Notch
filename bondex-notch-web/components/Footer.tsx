import Image from 'next/image';

export default function Footer() {
  const contacts = [
    {
      service: 'instagram',
      icon: '/social-icons/instagram.svg',
      label: 'Instagram',
      value: '@r.bondeth',
      href: 'https://www.instagram.com/r.bondeth/',
    },
    {
      service: 'telegram',
      icon: '/social-icons/telegram.svg',
      label: 'Telegram',
      value: '@hemrithybondeth',
      href: 'https://t.me/hemrithybondeth',
    },
    {
      service: 'whatsapp',
      icon: '/social-icons/whatsapp.svg',
      label: 'WhatsApp',
      value: '+855 85 872 582',
      href: 'https://wa.me/85585872582',
    },
    {
      service: 'email',
      icon: '/social-icons/gmail.svg',
      label: 'Email',
      value: 'rithybondeth999@gmail.com',
      href: 'mailto:rithybondeth999@gmail.com?subject=Question%20about%20Bondex%20Notch',
    },
  ];

  return (
    <footer className="footer">
      <div className="wrap footer__inner">
        <div className="footer__intro">
          <span className="brand">
            <span className="brand__mark" aria-hidden="true" />
            <span className="brand__name">Bondex&nbsp;Notch</span>
          </span>
          <p>
            A calmer control center for macOS, built privately in Cambodia.
            Questions, early access, and feedback are always welcome.
          </p>
          <span className="footer__availability"><i /> Available for direct messages</span>
        </div>

        <nav className="footer__nav" aria-label="Footer navigation">
          <b>Explore</b>
          <a href="#showcase">Product tour</a>
          <a href="#efficiency">Performance</a>
          <a href="#features">Features</a>
          <a href="#pricing">Pricing</a>
          <a href="#faq">FAQ</a>
        </nav>

        <div className="footer__contacts">
          <div className="footer__contacts-head">
            <b>Contact directly</b>
            <span>Choose what works for you</span>
          </div>
          <div className="footer__contact-grid">
            {contacts.map(({ service, icon, label, value, href }) => (
              <a
                href={href}
                className="footer__contact-card"
                data-service={service}
                target={service === 'email' ? undefined : '_blank'}
                rel={service === 'email' ? undefined : 'noreferrer'}
                key={service}
              >
                <span className="footer__contact-mark" aria-hidden="true">
                  <Image src={icon} alt="" width={18} height={18} />
                </span>
                <span>
                  <b>{label}</b>
                  <small>{value}</small>
                </span>
                <i aria-hidden="true">↗</i>
              </a>
            ))}
          </div>
        </div>
      </div>

      <div className="wrap footer__bottom">
        <p className="footer__legal">Built with Swift and SwiftUI.</p>
        <p className="footer__legal">Not affiliated with Apple Inc.</p>
      </div>
    </footer>
  );
}
