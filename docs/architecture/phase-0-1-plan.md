# Phase 0 and Phase 1 implementation plan

Status: approved scope from the Version 1 feature freeze. This document is the implementation gate before feature work.

## Repository plan

The repository uses npm workspaces with one mobile-first React/Vite application. Supabase owns authentication, Postgres, Storage, RLS, and later server-side operations. Pure domain code will be split into packages only when Phase 2 or later creates a real shared boundary; empty abstractions are deliberately avoided.

The frontend receives a generated `Database` type and constructs one typed Supabase client. Environment parsing rejects missing, invalid, non-HTTPS, or secret/service-role browser configuration. The PWA shell is installable, but Phase 4 owns IndexedDB durability and offline queue behavior; the current shell does not claim that valid counts can be captured.

CI runs formatting, lint, TypeScript, unit tests, a production build, a clean Supabase migration replay, pgTAP database tests, and generated-type drift detection.

## Migration sequence

Migration filenames are generated with `supabase migration new`; timestamps are implementation metadata. The ordered logical names are:

1. `phase_1_core_types_and_profiles`
2. `phase_1_tenancy_and_memberships`
3. `phase_1_authorization_helpers_and_rls`
4. `phase_1_audit_foundation`
5. `phase_1_grants_and_hardening`
6. `phase_1_audit_warehouse_fk_index`

Each migration has one responsibility so review and forward fixes remain bounded. Supabase migrations are forward-applied; reversal is documented and exercised in disposable local databases rather than by shipping destructive down migrations.

## Phase 1 schema

- `companies`: tenant root and lifecycle status.
- `warehouses`: tenant warehouse with `(company_id, warehouse_code)` uniqueness.
- `profiles`: minimal identity extension keyed to `auth.users`; platform role is separate from tenant access.
- `company_memberships`: one role/status per user/company.
- `warehouse_memberships`: warehouse allocation constrained to an existing membership in the same company and role.
- `audit_logs`: append-only security and business audit foundation.

Company and warehouse relationships use composite foreign keys where possible. A company role must match the role used for each warehouse allocation. An active Manager allocation is unique per user, implementing the frozen one-warehouse Manager rule. The one-active-stock-taker-session rule belongs to Phase 3 because sessions do not exist in Phase 1.

## Authorisation model

`profiles.platform_role = 'super_admin'` marks eligibility for privileged platform support, but does not grant direct access to every tenant. Direct tenant access still requires an active `company_memberships` row with role `super_admin`; this satisfies the requirement that cross-company support be explicitly authorised.

Admin and Manager warehouse access requires an active matching warehouse membership. Stock Takers can read only their own allocation rows in Phase 1. No application role receives direct insert, update, or delete rights to membership or audit tables; controlled management RPCs will own those mutations when their workflow is implemented.

## Phase boundary

Phase 1 intentionally does not create products, snapshots, stock takes, sessions, counts, recognition events, recounts, notifications, or exports. Their names appear in the full logical model but implementing them here would couple unreviewed Phase 2/3 business rules into the security foundation.

## Exit criteria

- Clean migration replay succeeds on a current local Supabase stack.
- Every Phase 1 public table has RLS forced and enabled.
- Positive and negative company/warehouse/role tests pass.
- Anonymous, cross-company, cross-warehouse, and unallocated access is denied.
- Audit update/delete attempts fail for normal application roles.
- Frontend checks/build pass and generated database types are current.
