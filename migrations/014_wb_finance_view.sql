-- 014_wb_finance_view.sql
-- Закрепляем view v_wb_income_expenses_daily в Git.
-- Формулы сверены 1-в-1 с отчётом ЛК WB "Финансовый отчёт по реализации".
-- Дата: 2026-04-19

CREATE OR REPLACE VIEW v_wb_income_expenses_daily AS
WITH src AS (
    SELECT
        credential_id,
        sale_dt,
        supplier_oper_name AS oper,
        quantity,
        retail_price_withdisc_rub AS price_w_disc,
        ppvz_for_pay,
        delivery_rub,
        storage_fee,
        acceptance,
        penalty,
        additional_payment,
        deduction
    FROM wb_sales
)
SELECT
    credential_id,
    sale_dt,

    -- Выручка = Продажи - Возвраты - Добровольные компенсации
    ROUND(
        COALESCE(SUM(price_w_disc) FILTER (WHERE oper = 'Продажа'), 0)
      - COALESCE(SUM(price_w_disc) FILTER (WHERE oper = 'Возврат'), 0)
      - COALESCE(SUM(ppvz_for_pay) FILTER (WHERE oper = 'Добровольная компенсация при возврате'), 0),
    2) AS sales_revenue,

    -- Количество штук (продано минус возвращено)
    COALESCE(SUM(quantity) FILTER (WHERE oper = 'Продажа'),  0)
    - COALESCE(SUM(quantity) FILTER (WHERE oper = 'Возврат'), 0) AS sales_qty,

    -- Расходы (уже в wb_sales по всем строкам)
    ROUND(COALESCE(SUM(delivery_rub),        0), 2) AS logistics,
    ROUND(COALESCE(SUM(storage_fee),         0), 2) AS storage,
    ROUND(COALESCE(SUM(acceptance),          0), 2) AS acceptance,
    ROUND(COALESCE(SUM(penalty),             0), 2) AS penalty,
    ROUND(COALESCE(SUM(additional_payment),  0), 2) AS addpay,
    ROUND(COALESCE(SUM(deduction),           0), 2) AS deduction,

    -- Брак (компенсация брака и пр.) — по операциям типа "Добровольная компенсация при возврате"
    ROUND(COALESCE(SUM(ppvz_for_pay) FILTER (WHERE oper = 'Добровольная компенсация при возврате'), 0), 2) AS defects,

    -- Комиссия WB = Продажа_розница - К_перечислению
    ROUND(
        COALESCE(SUM(price_w_disc)  FILTER (WHERE oper = 'Продажа'), 0)
      - COALESCE(SUM(ppvz_for_pay)  FILTER (WHERE oper = 'Продажа'), 0),
    2) AS wb_commission,

    -- К перечислению от WB
    ROUND(
        COALESCE(SUM(ppvz_for_pay) FILTER (WHERE oper = 'Продажа'), 0)
      - COALESCE(SUM(ppvz_for_pay) FILTER (WHERE oper = 'Возврат'), 0),
    2) AS for_pay,

    -- Итого к выплате поставщику (за вычетом всех расходов)
    ROUND(
        COALESCE(SUM(ppvz_for_pay) FILTER (WHERE oper = 'Продажа'), 0)
      - COALESCE(SUM(ppvz_for_pay) FILTER (WHERE oper = 'Возврат'), 0)
      - COALESCE(SUM(ppvz_for_pay) FILTER (WHERE oper = 'Добровольная компенсация при возврате'), 0)
      - COALESCE(SUM(delivery_rub),       0)
      - COALESCE(SUM(storage_fee),        0)
      - COALESCE(SUM(acceptance),         0)
      - COALESCE(SUM(penalty),            0)
      - COALESCE(SUM(deduction),          0)
      + COALESCE(SUM(additional_payment), 0),
    2) AS grand_total

FROM src
GROUP BY credential_id, sale_dt;

ALTER VIEW v_wb_income_expenses_daily OWNER TO sportdata_admin;
GRANT SELECT ON v_wb_income_expenses_daily TO sportdata;

COMMENT ON VIEW v_wb_income_expenses_daily IS
  'WB P&L по дням. Источник: wb_sales. Формулы соответствуют отчёту ЛК WB.';
