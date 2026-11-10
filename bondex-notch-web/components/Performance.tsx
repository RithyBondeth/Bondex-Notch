const efficiencyFacts = [
  {
    value: '2 sec',
    label: 'System refresh',
    detail: 'CPU, memory, power and network sampling runs as a background utility task.',
  },
  {
    value: '0',
    label: 'Web runtimes',
    detail: 'No Electron process and no embedded web view sitting behind the panel.',
  },
  {
    value: 'Off',
    label: 'Means stopped',
    detail: 'Disable a widget and its service stops sampling instead of merely hiding it.',
  },
  {
    value: 'Local',
    label: 'By default',
    detail: 'Core widgets read your Mac directly without uploading their activity.',
  },
];

export default function Performance() {
  return (
    <section id="efficiency" className="section efficiency">
      <div className="wrap">
        <div className="efficiency__panel">
          <div className="efficiency__copy">
            <p className="label">Small footprint</p>
            <h2 className="title">Useful at a glance. Quiet the rest of the time.</h2>
            <p className="lede">
              Bondex is designed for low CPU overhead from the beginning—not
              wrapped in a browser engine after the fact. Native services do one
              focused job, update at a deliberate cadence, and stop when you turn
              their widget off.
            </p>
            <div className="efficiency__status">
              <span aria-hidden="true"><i /></span>
              <div>
                <b>Low-overhead architecture</b>
                <small>Swift + SwiftUI · background utility sampling</small>
              </div>
            </div>
          </div>

          <div className="efficiency__facts" aria-label="Bondex efficiency details">
            {efficiencyFacts.map(({ value, label, detail }) => (
              <article className="efficiency__fact" key={label}>
                <strong>{value}</strong>
                <span>{label}</span>
                <p>{detail}</p>
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
