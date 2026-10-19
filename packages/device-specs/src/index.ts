/**
 * Device specification catalog: nominal battery capacity per phone model.
 *
 * One JSON file is the single source of truth (`devices.json`). The mobile app
 * ships a copy as an asset (offline, last known catalog) and the API serves
 * the same file through `GET /api/v1/devices/specifications/:identifier` for
 * models that are newer than the installed app. `scripts/check-device-specs.mjs`
 * keeps both copies identical.
 *
 * Every figure is a DESIGN (nominal) capacity of the phone model. It says nothing
 * about the wear of a particular battery and is never a measurement: the
 * app's estimated full-charge capacity is a separate fact (docs/BATTERY_CAPACITY.md).
 *
 * No value here is guessed: a model without a documented figure is simply
 * absent, and lookups answer `null` (the app then says "unknown").
 */
import catalog from './devices.json' with { type: 'json' };

export interface CatalogEntry {
  manufacturer: string;
  model: string;
  /** Exact identifiers (iOS `utsname.machine`, Android `Build.MODEL`). */
  identifiers?: string[];
  /** Android model codes carry regional suffixes (SM-S921B / SM-S921U); a prefix covers them. */
  identifierPrefixes?: string[];
  /** Design (nominal) capacity of the model in mAh, as published. */
  designCapacityMah: number;
  /** Design (nominal) energy in Wh; present only where a published figure exists. */
  designCapacityWh?: number;
  remark?: string;
}

export interface DeviceCatalog {
  version: string;
  notes: string;
  devices: CatalogEntry[];
}

export interface DeviceSpecification {
  manufacturer: string;
  model: string;
  modelIdentifier: string;
  /** Design (nominal) capacity of the model in mAh. Never a measurement of one battery. */
  designCapacityMah: number;
  /** Design (nominal) energy in Wh when a published figure exists, otherwise null. */
  designCapacityWh: number | null;
  /** Nominal voltage = design Wh / design Ah when both are published, otherwise null (the catalog never guesses a voltage). */
  nominalVoltage: number | null;
  catalogVersion: string;
}

export const DEVICE_CATALOG: DeviceCatalog = catalog as DeviceCatalog;

const normalize = (s: string): string => s.trim().toLowerCase().replace(/\s+/g, ' ');

/** Longest identifier the API accepts; anything longer cannot be a model code. */
export const MAX_IDENTIFIER_LENGTH = 64;

/**
 * Finds the entry for a model identifier: exact identifiers first, then prefixes,
 * longest prefix winning. Case-insensitive; `null` when the catalog has no figure.
 */
export function lookupDeviceSpecification(identifier: string, source: DeviceCatalog = DEVICE_CATALOG): DeviceSpecification | null {
  const id = normalize(identifier);
  if (!id || id.length > MAX_IDENTIFIER_LENGTH) return null;
  let best: { entry: CatalogEntry; score: number } | null = null;
  for (const entry of source.devices) {
    if (entry.identifiers?.some((i) => normalize(i) === id)) {
      best = { entry, score: Number.MAX_SAFE_INTEGER };
      break;
    }
    for (const prefix of entry.identifierPrefixes ?? []) {
      const p = normalize(prefix);
      if (id.startsWith(p) && (!best || p.length > best.score)) best = { entry, score: p.length };
    }
  }
  if (!best) return null;
  const { entry } = best;
  const wh = entry.designCapacityWh ?? null;
  return {
    manufacturer: entry.manufacturer,
    model: entry.model,
    modelIdentifier: identifier.trim(),
    designCapacityMah: entry.designCapacityMah,
    designCapacityWh: wh,
    nominalVoltage: wh == null ? null : Math.round((wh / (entry.designCapacityMah / 1000)) * 100) / 100,
    catalogVersion: source.version,
  };
}
