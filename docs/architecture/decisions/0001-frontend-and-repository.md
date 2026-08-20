# ADR 0001: React/Vite PWA with migration-first Supabase development

## Status

Accepted for Version 1 foundation.

## Context

The repository was greenfield. The product requires a mobile-first PWA, durable offline behavior, typed database access, and strong database-level isolation. No existing framework constrained the choice.

## Decision

Use React with TypeScript and Vite for the client, npm workspaces for repository organisation, and a locally reproducible Supabase CLI workflow. Pin all package versions and commit the lockfile. Use generated Supabase database types rather than hand-maintained table types.

React/Vite keeps the warehouse UI small and provides direct control over the service worker and IndexedDB lifecycle required in Phase 4. Supabase schema changes are migration-first and verified with pgTAP before remote deployment.

## Consequences

- Phase 4 must explicitly design IndexedDB schema migration, durable acknowledgement, retry, and recovery; PWA installation alone is not offline correctness.
- Business-critical mutations will use reviewed database functions or Edge Functions instead of direct multi-row client writes.
- The client will never contain a service-role or secret key.
