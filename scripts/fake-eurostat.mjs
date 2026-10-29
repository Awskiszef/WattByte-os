// A tiny stand-in for the Eurostat dissemination API (dataset nrg_pc_204) so the e2e job and local runs do not
// depend on the public internet. It answers the exact query shape EurostatElectricityPriceProvider sends and
// serves JSON-stat 2.0 documents like the real service: the last three half-years for a few countries, and an
// EMPTY dataset (size 0 for geo) for every other country, which is how Eurostat answers an unknown geo.
//
//   node scripts/fake-eurostat.mjs [port]          # prints "listening http://127.0.0.1:<port>"
//   EUROSTAT_BASE_URL=http://127.0.0.1:<port>/eurostat/api/dissemination/statistics/1.0/data  (API env)
//
// Values are the real published 2025-S1 .. 2026-S1 household prices (national currency per kWh, all taxes, band DC)
// as returned on 2026-10-12; they are fixtures, not a data source.
import http from 'node:http';

import { isMainModule } from './is-main.mjs';

export const FIXTURE = {
  PL: [1.0827, 1.1505, 1.2724],
  DE: [0.3835, 0.3869, 0.3618],
  CZ: [7.948, 7.845, 7.0108],
};
const PERIODS = ['2025-S1', '2025-S2', '2026-S1'];
export const BASE_PATH = '/eurostat/api/dissemination/statistics/1.0/data';

export function jsonStat(geo) {
  const values = FIXTURE[geo];
  const one = (k) => ({ category: { index: { [k]: 0 } } });
  return {
    version: '2.0',
    class: 'dataset',
    label: 'Electricity prices for household consumers - bi-annual data (fixture)',
    source: 'FIXTURE',
    value: values ? Object.fromEntries(values.map((v, i) => [String(i), v])) : {},
    id: ['freq', 'siec', 'nrg_cons', 'unit', 'tax', 'currency', 'geo', 'time'],
    size: [1, 1, 1, 1, 1, 1, values ? 1 : 0, 3],
    dimension: {
      freq: one('S'),
      siec: one('E7000'),
      nrg_cons: one('KWH2500-4999'),
      unit: one('KWH'),
      tax: one('I_TAX'),
      currency: one('NAC'),
      geo: { category: { index: values ? { [geo]: 0 } : {} } },
      time: { category: { index: Object.fromEntries(PERIODS.map((p, i) => [p, i])) } },
    },
  };
}

export function startFakeEurostat(port = 0, host = '127.0.0.1') {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (url.pathname !== `${BASE_PATH}/nrg_pc_204`) {
      res.writeHead(404, { 'content-type': 'application/json' }).end(JSON.stringify({ error: [{ status: 404, label: 'unknown dataset' }] }));
      return;
    }
    const p = url.searchParams;
    const expected = { siec: 'E7000', nrg_cons: 'KWH2500-4999', unit: 'KWH', tax: 'I_TAX', currency: 'NAC' };
    const wrong = Object.entries(expected).filter(([k, v]) => p.get(k) !== v);
    if (wrong.length) {
      // The real service rejects an invalid dimension with HTTP 400 and an error list.
      res.writeHead(400, { 'content-type': 'application/json' }).end(JSON.stringify({ error: [{ status: 400, label: `INVALID_QUERY_DIMENSION ${wrong[0][0]}` }] }));
      return;
    }
    res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(jsonStat(p.get('geo') ?? '')));
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => resolve({ server, port: server.address().port, baseUrl: `http://${host}:${server.address().port}${BASE_PATH}` }));
  });
}

if (isMainModule(import.meta.url)) {
  const { baseUrl } = await startFakeEurostat(Number(process.argv[2] ?? 0));
  console.warn(`listening ${baseUrl}`);
}
