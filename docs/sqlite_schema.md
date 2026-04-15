# SQLite Schema Plan

## Goal
Store Smart Notebook data locally with SQLite as the source of truth while preserving raw notes, enhanced versions, and review metadata.

## Core Tables

### `notes`
Root record for one note.
- `id` TEXT PRIMARY KEY
- `title` TEXT NOT NULL
- `note_type` TEXT NOT NULL
- `created_at` TEXT NOT NULL
- `updated_at` TEXT NOT NULL
- `archived_at` TEXT NULL

Recommended indexes:
- `(updated_at DESC)`
- `(note_type, updated_at DESC)`

### `note_versions`
Immutable snapshots of raw and enhanced content.
- `id` TEXT PRIMARY KEY
- `note_id` TEXT NOT NULL REFERENCES `notes(id)` ON DELETE CASCADE
- `version_number` INTEGER NOT NULL
- `raw_content` TEXT NOT NULL
- `enhanced_content` TEXT NOT NULL
- `enhancement_mode` TEXT NOT NULL
- `pipeline_run_id` TEXT NOT NULL
- `created_at` TEXT NOT NULL

Recommended constraints:
- `UNIQUE(note_id, version_number)`

Recommended indexes:
- `(note_id, version_number DESC)`
- `(pipeline_run_id)`

### `change_items`
Atomic edits and annotations attached to one version.
- `id` TEXT PRIMARY KEY
- `version_id` TEXT NOT NULL REFERENCES `note_versions(id)` ON DELETE CASCADE
- `kind` TEXT NOT NULL
- `raw_text` TEXT NOT NULL
- `enhanced_text` TEXT NOT NULL
- `confidence` REAL NOT NULL
- `explanation` TEXT NULL
- `source_start` INTEGER NULL
- `source_end` INTEGER NULL
- `target_start` INTEGER NULL
- `target_end` INTEGER NULL

Recommended indexes:
- `(version_id, kind)`

### `verification_flags`
Advisory fact-check output attached to one version.
- `id` TEXT PRIMARY KEY
- `version_id` TEXT NOT NULL REFERENCES `note_versions(id)` ON DELETE CASCADE
- `claim_text` TEXT NOT NULL
- `status` TEXT NOT NULL
- `confidence` REAL NOT NULL
- `reason` TEXT NULL
- `suggested_correction` TEXT NULL
- `span_start` INTEGER NULL
- `span_end` INTEGER NULL

Recommended indexes:
- `(version_id, status)`

## Supporting Tables

### `note_tags`
Normalized tags for note search and filters.
- `note_id` TEXT NOT NULL REFERENCES `notes(id)` ON DELETE CASCADE
- `tag` TEXT NOT NULL
- `PRIMARY KEY(note_id, tag)`

Recommended indexes:
- `(tag)`

## Storage Rules
- Keep `note_versions`, `change_items`, and `verification_flags` append-only.
- Preserve `raw_content` exactly as captured.
- Never update an old version in place once persisted.
- Use UTC ISO-8601 text timestamps for predictable cross-platform handling.
- Store enum-like values as text so the schema stays readable and migration-friendly.

