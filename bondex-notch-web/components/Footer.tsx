export default function Footer() {
  return (
    <footer className="footer">
      <div className="wrap footer__inner">
        <span className="brand">
          <span className="brand__mark" aria-hidden="true" />
          <span className="brand__name">Bondex&nbsp;Notch</span>
        </span>
        <p className="footer__legal">
          Built with Swift and SwiftUI. Not affiliated with Apple Inc.
        </p>
        <a className="footer__contact" href="#contact">Contact</a>
      </div>
    </footer>
  );
}
