-- Удаляем дубликат
DROP INDEX IF EXISTS sales_sale_id_mp_date_idx;

-- Покрывающий индекс для основных аналитических запросов
-- (sale_date, marketplace_id, product_id) INCLUDE (revenue, net_profit, quantity, commission, logistics_cost)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sales_analytics_cover
ON sales (sale_date, marketplace_id)
INCLUDE (product_id, revenue, net_profit, quantity, commission, logistics_cost);

-- Partial index для quantity > 0 (отсекает ~30% строк)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sales_positive_qty
ON sales (sale_date, product_id)
WHERE quantity > 0;

-- Refresh stats
ANALYZE sales;
