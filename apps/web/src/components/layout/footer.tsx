import Link from 'next/link';
import { footerColumns } from '@/config/navigation';
import { site } from '@/config/site';
import { ComingSoon } from '@/components/ui/badge';
import { companyLine } from '@/components/ui/company-details';
import { Logo } from './logo';

export function Footer() {
  const year = new Date().getFullYear();
  return (
    <footer className="border-t border-border bg-bg-elevated">
      <div className="container-x py-14 sm:py-16">
        <div className="grid gap-10 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-[1.4fr_repeat(5,minmax(0,1fr))] lg:gap-8">
          <div className="max-w-[16rem] sm:col-span-2 md:col-span-3 lg:col-span-1">
            <Logo />
            <p className="mt-4 text-sm leading-relaxed text-fg-muted">{site.tagline}</p>
          </div>
          {footerColumns.map((column) => (
            <nav key={column.title} aria-label={column.title}>
              <h2 className="text-sm font-semibold text-fg">{column.title}</h2>
              <ul className="mt-4 space-y-2.5">
                {column.links.map((link) => (
                  <li key={link.label} className="text-sm">
                    {'comingSoon' in link && link.comingSoon ? (
                      <span className="inline-flex flex-wrap items-center gap-2 text-fg-subtle">
                        {link.label}
                        <ComingSoon />
                      </span>
                    ) : (
                      <Link href={link.href} className="text-fg-muted transition-colors hover:text-fg">
                        {link.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>
        <div className="mt-14 border-t border-border pt-6 text-xs text-fg-subtle">
          <p>Operated by {companyLine()}. NIP {site.company.nip}, VAT ID {site.company.vatId}, REGON {site.company.regon}.</p>
          <div className="mt-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <p>
              © {year} {site.legalName}. All rights reserved.
            </p>
            <p>Mockups on this site show example data, not a real account.</p>
          </div>
        </div>
      </div>
    </footer>
  );
}
