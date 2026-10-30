# API compatibility (`/api/v1`)

Phones in the field keep running the app they were given while the server moves on. The published contract
(`packages/contracts/openapi/openapi.json`) may therefore only **grow** inside `/api/v1`.

## Allowed in `/api/v1`

* new routes, new optional request properties, new optional query parameters;
* new response properties;
* new members of a **response** enum. The generated Dart client reads a member it does not know as
  `unknownDefaultOpenApi` instead of failing (`scripts/dart-client-postprocess.mjs`, audit E-03 / G-08). An app must
  decide what an unknown member means for it and never treat it as a real one (an unknown plan is never premium).

## Breaking (needs `/api/v2` or a new route)

removing or renaming a route, a property, a query parameter or an enum member; a new **required** request property or
parameter; narrowing a type; making an always-present response property optional; removing a success status.

## The gate

`scripts/check-openapi-compat.mjs <baseline.json>` compares the current document with a baseline and exits 1 on a
breaking change. CI runs it on pull requests against `origin/<base branch>`; locally:

```bash
git show origin/main:packages/contracts/openapi/openapi.json > /tmp/base.json && pnpm openapi:compat /tmp/base.json
```

Run against the snapshot taken before the audit remediation it reports only additive changes (`GET /ready` gained
`schema`, session management routes were added).

## Not covered

The gate reads the OpenAPI document, not behaviour: a changed meaning of an existing field, a tightened validation or a
new error code are not detected. Old-client-against-new-server tests (a recorded old client run) do not exist yet.
Minimum-version signalling (F-11) is a separate item.
