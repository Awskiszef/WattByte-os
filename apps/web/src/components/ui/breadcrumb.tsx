// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import Link from 'next/link';
import { JsonLd } from './json-ld';
import { absoluteUrl } from '@/lib/seo';

type Crumb = { label: string; href: string };

/** A visible trail plus the matching BreadcrumbList structured data. */
export function Breadcrumb({ items }: { items: Crumb[] }) {
  const last = items.length - 1;
  return (
    <>
      <nav aria-label="Breadcrumb" className="container-x pt-6">
        <ol className="flex flex-wrap items-center gap-2 text-sm text-fg-subtle">
          {items.map((item, i) => (
            <li key={item.href} className="flex items-center gap-2">
              {i === last ? (
                <span aria-current="page" className="text-fg-muted">
                  {item.label}
                </span>
              ) : (
                <Link href={item.href} className="transition-colors hover:text-fg">
                  {item.label}
                </Link>
              )}
              {i < last ? <span aria-hidden="true">/</span> : null}
            </li>
          ))}
        </ol>
      </nav>
      <JsonLd
        data={{
          '@context': 'https://schema.org',
          '@type': 'BreadcrumbList',
          itemListElement: items.map((item, i) => ({
            '@type': 'ListItem',
            position: i + 1,
            name: item.label,
            item: absoluteUrl(item.href),
          })),
        }}
      />
    </>
  );
}
