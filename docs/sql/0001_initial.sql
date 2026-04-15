-- Smart Notebook initial SQLite schema.
-- Apply with foreign keys enabled.

PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  note_type TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  archived_at TEXT NULL
);

CREATE INDEX IF NOT EXISTS idx_notes_updated_at
  ON notes(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_notes_note_type_updated_at
  ON notes(note_type, updated_at DESC);

CREATE TABLE IF NOT EXISTS note_versions (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  version_number INTEGER NOT NULL,
  raw_content TEXT NOT NULL,
  enhanced_content TEXT NOT NULL,
  enhancement_mode TEXT NOT NULL,
  pipeline_run_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(note_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_note_versions_note_id_version_number
  ON note_versions(note_id, version_number DESC);

CREATE INDEX IF NOT EXISTS idx_note_versions_pipeline_run_id
  ON note_versions(pipeline_run_id);

CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);

INSERT OR IGNORE INTO schema_migrations (version, applied_at)
VALUES (1, CURRENT_TIMESTAMP);

COMMIT;
