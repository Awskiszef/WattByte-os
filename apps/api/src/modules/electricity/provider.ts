// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { ElectricityPriceSource } from '../../database/repositories.js';

/** A household price straight from a source, before caching. */
export interface ElectricityPriceResult {
  countryCode: string;
  currency: string;
  /** Per kWh, in `currency`. */
  pricePerKwh: number;
  /** Reporting period as the source names it (Eurostat: `2026-S1`). */
  period: string;
  source: ElectricityPriceSource;
  includesTaxes: boolean | null;
  includesNetworkCosts: boolean | null;
}

/**
 * Household (consumer) electricity price lookups. Implementations must return
 * end-user prices only: never a spot, day-ahead or wholesale market price, which
 * is not what a household pays for charging a phone.
 */
export interface ElectricityPriceProvider {
  readonly id: ElectricityPriceSource;
  /** `null` when the source has no household price for that country. Throws on transport/parse failure. */
  getHouseholdPrice(countryCode: string): Promise<ElectricityPriceResult | null>;
}
