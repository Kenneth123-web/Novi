-- Migration number: 0001 	 2026-09-15T00:00:00.000Z

CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  username TEXT NOT NULL,
  display_name TEXT NOT NULL DEFAULT '',
  is_active INTEGER NOT NULL DEFAULT 1,
  is_admin INTEGER NOT NULL DEFAULT 0,
  source TEXT NOT NULL DEFAULT 'register',
  created_at TEXT NOT NULL,
  last_seen_at TEXT,
  last_login_at TEXT,
  login_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE login_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  event TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT '',
  user_agent TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);

CREATE INDEX idx_login_events_user ON login_events (user_id, created_at DESC);
CREATE INDEX idx_login_events_created ON login_events (created_at DESC);

CREATE TABLE api_usage (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT,
  method TEXT NOT NULL,
  path TEXT NOT NULL,
  status INTEGER NOT NULL,
  latency_ms REAL NOT NULL DEFAULT 0,
  request_id TEXT,
  kind TEXT NOT NULL DEFAULT 'http',
  model TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  created_at TEXT NOT NULL
);

CREATE INDEX idx_usage_user_created ON api_usage (user_id, created_at DESC);
CREATE INDEX idx_usage_created ON api_usage (created_at DESC);
CREATE INDEX idx_usage_path ON api_usage (path);

CREATE TABLE admin_sessions (
  token_hash TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
