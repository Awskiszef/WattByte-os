// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

/**
 * Where an account-level value came from (`*Source` on `/me/settings`), written once and run against every repository
 * implementation (see setting-source.test.ts and db/setting-source.integration.test.ts). The device-side meaning of these
 * origins ("accountSynced", `originalSource`) is documented in docs/SETTING_SOURCES.md.
 */
import { CloudExportDocument, UserSettingsDto } from '@wattbyte/contracts';
import { describe, expect, it } from 'vitest';

import type { App } from '../src/app.js';

export interface SettingSourceFixture {
  app: App;
  /** A new account; returns the headers of its first session. */
  register(prefix: string): Promise<Record<string, string>>;
  /** Closes the app and whatever it holds (connection pools). */
  close(): Promise<void>;
}

export function describeSettingSources(label: string, fixture: () => Promise<SettingSourceFixture>, enabled = true): void {
  describe.skipIf(!enabled)(`setting sources on /me/settings (${label})`, () => {
    const put = (fx: SettingSourceFixture, headers: Record<string, string>, payload: object) =>
      fx.app.inject({ method: 'PUT', url: '/api/v1/me/settings', headers, payload });
    const get = async (fx: SettingSourceFixture, headers: Record<string, string>) => {
      const res = await fx.app.inject({ method: 'GET', url: '/api/v1/me/settings', headers });
      expect(res.statusCode).toBe(200);
      const body = res.json();
      expect(UserSettingsDto.safeParse(body).success, 'the response matches the published contract').toBe(true);
      return body as Record<string, unknown>;
    };

    it('a new account has no values and no origins', async () => {
      const fx = await fixture();
      const a = await fx.register('src-new');
      expect(await get(fx, a)).toMatchObject({
        countryCode: null,
        countryCodeSource: null,
        currencyCode: null,
        currencyCodeSource: null,
        electricityPriceMode: 'automatic',
        manualElectricityPrice: null,
        electricityPriceSource: null,
      });
      await fx.close();
    });

    it('device A detects PLN: the account stores the value and that it was detected, device B reads exactly that', async () => {
      const fx = await fixture();
      const a = await fx.register('src-detect');
      const res = await put(fx, a, { countryCode: 'PL', countryCodeSource: 'detected', currencyCode: 'PLN', currencyCodeSource: 'detected' });
      expect(res.statusCode).toBe(200);
      // Device B (the same account, another phone) pulls the same document.
      expect(await get(fx, a)).toMatchObject({ countryCode: 'PL', countryCodeSource: 'detected', currencyCode: 'PLN', currencyCodeSource: 'detected', electricityPriceSource: null });
      await fx.close();
    });

    it('device A switches PLN to EUR by hand: the new value carries "manual", the untouched country keeps "detected"', async () => {
      const fx = await fixture();
      const a = await fx.register('src-manual');
      await put(fx, a, { countryCode: 'PL', countryCodeSource: 'detected', currencyCode: 'PLN', currencyCodeSource: 'detected' });
      const res = await put(fx, a, { currencyCode: 'EUR', currencyCodeSource: 'manual' });
      expect(res.statusCode).toBe(200);
      expect(res.json()).toMatchObject({ countryCode: 'PL', countryCodeSource: 'detected', currencyCode: 'EUR', currencyCodeSource: 'manual' });
      expect(await get(fx, a)).toMatchObject({ currencyCode: 'EUR', currencyCodeSource: 'manual', countryCodeSource: 'detected' });
      await fx.close();
    });

    it('a manual tariff is stored as a decision: mode, price and origin; switching back to automatic keeps the price and records who chose', async () => {
      const fx = await fixture();
      const a = await fx.register('src-tariff');
      const manual = await put(fx, a, { electricityPriceMode: 'manual', manualElectricityPrice: 0.95, electricityPriceSource: 'manual' });
      expect(manual.statusCode).toBe(200);
      expect(await get(fx, a)).toMatchObject({ electricityPriceMode: 'manual', manualElectricityPrice: 0.95, electricityPriceSource: 'manual' });
      const automatic = await put(fx, a, { electricityPriceMode: 'automatic', manualElectricityPrice: 0.95, electricityPriceSource: 'manual' });
      expect(automatic.statusCode).toBe(200);
      expect(await get(fx, a)).toMatchObject({ electricityPriceMode: 'automatic', manualElectricityPrice: 0.95, electricityPriceSource: 'manual' });
      await fx.close();
    });

    it('a legacy migrated answer is accepted as an origin of its own', async () => {
      const fx = await fixture();
      const a = await fx.register('src-migrated');
      await put(fx, a, { currencyCode: 'PLN', currencyCodeSource: 'migratedManual', electricityPriceMode: 'manual', manualElectricityPrice: 0.8, electricityPriceSource: 'migratedManual' });
      expect(await get(fx, a)).toMatchObject({ currencyCodeSource: 'migratedManual', electricityPriceSource: 'migratedManual' });
      await fx.close();
    });

    it('"accountSynced" is not an origin: it describes how a value reaches a device, so the API refuses to store it', async () => {
      const fx = await fixture();
      const a = await fx.register('src-reject');
      for (const payload of [
        { currencyCode: 'EUR', currencyCodeSource: 'accountSynced' },
        { countryCode: 'PL', countryCodeSource: 'accountSynced' },
        { electricityPriceSource: 'accountSynced' },
        { currencyCode: 'EUR', currencyCodeSource: 'automatic' },
        { currencyCode: 'EUR', currencyCodeSource: 'psychic' },
        { currencyCode: 'EUR', currencyCodeSource: 1 },
      ]) {
        const res = await put(fx, a, payload);
        expect(res.statusCode, JSON.stringify(payload)).toBe(400);
      }
      expect(await get(fx, a)).toMatchObject({ currencyCode: null, currencyCodeSource: null });
      await fx.close();
    });

    describe('compatibility with a client that does not know origins', () => {
      it('works exactly as before: a body without any origin is valid', async () => {
        const fx = await fixture();
        const a = await fx.register('src-old');
        const res = await put(fx, a, { countryCode: 'PL', currencyCode: 'PLN', electricityPriceMode: 'manual', manualElectricityPrice: 0.95 });
        expect(res.statusCode).toBe(200);
        expect(res.json()).toMatchObject({ countryCode: 'PL', currencyCode: 'PLN', electricityPriceMode: 'manual', manualElectricityPrice: 0.95 });
        await fx.close();
      });

      it('a value written without an origin has an unknown origin: nothing is guessed', async () => {
        const fx = await fixture();
        const a = await fx.register('src-unknown');
        await put(fx, a, { countryCode: 'PL', currencyCode: 'PLN' });
        expect(await get(fx, a)).toMatchObject({ countryCode: 'PL', countryCodeSource: null, currencyCode: 'PLN', currencyCodeSource: null });
        await fx.close();
      });

      it('an origin is never carried over to a different value', async () => {
        const fx = await fixture();
        const a = await fx.register('src-carry');
        await put(fx, a, { currencyCode: 'PLN', currencyCodeSource: 'manual', electricityPriceMode: 'manual', manualElectricityPrice: 0.95, electricityPriceSource: 'manual' });
        // The old client changes the values and says nothing about them.
        await put(fx, a, { currencyCode: 'EUR', electricityPriceMode: 'manual', manualElectricityPrice: 1.5 });
        expect(await get(fx, a)).toMatchObject({ currencyCode: 'EUR', currencyCodeSource: null, manualElectricityPrice: 1.5, electricityPriceSource: null });
        await fx.close();
      });

      it('an origin survives while the value it describes is unchanged, whoever writes (an old client echoing the account back)', async () => {
        const fx = await fixture();
        const a = await fx.register('src-echo');
        await put(fx, a, { countryCode: 'PL', countryCodeSource: 'detected', currencyCode: 'EUR', currencyCodeSource: 'manual', electricityPriceMode: 'manual', manualElectricityPrice: 0.95, electricityPriceSource: 'manual' });
        // An old client echoes the account back without saying anything about origins: nothing changed, so nothing is forgotten.
        await put(fx, a, { countryCode: 'PL', currencyCode: 'EUR', electricityPriceMode: 'manual', manualElectricityPrice: 0.95 });
        expect(await get(fx, a)).toMatchObject({ countryCodeSource: 'detected', currencyCodeSource: 'manual', electricityPriceSource: 'manual' });
        // Then it changes the country only: that value alone loses its origin.
        await put(fx, a, { countryCode: 'DE' });
        expect(await get(fx, a)).toMatchObject({
          countryCode: 'DE',
          countryCodeSource: null,
          currencyCode: 'EUR',
          currencyCodeSource: 'manual',
          electricityPriceMode: 'manual',
          manualElectricityPrice: 0.95,
          electricityPriceSource: 'manual',
        });
        await fx.close();
      });
    });

    it('generated clients send every unset field as null: a null origin is "not given", and the value keeps the origin it has', async () => {
      const fx = await fixture();
      const a = await fx.register('src-nulls');
      await put(fx, a, { currencyCode: 'EUR', currencyCodeSource: 'manual' });
      const res = await put(fx, a, {
        countryCode: null,
        countryCodeSource: null,
        currencyCode: 'EUR',
        currencyCodeSource: null,
        electricityPriceMode: null,
        manualElectricityPrice: null,
        electricityPriceSource: null,
      });
      expect(res.statusCode).toBe(200);
      expect(await get(fx, a)).toMatchObject({ countryCode: null, countryCodeSource: null, currencyCode: 'EUR', currencyCodeSource: 'manual', electricityPriceSource: null });
      await fx.close();
    });

    it('a cleared value has no origin, even when one is sent with it', async () => {
      const fx = await fixture();
      const a = await fx.register('src-clear');
      await put(fx, a, { countryCode: 'PL', countryCodeSource: 'manual' });
      await put(fx, a, { countryCode: null, countryCodeSource: 'manual' });
      expect(await get(fx, a)).toMatchObject({ countryCode: null, countryCodeSource: null });
      await fx.close();
    });

    it('an origin can be recorded for a value that is already stored (the user confirms it)', async () => {
      const fx = await fixture();
      const a = await fx.register('src-confirm');
      await put(fx, a, { currencyCode: 'PLN' });
      await put(fx, a, { currencyCode: 'PLN', currencyCodeSource: 'manual' });
      expect(await get(fx, a)).toMatchObject({ currencyCode: 'PLN', currencyCodeSource: 'manual' });
      await fx.close();
    });

    it('a rejected update changes nothing, origins included', async () => {
      const fx = await fixture();
      const a = await fx.register('src-atomic');
      await put(fx, a, { currencyCode: 'PLN', currencyCodeSource: 'detected' });
      const bad = await put(fx, a, { currencyCode: 'EUR', currencyCodeSource: 'manual', electricityPriceMode: 'manual' });
      expect(bad.statusCode).toBe(400);
      expect(await get(fx, a)).toMatchObject({ currencyCode: 'PLN', currencyCodeSource: 'detected' });
      await fx.close();
    });

    it('origins belong to the account: another account never sees them', async () => {
      const fx = await fixture();
      const a = await fx.register('src-iso-a');
      const b = await fx.register('src-iso-b');
      await put(fx, a, { currencyCode: 'EUR', currencyCodeSource: 'manual', electricityPriceMode: 'manual', manualElectricityPrice: 0.95, electricityPriceSource: 'manual' });
      expect(await get(fx, b)).toMatchObject({ currencyCode: null, currencyCodeSource: null, electricityPriceMode: 'automatic', manualElectricityPrice: null, electricityPriceSource: null });
      await put(fx, b, { currencyCode: 'GBP', currencyCodeSource: 'detected' });
      expect(await get(fx, a)).toMatchObject({ currencyCode: 'EUR', currencyCodeSource: 'manual' });
      await fx.close();
    });

    it('the account export carries the origins', async () => {
      const fx = await fixture();
      const a = await fx.register('src-export');
      await put(fx, a, { countryCode: 'PL', countryCodeSource: 'detected', currencyCode: 'EUR', currencyCodeSource: 'manual', electricityPriceMode: 'manual', manualElectricityPrice: 0.95, electricityPriceSource: 'migratedManual' });
      const res = await fx.app.inject({ method: 'GET', url: '/api/v1/me/export', headers: a });
      expect(res.statusCode).toBe(200);
      const doc = CloudExportDocument.parse(res.json());
      expect(doc.settings).toMatchObject({
        countryCode: 'PL',
        countryCodeSource: 'detected',
        currencyCode: 'EUR',
        currencyCodeSource: 'manual',
        electricityPriceMode: 'manual',
        manualElectricityPrice: 0.95,
        electricityPriceSource: 'migratedManual',
      });
      await fx.close();
    });
  });
}
