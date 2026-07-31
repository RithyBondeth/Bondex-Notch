import type { CSSProperties } from 'react';
import { panelStates } from '@/content/site';

/**
 * The three states are a real progression and each one is a real width, so the
 * diagram is the notch itself, drawn to scale. The dimensions come from the
 * content module rather than the stylesheet, because they are facts about the
 * product, not styling.
 */
export default function States() {
  return (
    <section id="how" className="section">
      <div className="wrap">
        <header className="head head--center">
          <p className="label label--light">One gesture</p>
          <h2 className="title title--light">Three states, drawn to scale</h2>
          <p className="lede lede--light">
            The panel is the same object throughout. It only ever changes size.
          </p>
        </header>

        <ol className="states">
          {panelStates.map(({ id, title, body, width, height, radius }) => (
            <li className="state" key={id}>
              <div className="state__art" aria-hidden="true">
                <span
                  className="mini"
                  style={
                    {
                      '--w': `${width}px`,
                      '--h': `${height}px`,
                      '--r': `${radius}px`,
                    } as CSSProperties
                  }
                />
              </div>
              <h3>{title}</h3>
              <p>{body}</p>
            </li>
          ))}
        </ol>

        <div className="callout">
          <p className="label">Displays</p>
          <h3>No notch? No problem.</h3>
          <p>
            On external displays and pre-2021 Macs, Bondex draws its own pill in
            the same place and behaves identically. It follows the built-in
            display when you plug in, and re-measures itself whenever your
            display arrangement changes.
          </p>
        </div>
      </div>
    </section>
  );
}
