-- ============================================================
-- 015_canonical_pnl.sql
-- Единый источник правды для P&L по WB
-- - Убирает расхождения между v_wb_income_expenses_daily и sales view (~95k ₽)
-- - Подтягивает rebill_logistic_cost из всех строк (+118k ₽ логистики)
-- - Учитывает ppvz_reward (бонусы за выдачу, +2.8k ₽)
-- - Удаляет мёртвые функции sync_wb_to_sales, sync_wb_to_unified
-- ============================================================

BEGIN;

-- Удалить мёртвые функции (делают INSERT в view = невозможно)
DROP FUNCTION IF EXISTS sync_wb_to_sales() CASCADE;
DROP FUNCTION IF EXISTS sync_wb_to_unified() CASCADE;

-- ------------------------------------------------------------
-- v_pnl_daily: детализация по SKU × день
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_pnl_daily AS
SELECT
  ws.credential_id,
  ws.sale_dt AS date,
  1 AS marketplace_id,
  ws.nm_id,
  p.id AS product_id,
  p.category_id,
  COALESCE(p.cost_price, 0) AS cost_price,

  SUM(CASE 
    WHEN ws.supplier_oper_name = 'Продажа' THEN COALESCE(ws.quantity, 1)
    WHEN ws.supplier_oper_name = 'Возврат' THEN -COALESCE(ws.quantity, 1)
    ELSE 0 
  END) AS units,

  SUM(CASE 
    WHEN ws.supplier_oper_name = 'Продажа' 
      THEN COALESCE(ws.retail_price_withdisc_rub, 0) * COALESCE(ws.quantity, 1)
    ELSE 0 
  END) AS gross_revenue,

  SUM(CASE 
    WHEN ws.supplier_oper_name = 'Возврат' 
      THEN COALESCE(ws.retail_price_withdisc_rub, 0) * COALESCE(ws.quantity, 1)
    ELSE 0 
  END) AS returns_amount,

  SUM(CASE 
    WHEN ws.supplier_oper_name = 'Продажа' THEN COALESCE(ws.ppvz_for_pay, 0)
    WHEN ws.supplier_oper_name = 'Возврат' THEN -COALESCE(ws.ppvz_for_pay, 0)
    WHEN ws.supplier_oper_name = 'Добровольная компенсация при возврате' 
      THEN -COALESCE(ws.ppvz_for_pay, 0)
    ELSE 0 
  END) AS for_pay,

  SUM(CASE 
    WHEN ws.supplier_oper_name = 'Продажа' THEN 
      COALESCE(ws.retail_price_withdisc_rub, 0) * COALESCE(ws.quantity, 1) 
      - COALESCE(ws.ppvz_for_pay, 0)
    ELSE 0 
  END) AS commission,

  SUM(COALESCE(ws.acquiring_fee, 0)) AS acquiring,

  -- Логистика из ВСЕХ строк: delivery_rub + rebill_logistic_cost
  SUM(
    COALESCE(ws.delivery_rub, 0) + COALESCE(ws.rebill_logistic_cost, 0)
  ) AS logistics,

  SUM(COALESCE(ws.storage_fee, 0)) AS storage,
  SUM(COALESCE(ws.acceptance, 0)) AS acceptance,
  SUM(COALESCE(ws.penalty, 0)) AS penalty,
  SUM(COALESCE(ws.deduction, 0)) AS deduction,
  SUM(COALESCE(ws.additional_payment, 0)) AS additional_payment,
  SUM(COALESCE(ws.ppvz_reward, 0)) AS reward_income,

  SUM(CASE 
    WHEN ws.supplier_oper_name = 'Продажа' 
      THEN COALESCE(ws.quantity, 1) * COALESCE(p.cost_price, 0)
    WHEN ws.supplier_oper_name = 'Возврат' 
      THEN -COALESCE(ws.quantity, 1) * COALESCE(p.cost_price, 0)
    ELSE 0 
  END) AS cogs

FROM wb_sales ws
LEFT JOIN products p ON p.nm_id = ws.nm_id
GROUP BY ws.credential_id, ws.sale_dt, ws.nm_id, p.id, p.category_id, p.cost_price;


-- ------------------------------------------------------------
-- v_pnl_summary: дневные агрегаты для дашбордов
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_pnl_summary AS
SELECT
  credential_id,
  date,
  SUM(units) AS units,
  SUM(gross_revenue) AS gross_revenue,
  SUM(returns_amount) AS returns_amount,
  SUM(gross_revenue) - SUM(returns_amount) AS net_revenue,
  SUM(for_pay) AS for_pay,
  SUM(commission) AS commission,
  SUM(acquiring) AS acquiring,
  SUM(logistics) AS logistics,
  SUM(storage) AS storage,
  SUM(acceptance) AS acceptance,
  SUM(penalty) AS penalty,
  SUM(deduction) AS deduction,
  SUM(additional_payment) AS additional_payment,
  SUM(reward_income) AS reward_income,
  SUM(cogs) AS cogs,
  SUM(for_pay) 
    - SUM(logistics) 
    - SUM(storage) 
    - SUM(acceptance)
    - SUM(penalty) 
    - SUM(deduction)
    + SUM(additional_payment)
    + SUM(reward_income)
    - SUM(cogs)
  AS net_profit
FROM v_pnl_daily
GROUP BY credential_id, date;


-- Индекс для скорости
CREATE INDEX IF NOT EXISTS idx_wb_sales_sale_dt_nm 
  ON wb_sales(sale_dt, nm_id);

-- Запись о миграции
INSERT INTO schema_migrations(filename) 
VALUES ('015_canonical_pnl.sql')
ON CONFLICT DO NOTHING;

COMMIT;

-- ============================================================
-- Проверки после миграции
-- ============================================================
\echo ''
\echo '=== СРАВНЕНИЕ: старые views vs новый v_pnl_summary ==='
SELECT 
  'v_wb_income_expenses_daily (OLD)' AS source,
  SUM(sales_revenue)::numeric(14,2) AS revenue,
  SUM(for_pay)::numeric(14,2) AS for_pay,
  SUM(grand_total)::numeric(14,2) AS net
FROM v_wb_income_expenses_daily
UNION ALL
SELECT 
  'sales view (OLD)',
  SUM(revenue)::numeric(14,2),
  SUM(for_pay)::numeric(14,2),
  SUM(net_profit)::numeric(14,2)
FROM sales WHERE marketplace_id = 1
UNION ALL
SELECT 
  'v_pnl_summary (NEW, без COGS в net)',
  SUM(net_revenue)::numeric(14,2),
  SUM(for_pay)::numeric(14,2),
  (SUM(net_profit) + SUM(cogs))::numeric(14,2)
FROM v_pnl_summary
UNION ALL
SELECT 
  'v_pnl_summary (NEW, с COGS)',
  SUM(net_revenue)::numeric(14,2),
  SUM(for_pay)::numeric(14,2),
  SUM(net_profit)::numeric(14,2)
FROM v_pnl_summary;
