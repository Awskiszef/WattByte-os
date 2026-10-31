// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * Who operates this deployment of the website: the business behind the legal pages, the footer and the About page.
 *
 * PLACEHOLDERS. The legal pages (privacy policy, terms, contact) print these values; before you deploy the site, replace
 * every one of them with the real details of the business that operates YOUR deployment. Nothing here identifies a real
 * person or company.
 *
 * This is the ONE file that holds business identifiers (tax id, registry number, postal address) and the named person on
 * the About page. Everything else reads it through `site.company` and `aboutPeople.founder`.
 */
export const operator = {
  company: {
    name: 'Example Operator',
    owner: 'Example Owner',
    legalForm: 'Sole proprietorship (placeholder)',
    nip: '0000000000',
    vatId: 'PL0000000000',
    regon: '000000000',
    address: {
      street: 'Example Street 1',
      postalCode: '00-000',
      city: 'Example City',
      region: 'Example Region',
      country: 'Poland',
      countryCode: 'PL',
    },
  },
  founder: {
    name: 'Example Maintainer',
    role: 'Building WattByte',
    copy: 'Leads WattByte from product to code. The point of the project is a simple one: the numbers a phone already has should be readable by the person holding it.',
  },
} as const;
