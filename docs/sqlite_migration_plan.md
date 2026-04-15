# SQLite Migration Plan

## Migration Strategy
Use ordered SQL migrations with one-way forward steps and a version table to track applied changes.

## Meta Table
Create a small bookkeeping table:
- `schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)`

## Proposed Initial Sequence

### `0001_initial.sql`
Create the core tables:
- `notes`
- `note_versions`
- `change_items`
- `verification_flags`
- `note_tags`
- `schema_migrations`

Seed only the migration record, not app content.

### `0002_add_search_support.sql`
Add search-friendly support once the base schema is stable:
- FTS or search index for note titles and content
- optional triggers to keep the index in sync

### `0003_add_sync_metadata.sql`
Reserve columns or a companion table for future sync/import support:
- origin source
- external ids
- device/app metadata

## Migration Rules
- Migrations must be idempotent where practical.
- Schema changes should prefer additive columns over destructive rewrites.
- Breaking changes should create a new table and copy data only when unavoidable.
- Application startup should refuse to run if a migration fails partway through.
- Each migration should be small enough to review and rollback by recreating the database from backup.

## Versioning Notes
- Keep the schema version in code and in the database.
- Bump the version for every table, index, or trigger change.
- Treat raw note snapshots as immutable to avoid migration risk on historical content.

