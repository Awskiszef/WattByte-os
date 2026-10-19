import { site } from '@/config/site';
import { cn } from '@/lib/cn';

const { company } = site;

/** One line, for the footer and the legal pages. */
export function companyLine(): string {
  const a = company.address;
  return `${company.name}, ${a.street}, ${a.postalCode} ${a.city}, ${a.country}`;
}

/** The full registration block, as a definition list inside an <address>. */
export function CompanyDetails({ className }: { className?: string }) {
  const a = company.address;
  const rows: Array<[string, string]> = [
    ['Business name', company.name],
    ['Owner', company.owner],
    ['Legal form', company.legalForm],
    ['Address', `${a.street}, ${a.postalCode} ${a.city}, ${a.region}, ${a.country}`],
    ['NIP (tax id)', company.nip],
    ['EU VAT id', company.vatId],
    ['REGON', company.regon],
    ['E-mail', site.supportEmail],
  ];
  return (
    <address className={cn('not-italic', className)}>
      <dl className="divide-y divide-border rounded-lg border border-border text-sm">
        {rows.map(([label, value]) => (
          <div key={label} className="grid gap-1 px-4 py-3 sm:grid-cols-[11rem_1fr] sm:gap-4">
            <dt className="text-fg-subtle">{label}</dt>
            <dd className="text-fg tabular">
              {label === 'E-mail' ? (
                <a href={`mailto:${value}`} className="underline underline-offset-4 hover:text-fg-muted">
                  {value}
                </a>
              ) : (
                value
              )}
            </dd>
          </div>
        ))}
      </dl>
    </address>
  );
}
