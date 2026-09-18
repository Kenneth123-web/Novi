-- Migration number: 0002 	 2026-09-16T21:00:00.000Z

-- Blind index for exact email lookup after the address itself is sealed.
ALTER TABLE users ADD COLUMN email_hash TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_hash ON users (email_hash);
