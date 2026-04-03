CREATE OR REPLACE VIEW trending_products AS
WITH weekly AS (
    SELECT
        s.product_id,
        p.name,
        p.category_id,
        SUM(CASE WHEN s.sale_date >= CURRENT_DATE - 7 THEN s.quantity ELSE 0 END) AS sales_7d,
        SUM(CASE WHEN s.sale_date >= CURRENT_DATE - 14
                  AND s.sale_date < CURRENT_DATE - 7 THEN s.quantity ELSE 0 END) AS prev_sales_7d
    FROM sales s
    JOIN products p ON p.id = s.product_id
    WHERE s.sale_date >= CURRENT_DATE - 14
    GROUP BY s.product_id, p.name, p.category_id
)
SELECT product_id, name, category_id, sales_7d, prev_sales_7d
FROM weekly;

ALTER TABLE marketplace_credentials
ADD COLUMN IF NOT EXISTS api_key_hint VARCHAR(20)
GENERATED ALWAYS AS (
    CASE WHEN LENGTH(api_key_encrypted) > 8
        THEN '***' || RIGHT(api_key_encrypted, 4)
        ELSE '***'
    END
) STORED;
