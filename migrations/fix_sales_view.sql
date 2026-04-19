-- ============================================================================
-- FIX: view public.sales возвращал неверные revenue/commission для WB
-- Было: revenue=retail_amount (вычтены WB-скидки), commission=ppvz_sales_commission (16k вместо 3M)
-- Стало: revenue=retail_price_withdisc_rub*qty, commission=revenue-ppvz_for_pay
-- ============================================================================

CREATE OR REPLACE VIEW public.sales AS
-- ----------- WB -----------
SELECT
    ws.id,
    COALESCE(p.id, 0) AS product_id,
    1 AS marketplace_id,
    ws.sale_dt AS sale_date,

    -- Количество: реальное только у "Продажа"/"Возврат"
    CASE
      WHEN ws.supplier_oper_name = 'Продажа' THEN COALESCE(ws.quantity, 0)
      WHEN ws.supplier_oper_name = 'Возврат' THEN -COALESCE(ws.quantity, 0)
      ELSE 0
    END AS quantity,

    -- Выручка: цена после скидок × кол-во (что заплатил покупатель)
    CASE
      WHEN ws.supplier_oper_name = 'Продажа'
        THEN COALESCE(ws.retail_price_withdisc_rub, 0) * COALESCE(ws.quantity, 0)
      WHEN ws.supplier_oper_name = 'Возврат'
        THEN -COALESCE(ws.retail_price_withdisc_rub, 0) * COALESCE(ws.quantity, 0)
      ELSE 0
    END AS revenue,

    -- Комиссия WB: разница между тем, что заплатил покупатель и что получил продавец
    CASE
      WHEN ws.supplier_oper_name IN ('Продажа','Возврат')
        THEN (COALESCE(ws.retail_price_withdisc_rub,0) * COALESCE(ws.quantity,0)) - COALESCE(ws.ppvz_for_pay,0)
      ELSE 0
    END AS commission,

    -- Логистика: только для строк логистики и коррекций
    CASE
      WHEN ws.supplier_oper_name IN ('Логистика','Коррекция логистики')
        THEN COALESCE(ws.delivery_rub,0) + COALESCE(ws.rebill_logistic_cost,0)
      ELSE 0
    END AS logistics_cost,

    -- Чистая прибыль (до себестоимости): for_pay минус логистика/штрафы/хранение этой строки
    CASE
      WHEN ws.supplier_oper_name = 'Продажа' THEN COALESCE(ws.ppvz_for_pay,0)
      WHEN ws.supplier_oper_name = 'Возврат' THEN -COALESCE(ws.ppvz_for_pay,0)
      WHEN ws.supplier_oper_name IN ('Логистика','Коррекция логистики')
           THEN -(COALESCE(ws.delivery_rub,0) + COALESCE(ws.rebill_logistic_cost,0))
      WHEN ws.supplier_oper_name = 'Хранение'          THEN -COALESCE(ws.storage_fee,0)
      WHEN ws.supplier_oper_name = 'Обработка товара'  THEN -COALESCE(ws.acceptance,0)
      WHEN ws.supplier_oper_name = 'Штраф'             THEN -COALESCE(ws.penalty,0)
      WHEN ws.supplier_oper_name = 'Удержание'         THEN -COALESCE(ws.deduction,0)
      ELSE 0
    END AS net_profit,

    ws.created_at,
    ws.country_name AS country,
    ws.region_name AS region,
    ws.office_name AS warehouse,
    NULL::character varying(100) AS warehouse_type,
    NULL::integer AS pickup_point_id,

    COALESCE(ws.ppvz_for_pay,0) AS for_pay,
    CASE WHEN ws.supplier_oper_name = 'Штраф'     THEN COALESCE(ws.penalty,0)    ELSE 0 END AS penalty,
    ws.retail_price,
    ws.retail_amount,
    ws.retail_price_withdisc_rub AS discount_price,
    ws.retail_price_withdisc_rub AS finished_price,
    ws.nm_id,
    ws.brand,
    ws.subject_name,
    ws.supplier_article,
    ws.barcode,
    ws.doc_type_name,
    ws.supplier_oper_name,
    ws.order_dt::text AS order_dt,
    ws.srid,
    ws.srid AS sale_id,
    ws.rrd_id,
    ws.gi_id,
    ws.sticker_id,
    ws.office_name AS office_name_2,
    ws.ppvz_for_pay,
    ws.ppvz_sales_commission,
    ws.ppvz_reward,
    COALESCE(ws.acquiring_fee,0) AS acquiring_fee,
    ws.acquiring_percent,
    ws.ppvz_vw,
    ws.ppvz_vw_nds,
    COALESCE(ws.delivery_rub,0) AS delivery_rub,
    COALESCE(ws.return_amount,0) AS return_amount,
    COALESCE(ws.delivery_amount,0) AS delivery_amount,
    CASE WHEN ws.supplier_oper_name = 'Обработка товара' THEN COALESCE(ws.acceptance,0) ELSE 0 END AS acceptance,
    ws.kiz,
    CASE WHEN ws.supplier_oper_name = 'Хранение'  THEN COALESCE(ws.storage_fee,0) ELSE 0 END AS storage_fee,
    CASE WHEN ws.supplier_oper_name = 'Удержание' THEN COALESCE(ws.deduction,0)   ELSE 0 END AS deduction,
    COALESCE(ws.rebill_logistic_cost,0) AS rebill_logistic_cost,
    ws.credential_id
FROM wb_sales ws
LEFT JOIN products p ON p.nm_id = ws.nm_id

UNION ALL

-- ----------- OZON -----------
SELECT
    os.id,
    COALESCE(p.id, 0) AS product_id,
    2 AS marketplace_id,
    os.operation_date::date AS sale_date,
    COALESCE(os.sale_qty, 0) AS quantity,
    COALESCE(os.accruals_for_sale, os.sale_price, 0::numeric) AS revenue,
    COALESCE(os.sale_commission, 0::numeric) AS commission,
    COALESCE(os.delivery_commission, 0::numeric) AS logistics_cost,
    COALESCE(os.accruals_for_sale,0::numeric) - COALESCE(os.sale_commission,0::numeric) - COALESCE(os.delivery_commission,0::numeric) AS net_profit,
    os.created_at,
    NULL::character varying(100) AS country,
    os.region,
    os.warehouse_name AS warehouse,
    NULL::character varying(100) AS warehouse_type,
    NULL::integer AS pickup_point_id,
    COALESCE(os.accruals_for_sale, 0::numeric) AS for_pay,
    COALESCE(os.return_commission, 0::numeric) AS penalty,
    os.sale_price AS retail_price,
    os.sale_price AS retail_amount,
    os.sale_price AS discount_price,
    os.sale_price AS finished_price,
    os.sku AS nm_id,
    NULL::character varying(200) AS brand,
    NULL::character varying(200) AS subject_name,
    os.offer_id AS supplier_article,
    os.barcode,
    NULL::character varying(50) AS doc_type_name,
    os.operation_type AS supplier_oper_name,
    os.order_date::text AS order_dt,
    os.posting_number AS srid,
    os.posting_number AS sale_id,
    os.operation_id AS rrd_id,
    NULL::bigint AS gi_id,
    NULL::character varying(50) AS sticker_id,
    os.warehouse_name AS office_name_2,
    COALESCE(os.accruals_for_sale, 0::numeric) AS ppvz_for_pay,
    COALESCE(os.sale_commission, 0::numeric) AS ppvz_sales_commission,
    NULL::numeric AS ppvz_reward,
    0::numeric AS acquiring_fee,
    NULL::numeric AS acquiring_percent,
    NULL::numeric AS ppvz_vw,
    NULL::numeric AS ppvz_vw_nds,
    COALESCE(os.delivery_commission, 0::numeric) AS delivery_rub,
    0 AS return_amount,
    0 AS delivery_amount,
    0::numeric AS acceptance,
    NULL::character varying AS kiz,
    0::numeric AS storage_fee,
    0::numeric AS deduction,
    0::numeric AS rebill_logistic_cost,
    os.credential_id
FROM ozon_sales os
LEFT JOIN products p ON p.sku::text = os.offer_id::text;
