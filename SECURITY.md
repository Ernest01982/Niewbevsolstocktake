# Security policy

## Non-negotiable controls

- Never commit access tokens, database passwords, service-role keys, secret keys, or production exports.
- Browser code may use only the project URL and a publishable key. RLS remains mandatory.
- Never use `raw_user_meta_data` or user-editable JWT claims for authorisation.
- Every table in an exposed schema must have RLS enabled before any API grant is added.
- Tenant access is derived from active company and warehouse memberships, not from client-supplied identifiers.
- Security-definer functions live in the non-exposed `private` schema, set an empty search path, and are not executable by `PUBLIC`.
- Audit records are append-only; application roles cannot update or delete them.
- Remote migrations are never applied before local reset, pgTAP tests, lint, typecheck, and review succeed.

## Reporting a problem

Do not place secrets or customer data in an issue. Record the affected control, minimal reproduction, expected isolation boundary, and whether the issue is exploitable across a company or warehouse.
