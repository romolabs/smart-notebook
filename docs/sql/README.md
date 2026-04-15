# Smart Notebook SQL

This folder holds implementation-ready SQLite artifacts for the local-first note store.

Current scope:
- `0001_initial.sql`: core schema for `notes`, `note_versions`, and `schema_migrations`

The schema follows the planning docs:
- `notes` stores note metadata only
- `note_versions` stores immutable raw and enhanced snapshots
- `schema_migrations` tracks applied migration versions
