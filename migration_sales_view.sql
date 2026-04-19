BEGIN;

DROP TABLE IF EXISTS sales CASCADE;
DROP TABLE IF EXISTS unified_sales CASCADE;
DROP TABLE IF EXISTS stocks CASCADE;
DROP TABLE IF EXISTS staging_sales_update CASCADE;
DROP TABLE IF EXISTS sales_stage CASCADE;

CREATE OR REPLACE VIEW sales AS
SELECT
  ws.id,
  COALESCE(p.id, 0)::int                       AS product_id,
  1::int                                        AS marketplace_id,
  ws.sale_dt                                    AS sale_date,
  COALESCE(ws.quantity, 0)                      AS quantity,
  COALESCE(ws.retail_amount, 0)                 AS revenue,
  COALESCE(ws.ppvz_sales_commission, 0)         AS commission,
  COALESCE(ws.delivery_rub, 0)                  AS logistics_cost,
  COALESCE(ws.ppvz_for_pay, 0)                  AS net_profit,
  ws.created_at::timestamptz                    AS created_at,
  ws.country_name                               AS country,
  ws.region_name                                AS region,
  ws.office_name                                AS warehouse,
  NULL::varchar(100)                            AS warehouse_type,
  NULL::int                                     AS pickup_point_id,
  ws.ppvz_for_pay                               AS for_pay,
  COALESCE(ws.penalty, 0)                       AS penalty,
  ws.retail_price,
  ws.retail_amount,
  ws.retail_price_withdisc_rub                  AS discount_price,
  ws.retail_price_withdisc_rub                  AS finished_price,
  ws.nm_id,
  ws.brand,
  ws.subject_name,
  ws.supplier_article,
  ws.barcode,
  ws.doc_type_name,
  ws.supplier_oper_name,
  ws.order_dt::text                             AS order_dt,
  ws.srid,
  ws.srid                                       AS sale_id,
  ws.rrd_id,
  ws.gi_id,
  ws.sticker_id,
  ws.office_name                                AS office_name_2,
  ws.ppvz_for_pay                               AS ppvz_for_pay,
  ws.ppvz_sales_commission                      AS ppvz_sales_commission,
  ws.ppvz_reward,
  COALESCE(ws.acquiring_fee, 0)                 AS acquiring_fee,
  ws.acquiring_percent,
  ws.ppvz_vw,
  ws.ppvz_vw_nds,
  COALESCE(ws.delivery_rub, 0)                  AS delivery_rub,
  COALESCE(ws.return_amount, 0)                 AS return_amount,
  COALESCE(ws.delivery_amount, 0)               AS delivery_amount,
  COALESCE(ws.acceptance, 0)                    AS acceptance,
  ws.kiz,
  COALESCE(ws.storage_fee, 0)                   AS storage_fee,
  COALESCE(ws.deduction, 0)                     AS deduction,
  COALESCE(ws.rebill_logistic_cost, 0)          AS rebill_logistic_cost,
  ws.credential_id
FROM wb_sales ws
LEFT JOIN products p ON p.nm_id = ws.nm_id

UNION ALL

SELECT
  os.id,
  COALESCE(p.id, 0)::int                                    AS product_id,
  2::int                                                     AS marketplace_id,
  os.operation_date::date                                    AS sale_date,
  COALESCE(os.sale_qty, 0)                                   AS quantity,
  COALESCE(os.accruals_for_sale, os.sale_price, 0)           AS revenue,
  COALESCE(os.sale_commission, 0)                            AS commission,
  COALESCE(os.delivery_commission, 0)                        AS logistics_cost,
  COALESCE(os.accruals_for_sale, 0) 
    - COALESCE(os.sale_commission, 0) 
    - COALESCE(os.delivery_commission, 0)                    AS net_profit,
  os.created_at                                              AS created_at,
  NULL::varchar(100)                                         AS country,
  os.region                                                  AS region,
  os.warehouse_name                                          AS warehouse,
  NULL::varchar(100)                                         AS warehouse_type,
  NULL::int                                                  AS pickup_point_id,
  COALESCE(os.accruals_for_sale, 0)                          AS for_pay,
  COALESCE(os.return_commission, 0)                          AS penalty,
  os.sale_price                                              AS retail_price,
  os.sale_price                                              AS retail_amount,
  os.sale_price                                              AS discount_price,
  os.sale_price                                              AS finished_price,
  os.sku                                                     AS nm_id,
  NULL::varchar(200)                                         AS brand,
  NULL::varchar(200)                                         AS subject_name,
  os.offer_id                                                AS supplier_article,
  os.barcode,
  NULL::varchar(50)                                          AS doc_type_name,
  os.operation_type                                          AS supplier_oper_name,
  os.order_date::text                                        AS order_dt,
  os.posting_number                                          AS srid,
  os.posting_number                                          AS sale_id,
  os.operation_id                                            AS rrd_id,
  NULL::bigint                                               AS gi_id,
  NULL::varchar(50)                                          AS sticker_id,
  os.warehouse_name                                          AS office_name_2,
  COALESCE(os.accruals_for_sale, 0)                          AS ppvz_for_pay,
  COALESCE(os.sale_commission, 0)                            AS ppvz_sales_commission,
  NULL::numeric                                              AS ppvz_reward,
  0::numeric                                                 AS acquiring_fee,
  NULL::numeric                                              AS acquiring_percent,
  NULL::numeric                                              AS ppvz_vw,
  NULL::numeric                                              AS ppvz_vw_nds,
  COALESCE(os.delivery_commission, 0)                        AS delivery_rub,
  0::int                                                     AS return_amount,
  0::int                                                     AS delivery_amount,
  0::numeric                                                 AS acceptance,
  NULL::varchar                                              AS kiz,
  0::numeric                                                 AS storage_fee,
  0::numeric                                                 AS deduction,
  0::numeric                                                 AS rebill_logistic_cost,
  os.credential_id
FROM ozon_sales os
LEFT JOIN products p ON p.sku = os.offer_id;

CREATE OR REPLACE VIEW unified_sales AS SELECT * FROM sales;

COMMIT;
