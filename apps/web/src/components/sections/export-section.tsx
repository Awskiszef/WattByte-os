import { Section } from '@/components/ui/section';
import { SectionHeading } from '@/components/ui/section-heading';
import { exportSection } from '@/config/features';

const csvHeader = 'day,mobile_rx_bytes,mobile_tx_bytes,wifi_rx_bytes,wifi_tx_bytes,total_bytes,estimated';
const csvRow = '2026-10-19,612480102,187620442,9833214007,2512890110,13146204661,false';

export function ExportSection() {
  return (
    <Section id="export" className="scroll-mt-16 border-t border-border">
      <div className="container-x grid gap-12 lg:grid-cols-2 lg:items-center">
        <div>
          <SectionHeading title={exportSection.headline} copy={exportSection.copy} />
          <dl className="mt-8 grid gap-5 sm:grid-cols-2">
            {exportSection.formats.map((f) => (
              <div key={f.label} className="rounded-lg border border-border p-4">
                <dt className="text-sm font-semibold">{f.label}</dt>
                <dd className="mt-1 text-sm text-fg-muted">{f.detail}</dd>
              </div>
            ))}
          </dl>
          <p className="mt-6 text-sm text-fg-muted">{exportSection.cloud}</p>
        </div>
        <figure className="overflow-hidden rounded-xl border border-border bg-bg-elevated">
          <figcaption className="flex items-center justify-between border-b border-border px-4 py-2.5 text-xs text-fg-subtle">
            <span>wattbyte-data.csv</span>
            <span>Example row</span>
          </figcaption>
          <pre className="overflow-x-auto p-4 font-mono text-[12px] leading-relaxed text-fg-muted">
            <code>
              {csvHeader}
              {'\n'}
              <span className="text-fg">{csvRow}</span>
            </code>
          </pre>
        </figure>
      </div>
    </Section>
  );
}
