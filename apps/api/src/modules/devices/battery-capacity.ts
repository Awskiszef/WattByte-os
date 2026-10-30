// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

import type { DesignCapacitySource, FullChargeCapacityConfidence, FullChargeCapacitySource } from '../../database/repositories.js';
import { HttpError } from '../../errors/http-error.js';

/**
 * The battery fields of `POST /devices`. Two groups, stored atomically (docs/BATTERY_CAPACITY.md):
 * the design capacity of the phone MODEL and the estimated full-charge capacity of THIS battery.
 */
export interface BatteryCapacityGroups {
  designCapacityMah?: number | null;
  designCapacityWh?: number | null;
  designCapacitySource?: DesignCapacitySource | null;
  estimatedFullChargeCapacityMah?: number | null;
  estimatedFullChargeCapacityWh?: number | null;
  fullChargeCapacitySource?: FullChargeCapacitySource | null;
  fullChargeCapacityConfidence?: FullChargeCapacityConfidence | null;
}

const bad = (message: string): HttpError => HttpError.badRequest('validation', message);

/**
 * Cross-field rules the request schema cannot express. Each violation is a 400 `validation` whose message
 * names the rule; nothing is "repaired": a value without provenance is refused instead of being guessed.
 * Mirrors the CHECK constraints of migration 0006 (the database stays the last line of defence).
 *
 * Design capacity (nominal figure of the model):
 *  - a number needs a source other than `unknown`, and `unknown` carries no numbers;
 *  - `designCapacityWh` needs `designCapacityMah`;
 *  - a source other than `unknown` needs `designCapacityMah` (a claim without a value).
 *
 * Estimated full-charge capacity (extrapolated from a charge reading):
 *  - a number needs source `androidChargeCounter` and a confidence, and `unknown` carries no numbers;
 *  - `estimatedFullChargeCapacityWh` needs `estimatedFullChargeCapacityMah`;
 *  - source `androidChargeCounter` and a confidence both need `estimatedFullChargeCapacityMah`.
 *
 * `designCapacitySource: unknown` and `fullChargeCapacitySource: unknown` without numbers are valid: they
 * say "nothing known" and replace (clear) the stored group.
 */
export function validateBatteryCapacityGroups(b: BatteryCapacityGroups): void {
  const designMah = b.designCapacityMah ?? null;
  const designWh = b.designCapacityWh ?? null;
  const designSource = b.designCapacitySource ?? null;
  const hasDesignNumber = designMah != null || designWh != null;

  if (hasDesignNumber && designSource == null) {
    throw bad('designCapacityMah and designCapacityWh need a designCapacitySource');
  }
  if (designSource === 'unknown' && hasDesignNumber) {
    throw bad('designCapacitySource unknown carries no designCapacityMah or designCapacityWh');
  }
  if (designWh != null && designMah == null) {
    throw bad('designCapacityWh needs designCapacityMah');
  }
  if (designSource != null && designSource !== 'unknown' && designMah == null) {
    throw bad(`designCapacitySource ${designSource} needs designCapacityMah (use unknown when the capacity is not known)`);
  }

  const fullMah = b.estimatedFullChargeCapacityMah ?? null;
  const fullWh = b.estimatedFullChargeCapacityWh ?? null;
  const fullSource = b.fullChargeCapacitySource ?? null;
  const confidence = b.fullChargeCapacityConfidence ?? null;
  const hasFullNumber = fullMah != null || fullWh != null;

  if (hasFullNumber && fullSource == null) {
    throw bad('estimatedFullChargeCapacityMah and estimatedFullChargeCapacityWh need a fullChargeCapacitySource');
  }
  if (fullSource === 'unknown' && (hasFullNumber || confidence != null)) {
    throw bad('fullChargeCapacitySource unknown carries no estimatedFullChargeCapacity values and no fullChargeCapacityConfidence');
  }
  if (fullWh != null && fullMah == null) {
    throw bad('estimatedFullChargeCapacityWh needs estimatedFullChargeCapacityMah');
  }
  if (fullSource === 'androidChargeCounter' && fullMah == null) {
    throw bad('fullChargeCapacitySource androidChargeCounter needs estimatedFullChargeCapacityMah');
  }
  if (confidence != null && fullMah == null) {
    throw bad('fullChargeCapacityConfidence needs estimatedFullChargeCapacityMah');
  }
  if (fullMah != null && confidence == null) {
    throw bad('estimatedFullChargeCapacityMah needs a fullChargeCapacityConfidence');
  }
}
