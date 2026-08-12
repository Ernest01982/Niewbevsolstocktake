# AI Stock Take Control System

Version 1 is an offline-first, multi-company stock-taking SaaS. This repository currently contains the engineering, tenancy/security, product/import, lifecycle, and offline counting foundations through Phase 4 of the frozen build specification.

## Current scope

- Phase 0: TypeScript/React PWA shell, environment validation, formatting, linting, tests, CI, typed Supabase client, and migration workflow.
- Phase 1: companies, warehouses, profiles, memberships, deny-by-default RLS, audit foundation, development fixtures, and automated database security tests.
- Phase 2: company-global brands/products, explicit source-column mapping, audited partial-row imports, row-level issues, and immutable warehouse/stock-take SOH snapshots.
- Phase 3: database-enforced lifecycle transitions, READY validation, one active stock-taker session per user, safe session context, completion locking, and privileged recount-only reopen.
- Phase 4: immutable Bulk/Pick Face counts, canonical packaging calculation, IndexedDB product cache and durable queue, idempotent per-record sync, duplicate warnings/flags, and the mobile stock-taker counting flow.
- Recognition, variance, recount, and reporting workflows are not implemented yet.

## Prerequisites

- Node.js 22.20 or newer
- npm 10.9 or newer
- Docker Desktop

The Supabase CLI is pinned as a development dependency. Use `npm exec supabase` or the supplied npm scripts instead of relying on a machine-wide CLI.

## Local setup

1. Run `npm install`.
2. Copy `.env.example` to `.env.local`. Never place a secret/service-role key in a `VITE_` variable.
3. Run `npm run db:start`.
4. Run `npm run db:reset`.
5. Run `npm run db:test`.
6. Run `npm run db:types` after every schema change.
7. Run `npm run check` and `npm run build`.

The configured remote project URL is `https://woaffibkwqxwncooirzl.supabase.co`. Linking and deploying are separate, deliberate actions; local migrations must pass first.

## Repository map

```text
apps/web/                  React/Vite PWA shell and typed Supabase client
docs/architecture/         Phase plans and architecture decisions
docs/security/             RLS and trust-boundary design
docs/testing/              Acceptance and automated-test matrix
supabase/migrations/       Ordered database migrations
supabase/tests/database/   pgTAP schema, RLS, and immutability tests
supabase/seed.sql          Deterministic local-only fixtures
```

See the phase plans in `docs/architecture/`, including `phase-4-plan.md`, before extending the schema.
