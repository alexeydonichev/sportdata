INSERT INTO sales (
  product_id,
  marketplace_id,
  sale_date,
  quantity,
  revenue,
  for_pay,
  net_profit,
  commission,
  logistics_cost,
  sale_id
)
SELECT
  product_id,
  marketplace_id,
  sale_date,
  quantity,
  revenue,
  for_pay,
  net_profit,
  commission,
  logistics_cost,
  sale_id
FROM sales_stage
ON CONFLICT (sale_id, sale_date)
DO UPDATE SET
  quantity = EXCLUDED.quantity,
  revenue = EXCLUDED.revenue,
  for_pay = EXCLUDED.for_pay,
  net_profit = EXCLUDED.net_profit,
  commission = EXCLUDED.commission,
  logistics_cost = EXCLUDED.logistics_cost
WHERE
  sales.revenue IS DISTINCT FROM EXCLUDED.revenue
  OR sales.quantity IS DISTINCT FROM EXCLUDED.quantity;

TRUNCATE sales_stage RESTART IDENTITY;

ANALYZE sales;
