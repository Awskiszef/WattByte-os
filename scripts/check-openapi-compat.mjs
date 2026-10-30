// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// Backward-compatibility gate for /api/v1 (audit E-14): the apps already installed keep calling the NEXT server, so the
// published contract may only grow. Compares a baseline OpenAPI document (the one released / on the base branch) with the
// current one and lists every change an installed client could not survive.
//
//   node scripts/check-openapi-compat.mjs <baseline.json> [current.json]      (current defaults to the repo's)
//   git show origin/main:packages/contracts/openapi/openapi.json > /tmp/base.json && node scripts/check-openapi-compat.mjs /tmp/base.json
//
// Breaking: a removed path or method; a removed success status; in a REQUEST a new required property, a removed property
// (the schemas are strict), a narrowed type, a removed enum member; in a RESPONSE a removed property, a property that was
// required and no longer is, a changed type, a removed enum member. Allowed (reported as notes): new paths, optional request
// properties, new response properties, new enum members of a RESPONSE (the Dart client reads an unknown member as
// `unknownDefaultOpenApi`, see docs/API_COMPATIBILITY.md).
//
// Exit codes: 0 compatible, 1 breaking changes, 2 usage error.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Resolves `$ref` and merges `allOf`; returns a plain schema object. */
function resolve(doc, schema, seen = new Set()) {
  if (!schema || typeof schema !== 'object') return {};
  if (schema.$ref) {
    if (seen.has(schema.$ref)) return {};
    const name = schema.$ref.replace('#/components/schemas/', '');
    return resolve(doc, doc.components?.schemas?.[name], new Set([...seen, schema.$ref]));
  }
  return schema;
}

const typeOf = (s) => (Array.isArray(s.type) ? [...s.type].sort().join('|') : (s.type ?? (s.enum ? 'enum' : s.properties ? 'object' : 'any')));

function compareSchema(oldDoc, oldS, newDoc, newS, where, side, out, depth = 0) {
  if (depth > 8) return;
  const o = resolve(oldDoc, oldS);
  const n = resolve(newDoc, newS);
  if (typeOf(o) !== typeOf(n) && typeOf(o) !== 'any' && typeOf(n) !== 'any') {
    // number -> integer narrowing in a request, or anything else changing in a response, breaks a client.
    out.breaking.push(`${where}: type ${typeOf(o)} -> ${typeOf(n)}`);
    return;
  }
  if (o.enum) {
    const removed = o.enum.filter((v) => !(n.enum ?? []).includes(v));
    const added = (n.enum ?? []).filter((v) => !o.enum.includes(v));
    if (removed.length) out.breaking.push(`${where}: enum member(s) removed: ${removed.join(', ')}`);
    if (added.length) {
      if (side === 'request') out.notes.push(`${where}: enum member(s) added (request): ${added.join(', ')}`);
      else out.notes.push(`${where}: enum member(s) added (response, old clients read them as unknown): ${added.join(', ')}`);
    }
  }
  if (o.properties || n.properties) {
    const oldReq = new Set(o.required ?? []);
    const newReq = new Set(n.required ?? []);
    for (const key of Object.keys(o.properties ?? {})) {
      if (!n.properties?.[key]) {
        out.breaking.push(`${where}.${key}: property removed`);
        continue;
      }
      if (side === 'response' && oldReq.has(key) && !newReq.has(key)) out.breaking.push(`${where}.${key}: was always present, now optional`);
      compareSchema(oldDoc, o.properties[key], newDoc, n.properties[key], `${where}.${key}`, side, out, depth + 1);
    }
    for (const key of Object.keys(n.properties ?? {})) {
      if (o.properties?.[key]) continue;
      if (side === 'request' && newReq.has(key)) out.breaking.push(`${where}.${key}: new REQUIRED property`);
      else out.notes.push(`${where}.${key}: property added`);
    }
  }
  if (o.items && n.items) compareSchema(oldDoc, o.items, newDoc, n.items, `${where}[]`, side, out, depth + 1);
}

export function compareContracts(oldDoc, newDoc) {
  const out = { breaking: [], notes: [] };
  for (const [url, methods] of Object.entries(oldDoc.paths ?? {})) {
    for (const [method, op] of Object.entries(methods)) {
      if (!['get', 'post', 'put', 'patch', 'delete'].includes(method)) continue;
      const label = `${method.toUpperCase()} ${url}`;
      const next = newDoc.paths?.[url]?.[method];
      if (!next) {
        out.breaking.push(`${label}: removed`);
        continue;
      }
      const oldBody = op.requestBody?.content?.['application/json']?.schema;
      const newBody = next.requestBody?.content?.['application/json']?.schema;
      if (oldBody && newBody) compareSchema(oldDoc, oldBody, newDoc, newBody, `${label} request`, 'request', out);
      else if (!oldBody && newBody && next.requestBody?.required) out.breaking.push(`${label}: now requires a body`);
      for (const [status, res] of Object.entries(op.responses ?? {})) {
        if (!/^2\d\d$/.test(status)) continue;
        const nextRes = next.responses?.[status];
        if (!nextRes) {
          out.breaking.push(`${label}: success response ${status} removed`);
          continue;
        }
        const o = res.content?.['application/json']?.schema;
        const n = nextRes.content?.['application/json']?.schema;
        if (o && n) compareSchema(oldDoc, o, newDoc, n, `${label} ${status}`, 'response', out);
      }
      for (const p of op.parameters ?? []) {
        const same = (next.parameters ?? []).find((q) => q.name === p.name && q.in === p.in);
        if (!same) out.breaking.push(`${label}: parameter ${p.in}:${p.name} removed`);
      }
      for (const q of next.parameters ?? []) {
        const had = (op.parameters ?? []).find((p) => p.name === q.name && p.in === q.in);
        if (!had && q.required) out.breaking.push(`${label}: new REQUIRED parameter ${q.in}:${q.name}`);
      }
    }
  }
  for (const [url, methods] of Object.entries(newDoc.paths ?? {})) {
    for (const method of Object.keys(methods)) {
      if (!oldDoc.paths?.[url]?.[method]) out.notes.push(`${method.toUpperCase()} ${url}: added`);
    }
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [baseline, current] = process.argv.slice(2);
  if (!baseline) {
    console.error('usage: node scripts/check-openapi-compat.mjs <baseline.json> [current.json]');
    process.exit(2);
  }
  const read = (f) => JSON.parse(readFileSync(f, 'utf8'));
  const result = compareContracts(read(baseline), read(current ?? path.join(root, 'packages', 'contracts', 'openapi', 'openapi.json')));
  for (const n of result.notes) console.warn(`note:     ${n}`);
  for (const b of result.breaking) console.error(`BREAKING: ${b}`);
  if (result.breaking.length > 0) {
    console.error(`\n${result.breaking.length} breaking change(s) for installed apps. Add a new version (/api/v2) or make the change additive.`);
    process.exit(1);
  }
  console.warn(`compatible with the baseline (${result.notes.length} additive change(s)).`);
}
