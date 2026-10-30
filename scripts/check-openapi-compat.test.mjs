// Copyright 2026 ATLASHC Paweł Dolatowski
// SPDX-License-Identifier: Apache-2.0

// node --test scripts/check-openapi-compat.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

import { compareContracts } from './check-openapi-compat.mjs';

const doc = (over = {}) => ({
  paths: {
    '/api/v1/me': {
      get: { responses: { 200: { content: { 'application/json': { schema: { $ref: '#/components/schemas/User' } } } } } },
      put: {
        requestBody: { required: true, content: { 'application/json': { schema: { $ref: '#/components/schemas/Update' } } } },
        responses: { 200: { content: { 'application/json': { schema: { $ref: '#/components/schemas/User' } } } } },
      },
    },
  },
  components: {
    schemas: {
      User: { type: 'object', required: ['id', 'plan'], properties: { id: { type: 'string' }, plan: { type: 'string', enum: ['free', 'premium'] }, name: { type: 'string' } } },
      Update: { type: 'object', required: ['name'], properties: { name: { type: 'string' }, tone: { type: 'string', enum: ['a', 'b'] } } },
      ...over,
    },
  },
});
const clone = (d) => JSON.parse(JSON.stringify(d));

describe('compareContracts', () => {
  it('an identical contract is compatible', () => {
    const r = compareContracts(doc(), doc());
    assert.deepEqual(r.breaking, []);
  });

  it('additive changes are notes, not breaking', () => {
    const n = clone(doc());
    n.components.schemas.User.properties.extra = { type: 'string' };
    n.components.schemas.User.properties.plan.enum.push('team');
    n.components.schemas.Update.properties.optionalNew = { type: 'string' };
    n.paths['/api/v1/new'] = { get: { responses: { 200: {} } } };
    const r = compareContracts(doc(), n);
    assert.deepEqual(r.breaking, []);
    assert.ok(r.notes.some((x) => x.includes('team')));
    assert.ok(r.notes.some((x) => x.includes('GET /api/v1/new')));
  });

  it('a removed route, a removed response field, a type change and a response field turning optional break', () => {
    const n = clone(doc());
    delete n.paths['/api/v1/me'].put;
    delete n.components.schemas.User.properties.name;
    n.components.schemas.User.properties.id = { type: 'integer' };
    n.components.schemas.User.required = ['plan'];
    const r = compareContracts(doc(), n).breaking.join('\n');
    assert.match(r, /PUT \/api\/v1\/me: removed/);
    assert.match(r, /property removed/);
    assert.match(r, /type string -> integer/);
    assert.match(r, /was always present, now optional/);
  });

  it('a removed enum member breaks; a new required request property breaks; a request field removed breaks', () => {
    const n = clone(doc());
    n.components.schemas.User.properties.plan.enum = ['free'];
    n.components.schemas.Update.required = ['name', 'newRequired'];
    n.components.schemas.Update.properties.newRequired = { type: 'string' };
    delete n.components.schemas.Update.properties.tone;
    const r = compareContracts(doc(), n).breaking.join('\n');
    assert.match(r, /enum member\(s\) removed: premium/);
    assert.match(r, /newRequired: new REQUIRED property/);
    assert.match(r, /tone: property removed/);
  });

  it('a new required parameter breaks, an optional one does not', () => {
    const o = doc();
    o.paths['/api/v1/me'].get.parameters = [];
    const n = clone(o);
    n.paths['/api/v1/me'].get.parameters = [{ name: 'q', in: 'query', required: false }];
    assert.deepEqual(compareContracts(o, n).breaking, []);
    n.paths['/api/v1/me'].get.parameters = [{ name: 'q', in: 'query', required: true }];
    assert.match(compareContracts(o, n).breaking.join(), /new REQUIRED parameter query:q/);
  });

  it('the repo\'s own contract is compatible with itself', () => {
    const spec = JSON.parse(readFileSync(new URL('../packages/contracts/openapi/openapi.json', import.meta.url), 'utf8'));
    assert.deepEqual(compareContracts(spec, spec).breaking, []);
  });
});
