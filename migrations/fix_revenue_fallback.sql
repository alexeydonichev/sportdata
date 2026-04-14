-- Fix: revenue fallback retail_amount -> retail_price_withdisc_rub
-- Date: 2026-04-14
-- Problem: WB API returns retail_amount=0, causing zero revenue in sales/unified_sales

-- 1. Fix sync_wb_to_sales
CREATE OR REPLACE FUNCTION sync_wb_to_sales() RETURNS integer AS $$
DECLARE
    cnt INTEGER := 0;
BEGIN
    INSERT INTO sales (
        credential_id, source_id, sale_date, order_date,
        product_name, brand, barcode, supplier_article,
        category, warehouse, region,
        quantity, revenue, for_pay, ppvz_for_pay,
        commission, logistics, retail_price, discount_percent,
        supplier_oper_name, srid
    )
    SELECT
        credential_id, id, sale_dt::date, order_dt::date,
        subject_name, brand, barcode, supplier_article,
        ts_name, office_name, region_name,
        CASE 
          WHEN quantity != 0 THEN quantity
          WHEN supplier_oper_name ILIKE '%возврат%' THEN -1
          WHEN supplier_oper_name ILIKE '%продажа%' THEN 1
          ELSE 0
        END,
        CASE 
          WHEN retail_amount != 0 THEN retail_amount
          ELSE retail_price_withdisc_rub
        END,
        CASE 
          WHEN ppvz_for_pay != 0 THEN ppvz_for_pay
          ELSE retail_price_withdisc_rub - COALESCE(ppvz_sales_commission, 0) - COALESCE(delivery_rub, 0) - COALESCE(acquiring_fee, 0)
        END,
        ppvz_for_pay,
        ppvz_sales_commission, delivery_rub, retail_price, sale_percent,
        supplier_oper_name, srid
    FROM wb_sales w
    WHERE NOT EXISTS (
        SELECT 1 FROM sales s WHERE s.source_id = w.id
    )
    ON CONFLICT (source_id) DO NOTHING;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;

-- 2. Fix sync_wb_to_unified
CREATE OR REPLACE FUNCTION sync_wb_to_unified() RETURNS integer AS $$
DECLARE
    cnt INTEGER := 0;
BEGIN
    INSERT INTO unified_sales (
        marketplace_id, credential_id, source_table, source_id,
        order_id, product_sku, barcode,
        sale_date, order_date,
        product_name, brand, category,
        quantity, revenue, for_pay, commission, logistics,
        retail_price, discount_percent, return_amount, penalty, storage_fee, acquiring_fee,
        operation_type, operation_name,
        region, warehouse
    )
    SELECT
        1, credential_id, 'wb_sales', id,
        srid, supplier_article, barcode,
        sale_dt::date, order_dt::date,
        subject_name, brand, ts_name,
        CASE 
          WHEN quantity != 0 THEN quantity
          WHEN supplier_oper_name ILIKE '%возврат%' THEN -1
          WHEN supplier_oper_name ILIKE '%продажа%' THEN 1
          ELSE 0
        END,
        CASE 
          WHEN retail_amount != 0 THEN retail_amount
          ELSE retail_price_withdisc_rub
        END,
        CASE 
          WHEN ppvz_for_pay != 0 THEN ppvz_for_pay
          ELSE retail_price_withdisc_rub - COALESCE(ppvz_sales_commission, 0) - COALESCE(delivery_rub, 0) - COALESCE(acquiring_fee, 0)
        END,
        ppvz_sales_commission, delivery_rub,
        retail_price, sale_percent,
        CASE WHEN return_amount > 0 THEN return_amount * retail_price END,
        penalty, storage_fee, acquiring_fee,
        CASE
            WHEN supplier_oper_name ILIKE '%продажа%' THEN 'sale'
            WHEN supplier_oper_name ILIKE '%возврат%' THEN 'return'
            WHEN supplier_oper_name ILIKE '%логистик%' THEN 'logistics'
            WHEN supplier_oper_name ILIKE '%возмещение%' THEN 'compensation'
            WHEN supplier_oper_name ILIKE '%штраф%' THEN 'penalty'
            ELSE 'other'
        END,
        supplier_oper_name, region_name, office_name
    FROM wb_sales w
    WHERE NOT EXISTS (
        SELECT 1 FROM unified_sales u
        WHERE u.source_table = 'wb_sales' AND u.source_id = w.id
    )
    ON CONFLICT (source_table, source_id) DO NOTHING;
    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$ LANGUAGE plpgsql;
