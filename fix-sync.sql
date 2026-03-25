-- 1. Add nm_id to products for reliable WB matching
ALTER TABLE products ADD COLUMN IF NOT EXISTS nm_id BIGINT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_nm_id ON products(nm_id) WHERE nm_id IS NOT NULL;

-- 2. Add sale_id to sales for deduplication
ALTER TABLE sales ADD COLUMN IF NOT EXISTS sale_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_unique ON sales(sale_id) WHERE sale_id IS NOT NULL;

-- 3. Remove duplicates: keep only the row with the lowest id for each unique combination
DELETE FROM sales
WHERE id NOT IN (
    SELECT MIN(id)
    FROM sales
    GROUP BY product_id, marketplace_id, sale_date, revenue, for_pay
);

-- 4. Verify
SELECT COUNT(*) as remaining_rows FROM sales;
