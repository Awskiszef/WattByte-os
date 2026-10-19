import { describe, expect, it } from 'vitest';

import { csvField, DAILY_USAGE_CSV_HEADER, dailyUsageCsv, toCsv } from '../src/modules/cloud/csv.js';
import { exportDisposition } from '../src/modules/cloud/export.js';
import { parseCsv } from './cloud-support.js';

describe('CSV writer (RFC 4180)', () => {
  it('quotes exactly the fields that need it and doubles embedded quotes', () => {
    expect(csvField('plain')).toBe('plain');
    expect(csvField('')).toBe('');
    expect(csvField('a,b')).toBe('"a,b"');
    expect(csvField('say "hi"')).toBe('"say ""hi"""');
    expect(csvField('two\nlines')).toBe('"two\nlines"');
    expect(csvField('cr\rhere')).toBe('"cr\rhere"');
    expect(csvField('crlf\r\nhere')).toBe('"crlf\r\nhere"');
    expect(csvField('"')).toBe('""""');
    expect(csvField(' padded ')).toBe(' padded ');
    expect(csvField(12.5)).toBe('12.5');
    expect(csvField(0)).toBe('0');
    expect(csvField(-3)).toBe('-3');
    expect(csvField(true)).toBe('true');
    expect(csvField(false)).toBe('false');
  });

  it('refuses numbers a spreadsheet would read as text or errors', () => {
    for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) expect(() => csvField(bad)).toThrow(RangeError);
  });

  it('writes CRLF records with a trailing CRLF, and a header-only file for no rows', () => {
    expect(toCsv(['a', 'b'], [[1, 'x'], [2, 'y']])).toBe('a,b\r\n1,x\r\n2,y\r\n');
    expect(toCsv(['a', 'b'], [])).toBe('a,b\r\n');
  });

  it('round-trips hostile and non-ASCII text through an independent RFC 4180 reader, UTF-8 included', () => {
    const nasty = [
      'Zażółć gęślą jaźń',
      '日本語, テキスト',
      'battery 🔋 "100%"',
      'line1\r\nline2\nline3',
      '=SUM(A1:A2)',
      ',,,',
      '""',
      '  spaces  ',
      '',
      'trailing quote"',
      '\ttab',
    ];
    const csv = toCsv(['text', 'n'], nasty.map((t, i) => [t, i]));
    const parsed = parseCsv(csv);
    expect(parsed[0]).toEqual(['text', 'n']);
    expect(parsed.slice(1).map((r) => r[0])).toEqual(nasty);
    expect(parsed.slice(1).map((r) => r[1])).toEqual(nasty.map((_, i) => String(i)));
    // UTF-8 on the wire: encode and decode again without loss, no BOM.
    const bytes = Buffer.from(csv, 'utf8');
    expect(bytes.subarray(0, 3).toString('hex')).not.toBe('efbbbf');
    expect(bytes.toString('utf8')).toBe(csv);
  });

  it('the reader used as oracle rejects malformed CSV (so the round trips above mean something)', () => {
    expect(() => parseCsv('a,"b\r\n')).toThrow();
    expect(() => parseCsv('a,b\n')).toThrow();
    expect(() => parseCsv('a,b"c"\r\n')).toThrow();
    expect(() => parseCsv('"a"b,c\r\n')).toThrow();
  });

  it('writes the daily usage with a fixed header and one record per row', () => {
    const rows = [
      { deviceId: '11111111-1111-4111-8111-111111111111', date: '2026-10-12', mobileBytes: 10, wifiBytes: 20, chargedWh: 1.5, wallWh: 1.75, chargingSessions: 1, estimatedCost: 0.0012, currency: 'PLN', dataEstimated: false, energyEstimated: true },
    ];
    expect(dailyUsageCsv(rows)).toBe(
      `${DAILY_USAGE_CSV_HEADER.join(',')}\r\n2026-10-12,11111111-1111-4111-8111-111111111111,10,20,1.5,1.75,1,0.0012,PLN,false,true\r\n`,
    );
    expect(DAILY_USAGE_CSV_HEADER).toEqual(['date', 'deviceId', 'mobileBytes', 'wifiBytes', 'chargedWh', 'wallWh', 'chargingSessions', 'estimatedCost', 'currency', 'dataEstimated', 'energyEstimated']);
    expect(dailyUsageCsv([])).toBe(`${DAILY_USAGE_CSV_HEADER.join(',')}\r\n`);
  });
});

describe('export file name', () => {
  it('is wattbyte-export-YYYY-MM-DD.<ext> with the UTC date', () => {
    expect(exportDisposition(new Date('2026-10-13T23:59:59.999Z'), 'json')).toBe('attachment; filename="wattbyte-export-2026-10-13.json"');
    expect(exportDisposition(new Date('2026-01-02T00:00:00.000Z'), 'csv')).toBe('attachment; filename="wattbyte-export-2026-01-02.csv"');
    // 23:30 on the 13th at UTC-2 is already 01:30 on the 14th in UTC; the file name uses UTC.
    expect(exportDisposition(new Date('2026-10-13T23:30:00.000-02:00'), 'json')).toContain('2026-10-14');
  });
});
