-- ETL sync extensions
-- credential_id в sync_jobs (Go ETL отслеживает по credential)
ALTER TABLE sync_jobs ADD COLUMN IF NOT EXISTS credential_id INT REFERENCES marketplace_credentials(id);

-- last_sync_at для cooldown механизма
ALTER TABLE marketplace_credentials ADD COLUMN IF NOT EXISTS last_sync_at TIMESTAMPTZ;

-- user_email в audit_log (для логирования без JOIN)
ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS user_email VARCHAR(255);

-- staging таблица для ETL upsert
CREATE TABLE IF NOT EXISTS staging_sales_update (
    id BIGSERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id),
    marketplace_id INT REFERENCES marketplaces(id),
    sale_date DATE,
    quantity INT,
    revenue NUMERIC(14,2),
    commission NUMERIC(14,2),
    logistics_cost NUMERIC(14,2),
    net_profit NUMERIC(14,2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_sync_jobs_credential ON sync_jobs(credential_id);
CREATE INDEX IF NOT EXISTS idx_sync_jobs_status ON sync_jobs(status);
