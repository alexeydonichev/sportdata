-- Audit log table
CREATE TABLE IF NOT EXISTS audit_log (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT,
  user_email TEXT NOT NULL DEFAULT 'anonymous',
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_user ON audit_log (user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log (action);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log (created_at DESC);

-- API key hint column (first 8 chars for masking without decryption)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'marketplace_credentials' AND column_name = 'api_key_hint'
  ) THEN
    ALTER TABLE marketplace_credentials ADD COLUMN api_key_hint TEXT;
  END IF;
END $$;
