// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { ReactNode } from 'react';
import { SectionHeading } from './section-heading';

/** Top of every secondary page: the h1, one paragraph, optional actions. */
export function PageHeader({ title, copy, children }: { title: string; copy?: ReactNode; children?: ReactNode }) {
  return (
    <div className="container-x pb-6 pt-14 sm:pt-20">
      <SectionHeading as="h1" title={title} copy={copy} />
      {children ? <div className="mt-8 flex flex-wrap gap-3">{children}</div> : null}
    </div>
  );
}
