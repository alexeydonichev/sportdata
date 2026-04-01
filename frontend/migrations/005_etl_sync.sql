-- Миграция: синхронизация схемы для Go ETL worker
-- 2025-04-01

-- credential_id в sync_jobs (Go ETL отслеживает по credential)
ALTER TABLE sync_jobs ADD COLUMN IF NOT EXISTS credential_id INT REFERENCES marketplace_credentials(id);

-- last_sync_at для cooldown механизма
ALTER TABLE marketplace_credentials ADD COLUMN IF NOT EXISTS last_sync_at TIMESTAMPTZ;

-- Индекс для быстрого поиска последних jobs по credential
CREATE INDEX IF NOT EXISTS idx_sync_jobs_credential ON sync_jobs(credential_id);
CREATE INDEX IF NOT EXISTS idx_sync_jobs_status ON sync_jobs(status);
