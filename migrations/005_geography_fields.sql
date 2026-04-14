-- Миграция 005: Добавление географических полей для аналитики

-- ============================================
-- ГЕОГРАФИЯ В SALES
-- ============================================

ALTER TABLE sales 
ADD COLUMN IF NOT EXISTS country VARCHAR(100),
ADD COLUMN IF NOT EXISTS region VARCHAR(200),
ADD COLUMN IF NOT EXISTS warehouse VARCHAR(200),
ADD COLUMN IF NOT EXISTS warehouse_type VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_sales_country ON sales(country);
CREATE INDEX IF NOT EXISTS idx_sales_warehouse ON sales(warehouse);
CREATE INDEX IF NOT EXISTS idx_sales_region ON sales(region);

-- ============================================
-- РАСШИРЕНИЕ RETURNS
-- ============================================

ALTER TABLE returns
ADD COLUMN IF NOT EXISTS warehouse VARCHAR(200),
ADD COLUMN IF NOT EXISTS return_amount DECIMAL(14,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS logistics_cost DECIMAL(12,2) DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_returns_warehouse ON returns(warehouse);
CREATE INDEX IF NOT EXISTS idx_returns_date ON returns(return_date);

-- ============================================
-- ТАБЛИЦА ПВЗ
-- ============================================

CREATE TABLE IF NOT EXISTS pickup_points (
    id SERIAL PRIMARY KEY,
    marketplace_id INT REFERENCES marketplaces(id),
    external_id VARCHAR(100),
    name VARCHAR(500),
    address VARCHAR(1000),
    region VARCHAR(200),
    city VARCHAR(200),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(marketplace_id, external_id)
);

ALTER TABLE sales
ADD COLUMN IF NOT EXISTS pickup_point_id INT REFERENCES pickup_points(id);

-- ============================================
-- ОБНОВЛЕНИЕ VIEW (DROP + CREATE — нельзя OR REPLACE при смене колонок)
-- ============================================

DROP VIEW IF EXISTS v_daily_sales;

CREATE VIEW v_daily_sales AS
SELECT 
    s.sale_date,
    p.sku,
    p.name AS product_name,
    c.name AS category_name,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    s.country,
    s.region,
    s.warehouse,
    SUM(s.quantity) AS total_qty,
    SUM(s.revenue) AS total_revenue,
    SUM(s.commission) AS total_commission,
    SUM(s.logistics_cost) AS total_logistics,
    SUM(s.net_profit) AS total_profit
FROM sales s
JOIN products p ON p.id = s.product_id
JOIN marketplaces m ON m.id = s.marketplace_id
LEFT JOIN categories c ON c.id = p.category_id
GROUP BY s.sale_date, p.sku, p.name, c.name, m.slug, m.name, s.country, s.region, s.warehouse;

COMMENT ON COLUMN sales.country IS 'Страна доставки (из WB reportDetail)';
COMMENT ON COLUMN sales.region IS 'Регион/область (oblastOkrugName)';
COMMENT ON COLUMN sales.warehouse IS 'Склад отгрузки (officeName)';
