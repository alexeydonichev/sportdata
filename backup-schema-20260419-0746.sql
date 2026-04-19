--
-- PostgreSQL database dump
--

\restrict ClneSdFzUHTggcFMnSt0CKdifPGRoO9bIMJ8O9H7JBFuDcMvTft8FYYK8z3TMxl

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: rnp_status; Type: TYPE; Schema: public; Owner: sportdata_admin
--

CREATE TYPE public.rnp_status AS ENUM (
    'liquidation',
    'action',
    'monitoring',
    'completed'
);


ALTER TYPE public.rnp_status OWNER TO sportdata_admin;

--
-- Name: sync_wb_to_sales(); Type: FUNCTION; Schema: public; Owner: sportdata_admin
--

CREATE FUNCTION public.sync_wb_to_sales() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  affected integer;
BEGIN
  WITH src AS (
    SELECT
      p.id AS product_id,
      1 AS marketplace_id,
      w.sale_dt::date AS sale_date,
      -- quantity: если 0, вычисляем из типа операции
      CASE 
        WHEN w.quantity != 0 THEN w.quantity
        WHEN w.supplier_oper_name ILIKE '%возврат%' THEN -1
        WHEN w.supplier_oper_name ILIKE '%продажа%' THEN 1
        ELSE 0
      END AS quantity,
      -- revenue: fallback retail_price_withdisc_rub -> retail_amount
      CASE 
        WHEN w.retail_amount != 0 THEN w.retail_amount
        ELSE w.retail_price_withdisc_rub
      END AS revenue,
      w.ppvz_sales_commission AS commission,
      w.delivery_rub AS logistics_cost,
      -- net_profit: пересчёт с fallback
      CASE 
        WHEN w.ppvz_for_pay != 0 THEN w.ppvz_for_pay - w.delivery_rub - w.penalty - w.storage_fee - w.deduction
        ELSE w.retail_price_withdisc_rub - w.ppvz_sales_commission - w.delivery_rub - w.acquiring_fee - w.penalty - w.storage_fee - w.deduction
      END AS net_profit,
      w.country_name AS country,
      w.region_name AS region,
      w.office_name AS warehouse,
      -- for_pay: fallback
      CASE 
        WHEN w.ppvz_for_pay != 0 THEN w.ppvz_for_pay
        ELSE w.retail_price_withdisc_rub - w.ppvz_sales_commission - w.delivery_rub - w.acquiring_fee
      END AS for_pay,
      w.penalty,
      w.retail_price,
      -- retail_amount в sales: fallback
      CASE 
        WHEN w.retail_amount != 0 THEN w.retail_amount
        ELSE w.retail_price_withdisc_rub
      END AS retail_amount,
      w.retail_price_withdisc_rub AS discount_price,
      w.nm_id,
      w.brand,
      w.subject_name,
      w.supplier_article,
      w.barcode,
      w.doc_type_name,
      w.supplier_oper_name,
      w.order_dt::date AS order_dt,
      w.srid,
      w.rrd_id,
      w.gi_id,
      COALESCE(w.sticker_id, '0') AS sticker_id,
      -- ppvz_for_pay в sales: fallback
      CASE 
        WHEN w.ppvz_for_pay != 0 THEN w.ppvz_for_pay
        ELSE w.retail_price_withdisc_rub - w.ppvz_sales_commission - w.delivery_rub - w.acquiring_fee
      END AS ppvz_for_pay2,
      w.ppvz_sales_commission AS ppvz_sales_commission2,
      w.ppvz_reward,
      w.acquiring_fee,
      w.acquiring_percent,
      w.ppvz_vw,
      w.ppvz_vw_nds,
      w.delivery_rub AS delivery_rub2,
      w.return_amount,
      w.delivery_amount,
      w.acceptance,
      w.kiz,
      w.storage_fee,
      w.deduction,
      w.rebill_logistic_cost,
      w.credential_id
    FROM wb_sales w
    JOIN products p ON p.nm_id = w.nm_id
    WHERE w.sale_dt IS NOT NULL
      AND w.srid IS NOT NULL
  )
  INSERT INTO sales (
    product_id, marketplace_id, sale_date, quantity,
    revenue, commission, logistics_cost, net_profit,
    country, region, warehouse,
    for_pay, penalty, retail_price, retail_amount,
    discount_price, nm_id, brand, subject_name,
    supplier_article, barcode, doc_type_name, supplier_oper_name,
    order_dt, srid, rrd_id, gi_id, sticker_id,
    office_name, ppvz_for_pay, ppvz_sales_commission,
    ppvz_reward, acquiring_fee, acquiring_percent,
    ppvz_vw, ppvz_vw_nds, delivery_rub,
    return_amount, delivery_amount, acceptance,
    kiz, storage_fee, deduction, rebill_logistic_cost,
    credential_id, created_at
  )
  SELECT
    product_id, marketplace_id, sale_date, quantity,
    revenue, commission, logistics_cost, net_profit,
    country, region, warehouse,
    for_pay, penalty, retail_price, retail_amount,
    discount_price, nm_id, brand, subject_name,
    supplier_article, barcode, doc_type_name, supplier_oper_name,
    order_dt, srid, rrd_id, gi_id, sticker_id,
    warehouse, ppvz_for_pay2, ppvz_sales_commission2,
    ppvz_reward, acquiring_fee, acquiring_percent,
    ppvz_vw, ppvz_vw_nds, delivery_rub2,
    return_amount, delivery_amount, acceptance,
    kiz, storage_fee, deduction, rebill_logistic_cost,
    credential_id, NOW()
  FROM src
  ON CONFLICT (rrd_id) WHERE rrd_id IS NOT NULL
  DO UPDATE SET
    quantity = EXCLUDED.quantity,
    revenue = EXCLUDED.revenue,
    for_pay = EXCLUDED.for_pay,
    commission = EXCLUDED.commission,
    logistics_cost = EXCLUDED.logistics_cost,
    net_profit = EXCLUDED.net_profit,
    penalty = EXCLUDED.penalty,
    delivery_rub = EXCLUDED.delivery_rub,
    storage_fee = EXCLUDED.storage_fee,
    retail_amount = EXCLUDED.retail_amount,
    discount_price = EXCLUDED.discount_price,
    ppvz_for_pay = EXCLUDED.ppvz_for_pay;

  GET DIAGNOSTICS affected = ROW_COUNT;
  RAISE NOTICE 'sync_wb_to_sales: % rows upserted', affected;
  RETURN affected;
END;
$$;


ALTER FUNCTION public.sync_wb_to_sales() OWNER TO sportdata_admin;

--
-- Name: sync_wb_to_unified(); Type: FUNCTION; Schema: public; Owner: sportdata_admin
--

CREATE FUNCTION public.sync_wb_to_unified() RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
        1,
        credential_id,
        'wb_sales',
        id,
        srid,
        supplier_article,
        barcode,
        sale_dt::date,
        order_dt::date,
        subject_name,
        brand,
        ts_name,
        -- quantity fallback
        CASE 
          WHEN quantity != 0 THEN quantity
          WHEN supplier_oper_name ILIKE '%возврат%' THEN -1
          WHEN supplier_oper_name ILIKE '%продажа%' THEN 1
          ELSE 0
        END,
        -- revenue fallback
        CASE 
          WHEN retail_amount != 0 THEN retail_amount
          ELSE retail_price_withdisc_rub
        END,
        -- for_pay fallback
        CASE 
          WHEN ppvz_for_pay != 0 THEN ppvz_for_pay
          ELSE retail_price_withdisc_rub - ppvz_sales_commission - delivery_rub - acquiring_fee
        END,
        ppvz_sales_commission,
        delivery_rub,
        retail_price,
        sale_percent,
        CASE WHEN return_amount > 0 THEN return_amount * retail_price END,
        penalty,
        storage_fee,
        acquiring_fee,
        CASE
            WHEN supplier_oper_name ILIKE '%продажа%' THEN 'sale'
            WHEN supplier_oper_name ILIKE '%возврат%' THEN 'return'
            WHEN supplier_oper_name ILIKE '%логистик%' THEN 'logistics'
            WHEN supplier_oper_name ILIKE '%возмещение%' THEN 'compensation'
            WHEN supplier_oper_name ILIKE '%штраф%' THEN 'penalty'
            ELSE 'other'
        END,
        supplier_oper_name,
        region_name,
        office_name
    FROM wb_sales w
    WHERE NOT EXISTS (
        SELECT 1 FROM unified_sales u
        WHERE u.source_table = 'wb_sales' AND u.source_id = w.id
    )
    ON CONFLICT (source_table, source_id) DO NOTHING;

    GET DIAGNOSTICS cnt = ROW_COUNT;
    RETURN cnt;
END;
$$;


ALTER FUNCTION public.sync_wb_to_unified() OWNER TO sportdata_admin;

--
-- Name: update_rnp_attention(); Type: FUNCTION; Schema: public; Owner: sportdata_admin
--

CREATE FUNCTION public.update_rnp_attention() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.needs_attention := (
        NEW.reviews_ok = FALSE OR
        COALESCE(NEW.days_of_stock_7d, 999) < 7 OR
        (NEW.plan_orders_qty > 0 AND 
         COALESCE(NEW.fact_orders_qty, 0)::DECIMAL / NEW.plan_orders_qty < 0.3 AND
         CURRENT_DATE - COALESCE(NEW.period_start, CURRENT_DATE) > 10)
    );
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_rnp_attention() OWNER TO sportdata_admin;

--
-- Name: update_rnp_reviews_ok(); Type: FUNCTION; Schema: public; Owner: sportdata_admin
--

CREATE FUNCTION public.update_rnp_reviews_ok() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.reviews_ok := (
        COALESCE(NEW.review_1_stars, 5) >= 4 AND 
        COALESCE(NEW.review_2_stars, 5) >= 4 AND 
        COALESCE(NEW.review_3_stars, 5) >= 4
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_rnp_reviews_ok() OWNER TO sportdata_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    user_id uuid,
    action character varying(100) NOT NULL,
    entity_type character varying(50),
    entity_id character varying(100),
    details jsonb,
    ip_address inet,
    created_at timestamp with time zone DEFAULT now(),
    user_email character varying(255)
);


ALTER TABLE public.audit_log OWNER TO sportdata_admin;

--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_log_id_seq OWNER TO sportdata_admin;

--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.categories (
    id integer NOT NULL,
    parent_id integer,
    slug character varying(100) NOT NULL,
    name character varying(200) NOT NULL,
    department_id integer,
    sort_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.categories OWNER TO sportdata_admin;

--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categories_id_seq OWNER TO sportdata_admin;

--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: departments; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.departments (
    id integer NOT NULL,
    slug character varying(50) NOT NULL,
    name character varying(200) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.departments OWNER TO sportdata_admin;

--
-- Name: departments_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.departments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.departments_id_seq OWNER TO sportdata_admin;

--
-- Name: departments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.departments_id_seq OWNED BY public.departments.id;


--
-- Name: import_logs; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.import_logs (
    id bigint NOT NULL,
    source character varying(50) NOT NULL,
    file_name character varying(500),
    status character varying(20) DEFAULT 'pending'::character varying,
    rows_total integer DEFAULT 0,
    rows_imported integer DEFAULT 0,
    rows_errors integer DEFAULT 0,
    error_details jsonb,
    imported_by uuid,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.import_logs OWNER TO sportdata_admin;

--
-- Name: import_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.import_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.import_logs_id_seq OWNER TO sportdata_admin;

--
-- Name: import_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.import_logs_id_seq OWNED BY public.import_logs.id;


--
-- Name: inventory; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.inventory (
    id bigint NOT NULL,
    product_id integer NOT NULL,
    marketplace_id integer NOT NULL,
    warehouse character varying(200),
    quantity integer DEFAULT 0 NOT NULL,
    recorded_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.inventory OWNER TO sportdata_admin;

--
-- Name: inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventory_id_seq OWNER TO sportdata_admin;

--
-- Name: inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.inventory_id_seq OWNED BY public.inventory.id;


--
-- Name: invites; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.invites (
    id integer NOT NULL,
    email character varying(255) NOT NULL,
    token character varying(128) NOT NULL,
    role_level integer NOT NULL,
    created_by uuid NOT NULL,
    used_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.invites OWNER TO sportdata_admin;

--
-- Name: invites_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.invites_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.invites_id_seq OWNER TO sportdata_admin;

--
-- Name: invites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.invites_id_seq OWNED BY public.invites.id;


--
-- Name: marketplace_credentials; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.marketplace_credentials (
    id integer NOT NULL,
    marketplace_id integer NOT NULL,
    name character varying(200) NOT NULL,
    api_key_encrypted text NOT NULL,
    client_id character varying(200),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_sync_at timestamp with time zone,
    api_key_hint text,
    user_id uuid
);


ALTER TABLE public.marketplace_credentials OWNER TO sportdata_admin;

--
-- Name: marketplace_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.marketplace_credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.marketplace_credentials_id_seq OWNER TO sportdata_admin;

--
-- Name: marketplace_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.marketplace_credentials_id_seq OWNED BY public.marketplace_credentials.id;


--
-- Name: marketplaces; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.marketplaces (
    id integer NOT NULL,
    slug character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    api_base_url character varying(500),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.marketplaces OWNER TO sportdata_admin;

--
-- Name: marketplaces_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.marketplaces_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.marketplaces_id_seq OWNER TO sportdata_admin;

--
-- Name: marketplaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.marketplaces_id_seq OWNED BY public.marketplaces.id;


--
-- Name: sales; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.sales (
    id bigint NOT NULL,
    product_id integer NOT NULL,
    marketplace_id integer NOT NULL,
    sale_date date NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    revenue numeric(14,2) DEFAULT 0 NOT NULL,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    country character varying(100),
    region character varying(200),
    warehouse character varying(200),
    warehouse_type character varying(100),
    pickup_point_id integer,
    for_pay numeric(12,2),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(12,2),
    retail_amount numeric(12,2),
    discount_price numeric(12,2),
    finished_price numeric(12,2),
    nm_id bigint,
    brand character varying(200),
    subject_name character varying(200),
    supplier_article character varying(100),
    barcode character varying(100),
    doc_type_name character varying(50),
    supplier_oper_name character varying(100),
    order_dt character varying(30),
    srid character varying(100),
    sale_id character varying(50),
    rrd_id bigint,
    gi_id bigint,
    sticker_id character varying(50),
    office_name character varying(200),
    ppvz_for_pay numeric(12,2),
    ppvz_sales_commission numeric(12,2),
    ppvz_reward numeric(12,2),
    acquiring_fee numeric(12,2),
    acquiring_percent numeric(8,4),
    ppvz_vw numeric(12,2),
    ppvz_vw_nds numeric(12,2),
    delivery_rub numeric(12,2),
    return_amount integer,
    delivery_amount integer,
    acceptance numeric(12,2),
    kiz character varying(200),
    storage_fee numeric(12,2),
    deduction numeric(12,2),
    rebill_logistic_cost numeric(12,2),
    credential_id integer
);


ALTER TABLE public.sales OWNER TO sportdata_admin;

--
-- Name: COLUMN sales.country; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON COLUMN public.sales.country IS 'Страна доставки (из WB reportDetail)';


--
-- Name: COLUMN sales.region; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON COLUMN public.sales.region IS 'Регион/область (oblastOkrugName)';


--
-- Name: COLUMN sales.warehouse; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON COLUMN public.sales.warehouse IS 'Склад отгрузки (officeName)';


--
-- Name: mv_avg_daily_sales; Type: MATERIALIZED VIEW; Schema: public; Owner: sportdata_admin
--

CREATE MATERIALIZED VIEW public.mv_avg_daily_sales AS
 SELECT product_id,
    avg(daily_qty) AS avg_daily_qty,
    sum(daily_qty) AS total_qty_30d
   FROM ( SELECT sales.product_id,
            sales.sale_date,
            sum(sales.quantity) AS daily_qty
           FROM public.sales
          WHERE ((sales.quantity > 0) AND (sales.sale_date >= (CURRENT_DATE - 30)))
          GROUP BY sales.product_id, sales.sale_date) d
  GROUP BY product_id
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.mv_avg_daily_sales OWNER TO sportdata_admin;

--
-- Name: products; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.products (
    id integer NOT NULL,
    sku character varying(100) NOT NULL,
    name character varying(500) NOT NULL,
    category_id integer,
    brand character varying(100) DEFAULT 'YourFit'::character varying,
    barcode character varying(100),
    weight_g integer,
    cost_price numeric(12,2),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    nm_id bigint
);


ALTER TABLE public.products OWNER TO sportdata_admin;

--
-- Name: mv_daily_sales; Type: MATERIALIZED VIEW; Schema: public; Owner: sportdata_admin
--

CREATE MATERIALIZED VIEW public.mv_daily_sales AS
 SELECT s.sale_date,
    s.product_id,
    s.marketplace_id,
    p.category_id,
    sum(
        CASE
            WHEN (s.quantity > 0) THEN s.quantity
            ELSE 0
        END) AS sold_qty,
    sum(
        CASE
            WHEN (s.quantity < 0) THEN abs(s.quantity)
            ELSE 0
        END) AS returned_qty,
    sum(s.quantity) AS net_qty,
    count(*) AS records,
    sum(
        CASE
            WHEN (s.quantity > 0) THEN s.revenue
            ELSE (0)::numeric
        END) AS revenue,
    sum(
        CASE
            WHEN (s.quantity > 0) THEN s.net_profit
            ELSE (0)::numeric
        END) AS profit,
    sum(
        CASE
            WHEN (s.quantity > 0) THEN s.commission
            ELSE (0)::numeric
        END) AS commission,
    sum(
        CASE
            WHEN (s.quantity > 0) THEN s.logistics_cost
            ELSE (0)::numeric
        END) AS logistics,
    sum(
        CASE
            WHEN (s.quantity > 0) THEN (COALESCE(p.cost_price, (0)::numeric) * (s.quantity)::numeric)
            ELSE (0)::numeric
        END) AS cost_of_goods
   FROM (public.sales s
     JOIN public.products p ON ((p.id = s.product_id)))
  GROUP BY s.sale_date, s.product_id, s.marketplace_id, p.category_id
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.mv_daily_sales OWNER TO sportdata_admin;

--
-- Name: orders; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    product_id integer NOT NULL,
    marketplace_id integer NOT NULL,
    external_order_id character varying(200),
    order_date timestamp with time zone NOT NULL,
    status character varying(50) DEFAULT 'new'::character varying,
    quantity integer DEFAULT 1 NOT NULL,
    price numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.orders OWNER TO sportdata_admin;

--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.orders_id_seq OWNER TO sportdata_admin;

--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: ozon_sales; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.ozon_sales (
    id bigint NOT NULL,
    credential_id integer,
    operation_id bigint,
    posting_number character varying(100),
    sku bigint,
    operation_date timestamp with time zone,
    order_date timestamp with time zone,
    offer_id character varying(100),
    product_name character varying(500),
    barcode character varying(100),
    sale_commission numeric(14,2),
    accruals_for_sale numeric(14,2),
    sale_price numeric(14,2),
    sale_qty integer DEFAULT 0,
    delivery_commission numeric(14,2),
    return_commission numeric(14,2),
    services_amount numeric(14,2),
    item_services jsonb,
    operation_type character varying(100),
    operation_type_name character varying(200),
    warehouse_name character varying(200),
    region character varying(200),
    city character varying(200),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.ozon_sales OWNER TO sportdata_admin;

--
-- Name: TABLE ozon_sales; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON TABLE public.ozon_sales IS 'Сырые данные финансового отчёта OZON';


--
-- Name: ozon_sales_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.ozon_sales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ozon_sales_id_seq OWNER TO sportdata_admin;

--
-- Name: ozon_sales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.ozon_sales_id_seq OWNED BY public.ozon_sales.id;


--
-- Name: pickup_points; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.pickup_points (
    id integer NOT NULL,
    marketplace_id integer,
    external_id character varying(100),
    name character varying(500),
    address character varying(1000),
    region character varying(200),
    city character varying(200),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.pickup_points OWNER TO sportdata_admin;

--
-- Name: pickup_points_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.pickup_points_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.pickup_points_id_seq OWNER TO sportdata_admin;

--
-- Name: pickup_points_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.pickup_points_id_seq OWNED BY public.pickup_points.id;


--
-- Name: product_current_prices; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.product_current_prices AS
 SELECT DISTINCT ON (nm_id) nm_id,
    supplier_article,
    retail_price,
    discount_price,
    sale_date AS price_date
   FROM public.sales
  WHERE (retail_price > (0)::numeric)
  ORDER BY nm_id, sale_date DESC;


ALTER VIEW public.product_current_prices OWNER TO sportdata_admin;

--
-- Name: product_mappings; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.product_mappings (
    id integer NOT NULL,
    product_id integer NOT NULL,
    marketplace_id integer NOT NULL,
    external_sku character varying(200) NOT NULL,
    external_url character varying(1000),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.product_mappings OWNER TO sportdata_admin;

--
-- Name: product_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.product_mappings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.product_mappings_id_seq OWNER TO sportdata_admin;

--
-- Name: product_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.product_mappings_id_seq OWNED BY public.product_mappings.id;


--
-- Name: product_margin_analysis; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.product_margin_analysis AS
 SELECT p.nm_id,
    p.name,
    p.sku,
    pcp.supplier_article,
    p.cost_price,
    pcp.retail_price,
    pcp.discount_price,
    round((pcp.retail_price - COALESCE(p.cost_price, (0)::numeric)), 2) AS margin_rub,
        CASE
            WHEN (pcp.retail_price > (0)::numeric) THEN round((((pcp.retail_price - COALESCE(p.cost_price, (0)::numeric)) / pcp.retail_price) * (100)::numeric), 1)
            ELSE (0)::numeric
        END AS margin_pct,
    pcp.price_date
   FROM (public.products p
     JOIN public.product_current_prices pcp ON ((p.nm_id = pcp.nm_id)));


ALTER VIEW public.product_margin_analysis OWNER TO sportdata_admin;

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.products_id_seq OWNER TO sportdata_admin;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: project_members; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.project_members (
    id integer NOT NULL,
    project_id integer NOT NULL,
    user_id uuid NOT NULL,
    marketplace_id integer,
    role character varying(20) DEFAULT 'manager'::character varying
);


ALTER TABLE public.project_members OWNER TO sportdata_admin;

--
-- Name: project_members_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.project_members_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.project_members_id_seq OWNER TO sportdata_admin;

--
-- Name: project_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.project_members_id_seq OWNED BY public.project_members.id;


--
-- Name: projects; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.projects (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    slug character varying(50) NOT NULL,
    director_id uuid,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.projects OWNER TO sportdata_admin;

--
-- Name: projects_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.projects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.projects_id_seq OWNER TO sportdata_admin;

--
-- Name: projects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.projects_id_seq OWNED BY public.projects.id;


--
-- Name: returns; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.returns (
    id bigint NOT NULL,
    product_id integer NOT NULL,
    marketplace_id integer NOT NULL,
    order_id bigint,
    return_date date NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    reason character varying(500),
    penalty numeric(12,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    warehouse character varying(200),
    return_amount numeric(14,2) DEFAULT 0,
    logistics_cost numeric(12,2) DEFAULT 0
);


ALTER TABLE public.returns OWNER TO sportdata_admin;

--
-- Name: returns_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.returns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.returns_id_seq OWNER TO sportdata_admin;

--
-- Name: returns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.returns_id_seq OWNED BY public.returns.id;


--
-- Name: rnp; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp (
    id bigint NOT NULL,
    marketplace_id integer NOT NULL,
    operation_date date NOT NULL,
    category character varying(100) NOT NULL,
    subcategory character varying(200),
    description text,
    amount numeric(14,2) NOT NULL,
    document_id character varying(200),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.rnp OWNER TO sportdata_admin;

--
-- Name: rnp_categories; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_categories (
    id integer NOT NULL,
    slug character varying(50) NOT NULL,
    name character varying(200) NOT NULL,
    color character varying(7) DEFAULT '#6B7280'::character varying,
    sort_order integer DEFAULT 0
);


ALTER TABLE public.rnp_categories OWNER TO sportdata_admin;

--
-- Name: rnp_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_categories_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_categories_id_seq OWNED BY public.rnp_categories.id;


--
-- Name: rnp_checklist_items; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_checklist_items (
    id integer NOT NULL,
    item_id integer NOT NULL,
    template_id integer NOT NULL,
    is_done boolean DEFAULT false,
    done_at timestamp with time zone,
    done_by uuid,
    comment text
);


ALTER TABLE public.rnp_checklist_items OWNER TO sportdata_admin;

--
-- Name: rnp_checklist_items_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_checklist_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_checklist_items_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_checklist_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_checklist_items_id_seq OWNED BY public.rnp_checklist_items.id;


--
-- Name: rnp_checklist_templates; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_checklist_templates (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    sort_order integer DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.rnp_checklist_templates OWNER TO sportdata_admin;

--
-- Name: rnp_checklist_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_checklist_templates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_checklist_templates_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_checklist_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_checklist_templates_id_seq OWNED BY public.rnp_checklist_templates.id;


--
-- Name: rnp_daily; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_daily (
    id integer NOT NULL,
    item_id integer NOT NULL,
    date date NOT NULL,
    target_qty integer DEFAULT 0,
    fact_qty integer DEFAULT 0,
    fact_rub numeric(10,2) DEFAULT 0,
    fact_price numeric(10,2),
    status character varying(10)
);


ALTER TABLE public.rnp_daily OWNER TO sportdata_admin;

--
-- Name: rnp_daily_facts; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_daily_facts (
    id integer NOT NULL,
    item_id integer NOT NULL,
    fact_date date NOT NULL,
    target_orders_qty integer DEFAULT 0,
    fact_orders_qty integer DEFAULT 0,
    fact_orders_rub numeric(12,2),
    stock_fbo integer DEFAULT 0,
    stock_fbs integer DEFAULT 0,
    current_price numeric(10,2),
    discount_percent numeric(5,2) DEFAULT 0,
    spp_percent numeric(5,2) DEFAULT 0,
    comment text,
    created_at timestamp with time zone DEFAULT now(),
    plan_orders_day integer DEFAULT 0
);


ALTER TABLE public.rnp_daily_facts OWNER TO sportdata_admin;

--
-- Name: rnp_daily_facts_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_daily_facts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_daily_facts_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_daily_facts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_daily_facts_id_seq OWNED BY public.rnp_daily_facts.id;


--
-- Name: rnp_daily_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_daily_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_daily_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_daily_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_daily_id_seq OWNED BY public.rnp_daily.id;


--
-- Name: rnp_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_id_seq OWNED BY public.rnp.id;


--
-- Name: rnp_items; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_items (
    id integer NOT NULL,
    template_id integer NOT NULL,
    product_id integer,
    nm_id bigint,
    sku character varying(100),
    barcode character varying(50),
    size character varying(20) DEFAULT '0'::character varying,
    name character varying(500),
    category character varying(200),
    season character varying(20) DEFAULT 'all_season'::character varying,
    photo_url text,
    plan_orders_qty integer DEFAULT 0,
    plan_orders_rub numeric(12,2) DEFAULT 0,
    plan_price numeric(10,2) DEFAULT 0,
    fact_orders_qty integer DEFAULT 0,
    fact_orders_rub numeric(12,2) DEFAULT 0,
    fact_avg_price numeric(10,2) DEFAULT 0,
    stock_fbo integer DEFAULT 0,
    stock_fbs integer DEFAULT 0,
    stock_in_transit integer DEFAULT 0,
    stock_1c integer DEFAULT 0,
    turnover_mtd numeric(6,1),
    turnover_7d numeric(6,1),
    reviews_avg_rating numeric(2,1),
    reviews_status character varying(10),
    is_active boolean DEFAULT true,
    updated_at timestamp with time zone DEFAULT now(),
    status public.rnp_status DEFAULT 'liquidation'::public.rnp_status,
    target_orders_day integer DEFAULT 0,
    weekly_task_plan integer DEFAULT 0,
    spp_percent numeric(5,2) DEFAULT 0,
    days_of_stock integer DEFAULT 0,
    days_of_stock_7d integer DEFAULT 0,
    review_1_stars integer,
    review_2_stars integer,
    review_3_stars integer,
    reviews_ok boolean DEFAULT true,
    content_task_url text,
    checklist_url text,
    monitoring_url text,
    has_discount boolean DEFAULT false,
    needs_attention boolean DEFAULT false,
    notes text,
    manager_id uuid,
    period_start date DEFAULT CURRENT_DATE,
    period_end date,
    sort_order integer DEFAULT 0,
    item_status character varying(20) DEFAULT 'ok'::character varying,
    checklist_done integer DEFAULT 0,
    checklist_total integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.rnp_items OWNER TO sportdata_admin;

--
-- Name: rnp_items_daily; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_items_daily (
    id integer NOT NULL,
    item_id integer NOT NULL,
    date date NOT NULL,
    orders_qty integer DEFAULT 0,
    orders_rub numeric(12,2) DEFAULT 0,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.rnp_items_daily OWNER TO sportdata_admin;

--
-- Name: rnp_items_daily_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_items_daily_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_items_daily_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_items_daily_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_items_daily_id_seq OWNED BY public.rnp_items_daily.id;


--
-- Name: rnp_items_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_items_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_items_id_seq OWNED BY public.rnp_items.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    role_id integer NOT NULL,
    is_active boolean DEFAULT true,
    is_hidden boolean DEFAULT false,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    avatar_url character varying(255)
);


ALTER TABLE public.users OWNER TO sportdata_admin;

--
-- Name: rnp_items_summary; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.rnp_items_summary AS
 SELECT i.id,
    i.template_id,
    i.name,
    i.sku,
    i.nm_id,
    i.size,
    i.photo_url,
    i.category,
    i.status,
    i.plan_orders_qty AS target_orders_month,
    i.target_orders_day,
    i.plan_price,
    i.weekly_task_plan,
    i.fact_orders_qty,
    i.fact_orders_rub,
    i.fact_avg_price AS fact_price,
    i.spp_percent,
    i.stock_fbo,
    i.stock_fbs,
    (i.stock_fbo + i.stock_fbs) AS stock_total,
    i.days_of_stock,
    i.days_of_stock_7d,
    i.review_1_stars,
    i.review_2_stars,
    i.review_3_stars,
    i.reviews_ok,
    i.content_task_url AS tz_content_url,
    i.checklist_url,
    i.monitoring_url,
    i.has_discount,
    i.needs_attention,
    i.is_active,
    i.notes AS comment,
        CASE
            WHEN (i.plan_orders_qty > 0) THEN round((((i.fact_orders_qty)::numeric / (i.plan_orders_qty)::numeric) * (100)::numeric), 1)
            ELSE (0)::numeric
        END AS completion_percent,
    ( SELECT count(*) FILTER (WHERE ci.is_done) AS count
           FROM public.rnp_checklist_items ci
          WHERE (ci.item_id = i.id)) AS checklist_done,
    ( SELECT count(*) AS count
           FROM public.rnp_checklist_items ci
          WHERE (ci.item_id = i.id)) AS checklist_total,
    i.manager_id,
    (((u.first_name)::text || ' '::text) || (u.last_name)::text) AS manager_name,
    i.period_start,
    i.period_end,
    i.created_at,
    i.updated_at
   FROM (public.rnp_items i
     LEFT JOIN public.users u ON ((u.id = i.manager_id)))
  WHERE (i.is_active = true);


ALTER VIEW public.rnp_items_summary OWNER TO sportdata_admin;

--
-- Name: rnp_price_history; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_price_history (
    id integer NOT NULL,
    item_id integer,
    changed_at timestamp with time zone DEFAULT now(),
    old_price numeric(12,2),
    new_price numeric(12,2),
    old_spp numeric(5,2),
    new_spp numeric(5,2),
    reason text,
    changed_by uuid
);


ALTER TABLE public.rnp_price_history OWNER TO sportdata_admin;

--
-- Name: rnp_price_history_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_price_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_price_history_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_price_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_price_history_id_seq OWNED BY public.rnp_price_history.id;


--
-- Name: rnp_templates; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.rnp_templates (
    id integer NOT NULL,
    project_id integer NOT NULL,
    manager_id uuid NOT NULL,
    marketplace_id integer NOT NULL,
    year integer NOT NULL,
    month integer NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT rnp_templates_month_check CHECK (((month >= 1) AND (month <= 12)))
);


ALTER TABLE public.rnp_templates OWNER TO sportdata_admin;

--
-- Name: rnp_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.rnp_templates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rnp_templates_id_seq OWNER TO sportdata_admin;

--
-- Name: rnp_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.rnp_templates_id_seq OWNED BY public.rnp_templates.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    slug character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    level integer NOT NULL,
    is_hidden boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.roles OWNER TO sportdata_admin;

--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_id_seq OWNER TO sportdata_admin;

--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: sales_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.sales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sales_id_seq OWNER TO sportdata_admin;

--
-- Name: sales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.sales_id_seq OWNED BY public.sales.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.schema_migrations (
    filename text NOT NULL,
    applied_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.schema_migrations OWNER TO sportdata_admin;

--
-- Name: staging_sales_update; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.staging_sales_update (
    id bigint NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date,
    quantity integer,
    revenue numeric(14,2),
    commission numeric(14,2),
    logistics_cost numeric(14,2),
    net_profit numeric(14,2),
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.staging_sales_update OWNER TO sportdata_admin;

--
-- Name: staging_sales_update_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.staging_sales_update_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.staging_sales_update_id_seq OWNER TO sportdata_admin;

--
-- Name: staging_sales_update_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.staging_sales_update_id_seq OWNED BY public.staging_sales_update.id;


--
-- Name: stocks; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.stocks (
    id integer NOT NULL,
    credential_id integer,
    marketplace character varying(50) NOT NULL,
    sku character varying(100),
    barcode character varying(100),
    warehouse_id character varying(50),
    warehouse_name character varying(255),
    quantity integer DEFAULT 0 NOT NULL,
    quantity_full integer DEFAULT 0,
    quantity_promised integer DEFAULT 0,
    in_way_to_client integer DEFAULT 0,
    in_way_from_client integer DEFAULT 0,
    updated_at timestamp without time zone DEFAULT now(),
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.stocks OWNER TO sportdata_admin;

--
-- Name: stocks_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.stocks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stocks_id_seq OWNER TO sportdata_admin;

--
-- Name: stocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.stocks_id_seq OWNED BY public.stocks.id;


--
-- Name: sync_history; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.sync_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    marketplace character varying(50) NOT NULL,
    sync_type character varying(50) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    started_at timestamp with time zone DEFAULT now(),
    finished_at timestamp with time zone,
    items_synced integer DEFAULT 0,
    error_message text,
    triggered_by uuid,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.sync_history OWNER TO sportdata_admin;

--
-- Name: sync_jobs; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.sync_jobs (
    id bigint NOT NULL,
    marketplace_id integer NOT NULL,
    job_type character varying(50) NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    records_processed integer DEFAULT 0,
    error_message text,
    created_at timestamp with time zone DEFAULT now(),
    credential_id integer
);


ALTER TABLE public.sync_jobs OWNER TO sportdata_admin;

--
-- Name: sync_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.sync_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sync_jobs_id_seq OWNER TO sportdata_admin;

--
-- Name: sync_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.sync_jobs_id_seq OWNED BY public.sync_jobs.id;


--
-- Name: trending_products; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.trending_products AS
 WITH weekly AS (
         SELECT s.product_id,
            p.name,
            p.category_id,
            sum(
                CASE
                    WHEN (s.sale_date >= (CURRENT_DATE - 7)) THEN s.quantity
                    ELSE 0
                END) AS sales_7d,
            sum(
                CASE
                    WHEN ((s.sale_date >= (CURRENT_DATE - 14)) AND (s.sale_date < (CURRENT_DATE - 7))) THEN s.quantity
                    ELSE 0
                END) AS prev_sales_7d
           FROM (public.sales s
             JOIN public.products p ON ((p.id = s.product_id)))
          WHERE (s.sale_date >= (CURRENT_DATE - 14))
          GROUP BY s.product_id, p.name, p.category_id
        )
 SELECT product_id,
    name,
    category_id,
    sales_7d,
    prev_sales_7d
   FROM weekly;


ALTER VIEW public.trending_products OWNER TO sportdata_admin;

--
-- Name: unified_sales; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.unified_sales (
    id bigint NOT NULL,
    marketplace_id integer NOT NULL,
    credential_id integer,
    source_table character varying(50) NOT NULL,
    source_id bigint NOT NULL,
    order_id character varying(100),
    product_sku character varying(100),
    barcode character varying(100),
    sale_date date NOT NULL,
    order_date date,
    product_id integer,
    product_name character varying(500),
    brand character varying(200),
    category character varying(200),
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    for_pay numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics numeric(14,2) DEFAULT 0,
    retail_price numeric(14,2),
    discount_percent numeric(8,2),
    return_amount numeric(14,2) DEFAULT 0,
    penalty numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    other_fees numeric(14,2) DEFAULT 0,
    operation_type character varying(50),
    operation_name character varying(200),
    region character varying(200),
    warehouse character varying(200),
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.unified_sales OWNER TO sportdata_admin;

--
-- Name: TABLE unified_sales; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON TABLE public.unified_sales IS 'Унифицированная витрина продаж со всех маркетплейсов';


--
-- Name: unified_sales_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.unified_sales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.unified_sales_id_seq OWNER TO sportdata_admin;

--
-- Name: unified_sales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.unified_sales_id_seq OWNED BY public.unified_sales.id;


--
-- Name: user_departments; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.user_departments (
    user_id uuid NOT NULL,
    department_id integer NOT NULL
);


ALTER TABLE public.user_departments OWNER TO sportdata_admin;

--
-- Name: user_marketplaces; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.user_marketplaces (
    user_id uuid NOT NULL,
    marketplace_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.user_marketplaces OWNER TO sportdata_admin;

--
-- Name: v_current_inventory; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.v_current_inventory AS
 SELECT DISTINCT ON (i.product_id, i.marketplace_id) p.sku,
    p.name AS product_name,
    m.slug AS marketplace,
    i.warehouse,
    i.quantity,
    i.recorded_at
   FROM ((public.inventory i
     JOIN public.products p ON ((p.id = i.product_id)))
     JOIN public.marketplaces m ON ((m.id = i.marketplace_id)))
  ORDER BY i.product_id, i.marketplace_id, i.recorded_at DESC;


ALTER VIEW public.v_current_inventory OWNER TO sportdata_admin;

--
-- Name: v_daily_sales; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.v_daily_sales AS
 SELECT s.sale_date,
    p.sku,
    p.name AS product_name,
    c.name AS category_name,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    s.country,
    s.region,
    s.warehouse,
    sum(s.quantity) AS total_qty,
    sum(s.revenue) AS total_revenue,
    sum(s.commission) AS total_commission,
    sum(s.logistics_cost) AS total_logistics,
    sum(s.net_profit) AS total_profit
   FROM (((public.sales s
     JOIN public.products p ON ((p.id = s.product_id)))
     JOIN public.marketplaces m ON ((m.id = s.marketplace_id)))
     LEFT JOIN public.categories c ON ((c.id = p.category_id)))
  GROUP BY s.sale_date, p.sku, p.name, c.name, m.slug, m.name, s.country, s.region, s.warehouse;


ALTER VIEW public.v_daily_sales OWNER TO sportdata_admin;

--
-- Name: v_product_sales; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.v_product_sales AS
 SELECT sale_date,
    marketplace_id,
    product_sku,
    product_name,
    brand,
    sum(
        CASE
            WHEN ((operation_type)::text = 'sale'::text) THEN quantity
            ELSE 0
        END) AS sold_qty,
    sum(
        CASE
            WHEN ((operation_type)::text = 'return'::text) THEN abs(quantity)
            ELSE 0
        END) AS returned_qty,
    sum(
        CASE
            WHEN ((operation_type)::text = 'sale'::text) THEN revenue
            ELSE (0)::numeric
        END) AS gross_revenue,
    sum(for_pay) AS net_revenue,
    sum(commission) AS total_commission,
    sum(logistics) AS total_logistics
   FROM public.unified_sales
  WHERE ((operation_type)::text = ANY ((ARRAY['sale'::character varying, 'return'::character varying])::text[]))
  GROUP BY sale_date, marketplace_id, product_sku, product_name, brand;


ALTER VIEW public.v_product_sales OWNER TO sportdata_admin;

--
-- Name: VIEW v_product_sales; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON VIEW public.v_product_sales IS 'Продажи в разрезе товаров';


--
-- Name: v_rnp_monthly; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.v_rnp_monthly AS
 SELECT (date_trunc('month'::text, (r.operation_date)::timestamp with time zone))::date AS month,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    r.category,
    rc.name AS category_name,
    sum(r.amount) AS total_amount,
    count(*) AS operations_count
   FROM ((public.rnp r
     JOIN public.marketplaces m ON ((m.id = r.marketplace_id)))
     LEFT JOIN public.rnp_categories rc ON (((rc.slug)::text = (r.category)::text)))
  GROUP BY (date_trunc('month'::text, (r.operation_date)::timestamp with time zone)), m.slug, m.name, r.category, rc.name;


ALTER VIEW public.v_rnp_monthly OWNER TO sportdata_admin;

--
-- Name: v_rnp_summary; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.v_rnp_summary AS
 SELECT r.operation_date,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    r.category,
    rc.name AS category_name,
    rc.color AS category_color,
    sum(r.amount) AS total_amount,
    count(*) AS operations_count
   FROM ((public.rnp r
     JOIN public.marketplaces m ON ((m.id = r.marketplace_id)))
     LEFT JOIN public.rnp_categories rc ON (((rc.slug)::text = (r.category)::text)))
  GROUP BY r.operation_date, m.slug, m.name, r.category, rc.name, rc.color;


ALTER VIEW public.v_rnp_summary OWNER TO sportdata_admin;

--
-- Name: v_sales_summary; Type: VIEW; Schema: public; Owner: sportdata_admin
--

CREATE VIEW public.v_sales_summary AS
 SELECT sale_date,
    marketplace_id,
    operation_type,
    count(*) AS operations_count,
    sum(quantity) AS total_qty,
    sum(revenue) AS total_revenue,
    sum(for_pay) AS total_for_pay,
    sum(commission) AS total_commission,
    sum(logistics) AS total_logistics,
    sum(penalty) AS total_penalty
   FROM public.unified_sales
  GROUP BY sale_date, marketplace_id, operation_type;


ALTER VIEW public.v_sales_summary OWNER TO sportdata_admin;

--
-- Name: VIEW v_sales_summary; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON VIEW public.v_sales_summary IS 'Сводка продаж по дням и типам операций';


--
-- Name: wb_sales; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.wb_sales (
    id bigint NOT NULL,
    rrd_id bigint,
    srid character varying(100),
    rid bigint,
    gi_id bigint,
    shk_id bigint,
    sale_dt date NOT NULL,
    order_dt timestamp without time zone,
    rr_dt timestamp without time zone,
    create_dt timestamp without time zone,
    nm_id bigint,
    supplier_article character varying(100),
    barcode character varying(100),
    brand character varying(200),
    subject_name character varying(200),
    ts_name character varying(100),
    doc_type_name character varying(50),
    supplier_oper_name character varying(100),
    quantity integer DEFAULT 0,
    retail_price numeric(12,2),
    retail_amount numeric(12,2),
    retail_price_withdisc_rub numeric(12,2),
    sale_percent integer,
    commission_percent numeric(8,4),
    ppvz_spp_prc numeric(8,4),
    ppvz_kvw_prc numeric(8,4),
    ppvz_kvw_prc_base numeric(8,4),
    ppvz_sales_commission numeric(12,2),
    ppvz_for_pay numeric(12,2),
    ppvz_reward numeric(12,2),
    ppvz_vw numeric(12,2),
    ppvz_vw_nds numeric(12,2),
    acquiring_fee numeric(12,2),
    acquiring_percent numeric(8,4),
    acquiring_bank character varying(100),
    delivery_amount integer,
    return_amount integer,
    delivery_rub numeric(12,2),
    rebill_logistic_cost numeric(12,2),
    rebill_logistic_org character varying(200),
    penalty numeric(12,2) DEFAULT 0,
    additional_payment numeric(12,2),
    deduction numeric(12,2),
    storage_fee numeric(12,2),
    acceptance numeric(12,2),
    country_name character varying(100),
    oblast_okrug_name character varying(200),
    region_name character varying(200),
    office_name character varying(200),
    ppvz_office_id bigint,
    ppvz_office_name character varying(200),
    gi_box_type_name character varying(100),
    ppvz_supplier_id bigint,
    ppvz_supplier_name character varying(200),
    ppvz_inn character varying(20),
    supplier_contract_code character varying(50),
    sticker_id character varying(50),
    kiz character varying(200),
    bonus_type_name character varying(100),
    declaration_number character varying(100),
    product_discount_for_report numeric(12,2),
    supplier_promo numeric(12,2),
    report_type integer,
    credential_id integer,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wb_sales OWNER TO sportdata_admin;

--
-- Name: wb_sales_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.wb_sales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wb_sales_id_seq OWNER TO sportdata_admin;

--
-- Name: wb_sales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.wb_sales_id_seq OWNED BY public.wb_sales.id;


--
-- Name: ym_sales; Type: TABLE; Schema: public; Owner: sportdata_admin
--

CREATE TABLE public.ym_sales (
    id bigint NOT NULL,
    credential_id integer,
    order_id bigint,
    order_item_id bigint,
    shipment_id bigint,
    order_date timestamp with time zone,
    shipment_date timestamp with time zone,
    payment_date timestamp with time zone,
    offer_id character varying(100),
    shop_sku character varying(100),
    market_sku bigint,
    product_name character varying(500),
    barcode character varying(100),
    price numeric(14,2),
    buyer_price numeric(14,2),
    quantity integer DEFAULT 0,
    subsidy numeric(14,2),
    commission numeric(14,2),
    fee_total numeric(14,2),
    delivery_fee numeric(14,2),
    return_fee numeric(14,2),
    storage_fee numeric(14,2),
    operation_type character varying(100),
    order_status character varying(50),
    warehouse_name character varying(200),
    region character varying(200),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.ym_sales OWNER TO sportdata_admin;

--
-- Name: TABLE ym_sales; Type: COMMENT; Schema: public; Owner: sportdata_admin
--

COMMENT ON TABLE public.ym_sales IS 'Сырые данные финансового отчёта Яндекс.Маркет';


--
-- Name: ym_sales_id_seq; Type: SEQUENCE; Schema: public; Owner: sportdata_admin
--

CREATE SEQUENCE public.ym_sales_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ym_sales_id_seq OWNER TO sportdata_admin;

--
-- Name: ym_sales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: sportdata_admin
--

ALTER SEQUENCE public.ym_sales_id_seq OWNED BY public.ym_sales.id;


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: departments id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.departments ALTER COLUMN id SET DEFAULT nextval('public.departments_id_seq'::regclass);


--
-- Name: import_logs id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.import_logs ALTER COLUMN id SET DEFAULT nextval('public.import_logs_id_seq'::regclass);


--
-- Name: inventory id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.inventory ALTER COLUMN id SET DEFAULT nextval('public.inventory_id_seq'::regclass);


--
-- Name: invites id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.invites ALTER COLUMN id SET DEFAULT nextval('public.invites_id_seq'::regclass);


--
-- Name: marketplace_credentials id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.marketplace_credentials ALTER COLUMN id SET DEFAULT nextval('public.marketplace_credentials_id_seq'::regclass);


--
-- Name: marketplaces id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.marketplaces ALTER COLUMN id SET DEFAULT nextval('public.marketplaces_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: ozon_sales id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.ozon_sales ALTER COLUMN id SET DEFAULT nextval('public.ozon_sales_id_seq'::regclass);


--
-- Name: pickup_points id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.pickup_points ALTER COLUMN id SET DEFAULT nextval('public.pickup_points_id_seq'::regclass);


--
-- Name: product_mappings id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.product_mappings ALTER COLUMN id SET DEFAULT nextval('public.product_mappings_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: project_members id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.project_members ALTER COLUMN id SET DEFAULT nextval('public.project_members_id_seq'::regclass);


--
-- Name: projects id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.projects ALTER COLUMN id SET DEFAULT nextval('public.projects_id_seq'::regclass);


--
-- Name: returns id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.returns ALTER COLUMN id SET DEFAULT nextval('public.returns_id_seq'::regclass);


--
-- Name: rnp id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp ALTER COLUMN id SET DEFAULT nextval('public.rnp_id_seq'::regclass);


--
-- Name: rnp_categories id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_categories ALTER COLUMN id SET DEFAULT nextval('public.rnp_categories_id_seq'::regclass);


--
-- Name: rnp_checklist_items id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_items ALTER COLUMN id SET DEFAULT nextval('public.rnp_checklist_items_id_seq'::regclass);


--
-- Name: rnp_checklist_templates id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_templates ALTER COLUMN id SET DEFAULT nextval('public.rnp_checklist_templates_id_seq'::regclass);


--
-- Name: rnp_daily id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily ALTER COLUMN id SET DEFAULT nextval('public.rnp_daily_id_seq'::regclass);


--
-- Name: rnp_daily_facts id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily_facts ALTER COLUMN id SET DEFAULT nextval('public.rnp_daily_facts_id_seq'::regclass);


--
-- Name: rnp_items id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items ALTER COLUMN id SET DEFAULT nextval('public.rnp_items_id_seq'::regclass);


--
-- Name: rnp_items_daily id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items_daily ALTER COLUMN id SET DEFAULT nextval('public.rnp_items_daily_id_seq'::regclass);


--
-- Name: rnp_price_history id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_price_history ALTER COLUMN id SET DEFAULT nextval('public.rnp_price_history_id_seq'::regclass);


--
-- Name: rnp_templates id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_templates ALTER COLUMN id SET DEFAULT nextval('public.rnp_templates_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: sales id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sales ALTER COLUMN id SET DEFAULT nextval('public.sales_id_seq'::regclass);


--
-- Name: staging_sales_update id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.staging_sales_update ALTER COLUMN id SET DEFAULT nextval('public.staging_sales_update_id_seq'::regclass);


--
-- Name: stocks id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.stocks ALTER COLUMN id SET DEFAULT nextval('public.stocks_id_seq'::regclass);


--
-- Name: sync_jobs id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sync_jobs ALTER COLUMN id SET DEFAULT nextval('public.sync_jobs_id_seq'::regclass);


--
-- Name: unified_sales id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.unified_sales ALTER COLUMN id SET DEFAULT nextval('public.unified_sales_id_seq'::regclass);


--
-- Name: wb_sales id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.wb_sales ALTER COLUMN id SET DEFAULT nextval('public.wb_sales_id_seq'::regclass);


--
-- Name: ym_sales id; Type: DEFAULT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.ym_sales ALTER COLUMN id SET DEFAULT nextval('public.ym_sales_id_seq'::regclass);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: departments departments_slug_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_slug_key UNIQUE (slug);


--
-- Name: import_logs import_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.import_logs
    ADD CONSTRAINT import_logs_pkey PRIMARY KEY (id);


--
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (id);


--
-- Name: invites invites_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_pkey PRIMARY KEY (id);


--
-- Name: invites invites_token_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_token_key UNIQUE (token);


--
-- Name: marketplace_credentials marketplace_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.marketplace_credentials
    ADD CONSTRAINT marketplace_credentials_pkey PRIMARY KEY (id);


--
-- Name: marketplaces marketplaces_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.marketplaces
    ADD CONSTRAINT marketplaces_pkey PRIMARY KEY (id);


--
-- Name: marketplaces marketplaces_slug_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.marketplaces
    ADD CONSTRAINT marketplaces_slug_key UNIQUE (slug);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: ozon_sales ozon_sales_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.ozon_sales
    ADD CONSTRAINT ozon_sales_pkey PRIMARY KEY (id);


--
-- Name: pickup_points pickup_points_marketplace_id_external_id_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.pickup_points
    ADD CONSTRAINT pickup_points_marketplace_id_external_id_key UNIQUE (marketplace_id, external_id);


--
-- Name: pickup_points pickup_points_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.pickup_points
    ADD CONSTRAINT pickup_points_pkey PRIMARY KEY (id);


--
-- Name: product_mappings product_mappings_marketplace_id_external_sku_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_marketplace_id_external_sku_key UNIQUE (marketplace_id, external_sku);


--
-- Name: product_mappings product_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_pkey PRIMARY KEY (id);


--
-- Name: products products_nm_id_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_nm_id_key UNIQUE (nm_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_sku_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_sku_key UNIQUE (sku);


--
-- Name: project_members project_members_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_pkey PRIMARY KEY (id);


--
-- Name: project_members project_members_project_id_user_id_marketplace_id_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_project_id_user_id_marketplace_id_key UNIQUE (project_id, user_id, marketplace_id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: projects projects_slug_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_slug_key UNIQUE (slug);


--
-- Name: returns returns_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_pkey PRIMARY KEY (id);


--
-- Name: rnp_categories rnp_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_categories
    ADD CONSTRAINT rnp_categories_pkey PRIMARY KEY (id);


--
-- Name: rnp_categories rnp_categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_categories
    ADD CONSTRAINT rnp_categories_slug_key UNIQUE (slug);


--
-- Name: rnp_checklist_items rnp_checklist_items_item_id_template_id_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_items
    ADD CONSTRAINT rnp_checklist_items_item_id_template_id_key UNIQUE (item_id, template_id);


--
-- Name: rnp_checklist_items rnp_checklist_items_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_items
    ADD CONSTRAINT rnp_checklist_items_pkey PRIMARY KEY (id);


--
-- Name: rnp_checklist_templates rnp_checklist_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_templates
    ADD CONSTRAINT rnp_checklist_templates_pkey PRIMARY KEY (id);


--
-- Name: rnp_daily_facts rnp_daily_facts_item_id_fact_date_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily_facts
    ADD CONSTRAINT rnp_daily_facts_item_id_fact_date_key UNIQUE (item_id, fact_date);


--
-- Name: rnp_daily_facts rnp_daily_facts_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily_facts
    ADD CONSTRAINT rnp_daily_facts_pkey PRIMARY KEY (id);


--
-- Name: rnp_daily rnp_daily_item_id_date_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily
    ADD CONSTRAINT rnp_daily_item_id_date_key UNIQUE (item_id, date);


--
-- Name: rnp_daily rnp_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily
    ADD CONSTRAINT rnp_daily_pkey PRIMARY KEY (id);


--
-- Name: rnp_items_daily rnp_items_daily_item_id_date_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items_daily
    ADD CONSTRAINT rnp_items_daily_item_id_date_key UNIQUE (item_id, date);


--
-- Name: rnp_items_daily rnp_items_daily_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items_daily
    ADD CONSTRAINT rnp_items_daily_pkey PRIMARY KEY (id);


--
-- Name: rnp_items rnp_items_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items
    ADD CONSTRAINT rnp_items_pkey PRIMARY KEY (id);


--
-- Name: rnp rnp_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp
    ADD CONSTRAINT rnp_pkey PRIMARY KEY (id);


--
-- Name: rnp_price_history rnp_price_history_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_price_history
    ADD CONSTRAINT rnp_price_history_pkey PRIMARY KEY (id);


--
-- Name: rnp_templates rnp_templates_manager_id_marketplace_id_year_month_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_templates
    ADD CONSTRAINT rnp_templates_manager_id_marketplace_id_year_month_key UNIQUE (manager_id, marketplace_id, year, month);


--
-- Name: rnp_templates rnp_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_templates
    ADD CONSTRAINT rnp_templates_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: roles roles_slug_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_slug_key UNIQUE (slug);


--
-- Name: sales sales_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (filename);


--
-- Name: staging_sales_update staging_sales_update_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.staging_sales_update
    ADD CONSTRAINT staging_sales_update_pkey PRIMARY KEY (id);


--
-- Name: stocks stocks_credential_id_sku_warehouse_id_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_credential_id_sku_warehouse_id_key UNIQUE (credential_id, sku, warehouse_id);


--
-- Name: stocks stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_pkey PRIMARY KEY (id);


--
-- Name: sync_history sync_history_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sync_history
    ADD CONSTRAINT sync_history_pkey PRIMARY KEY (id);


--
-- Name: sync_jobs sync_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sync_jobs
    ADD CONSTRAINT sync_jobs_pkey PRIMARY KEY (id);


--
-- Name: unified_sales unified_sales_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.unified_sales
    ADD CONSTRAINT unified_sales_pkey PRIMARY KEY (id);


--
-- Name: unified_sales unified_sales_source_table_source_id_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.unified_sales
    ADD CONSTRAINT unified_sales_source_table_source_id_key UNIQUE (source_table, source_id);


--
-- Name: user_departments user_departments_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.user_departments
    ADD CONSTRAINT user_departments_pkey PRIMARY KEY (user_id, department_id);


--
-- Name: user_marketplaces user_marketplaces_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.user_marketplaces
    ADD CONSTRAINT user_marketplaces_pkey PRIMARY KEY (user_id, marketplace_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wb_sales wb_sales_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.wb_sales
    ADD CONSTRAINT wb_sales_pkey PRIMARY KEY (id);


--
-- Name: ym_sales ym_sales_pkey; Type: CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.ym_sales
    ADD CONSTRAINT ym_sales_pkey PRIMARY KEY (id);


--
-- Name: idx_audit_created; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_audit_created ON public.audit_log USING btree (created_at);


--
-- Name: idx_audit_user; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_audit_user ON public.audit_log USING btree (user_id);


--
-- Name: idx_credentials_marketplace_active; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_credentials_marketplace_active ON public.marketplace_credentials USING btree (marketplace_id) WHERE (is_active = true);


--
-- Name: idx_credentials_user_marketplace; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_credentials_user_marketplace ON public.marketplace_credentials USING btree (user_id, marketplace_id);


--
-- Name: idx_inventory_product; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_inventory_product ON public.inventory USING btree (product_id);


--
-- Name: idx_inventory_recorded; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_inventory_recorded ON public.inventory USING btree (recorded_at);


--
-- Name: idx_invites_created_by; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_invites_created_by ON public.invites USING btree (created_by);


--
-- Name: idx_invites_token; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_invites_token ON public.invites USING btree (token);


--
-- Name: idx_orders_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_orders_date ON public.orders USING btree (order_date);


--
-- Name: idx_orders_product; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_orders_product ON public.orders USING btree (product_id);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_ozon_sales_cred; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_ozon_sales_cred ON public.ozon_sales USING btree (credential_id);


--
-- Name: idx_ozon_sales_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_ozon_sales_date ON public.ozon_sales USING btree (operation_date);


--
-- Name: idx_ozon_sales_sku; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_ozon_sales_sku ON public.ozon_sales USING btree (sku);


--
-- Name: idx_ozon_sales_uniq; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_ozon_sales_uniq ON public.ozon_sales USING btree (operation_id, posting_number) WHERE (operation_id IS NOT NULL);


--
-- Name: idx_products_nm_id; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_products_nm_id ON public.products USING btree (nm_id);


--
-- Name: idx_returns_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_returns_date ON public.returns USING btree (return_date);


--
-- Name: idx_returns_warehouse; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_returns_warehouse ON public.returns USING btree (warehouse);


--
-- Name: idx_rnp_category; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_category ON public.rnp USING btree (category);


--
-- Name: idx_rnp_checklist_item; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_checklist_item ON public.rnp_checklist_items USING btree (item_id);


--
-- Name: idx_rnp_daily_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_daily_date ON public.rnp_daily USING btree (date);


--
-- Name: idx_rnp_daily_facts_item_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_daily_facts_item_date ON public.rnp_daily_facts USING btree (item_id, fact_date);


--
-- Name: idx_rnp_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_date ON public.rnp USING btree (operation_date);


--
-- Name: idx_rnp_date_mp; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_date_mp ON public.rnp USING btree (operation_date, marketplace_id);


--
-- Name: idx_rnp_items_attention; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_attention ON public.rnp_items USING btree (needs_attention) WHERE (needs_attention = true);


--
-- Name: idx_rnp_items_daily_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_daily_date ON public.rnp_items_daily USING btree (date);


--
-- Name: idx_rnp_items_daily_item; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_daily_item ON public.rnp_items_daily USING btree (item_id);


--
-- Name: idx_rnp_items_manager; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_manager ON public.rnp_items USING btree (manager_id);


--
-- Name: idx_rnp_items_nm; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_nm ON public.rnp_items USING btree (nm_id);


--
-- Name: idx_rnp_items_reviews_ok; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_reviews_ok ON public.rnp_items USING btree (reviews_ok);


--
-- Name: idx_rnp_items_status; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_status ON public.rnp_items USING btree (status);


--
-- Name: idx_rnp_items_template; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_items_template ON public.rnp_items USING btree (template_id);


--
-- Name: idx_rnp_marketplace; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_marketplace ON public.rnp USING btree (marketplace_id);


--
-- Name: idx_rnp_price_history_item; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_price_history_item ON public.rnp_price_history USING btree (item_id);


--
-- Name: idx_rnp_templates_manager; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_rnp_templates_manager ON public.rnp_templates USING btree (manager_id);


--
-- Name: idx_sales_analytics_cover; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_analytics_cover ON public.sales USING btree (sale_date, marketplace_id) INCLUDE (product_id, revenue, net_profit, quantity, commission, logistics_cost);


--
-- Name: idx_sales_country; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_country ON public.sales USING btree (country);


--
-- Name: idx_sales_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_date ON public.sales USING btree (sale_date);


--
-- Name: idx_sales_marketplace; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_marketplace ON public.sales USING btree (marketplace_id);


--
-- Name: idx_sales_positive_qty; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_positive_qty ON public.sales USING btree (sale_date, product_id) WHERE (quantity > 0);


--
-- Name: idx_sales_product; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_product ON public.sales USING btree (product_id);


--
-- Name: idx_sales_product_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_product_date ON public.sales USING btree (product_id, sale_date);


--
-- Name: idx_sales_region; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_region ON public.sales USING btree (region);


--
-- Name: idx_sales_rrd_id; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_sales_rrd_id ON public.sales USING btree (rrd_id) WHERE (rrd_id IS NOT NULL);


--
-- Name: idx_sales_sale_id_mp_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_sales_sale_id_mp_date ON public.sales USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: idx_sales_warehouse; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sales_warehouse ON public.sales USING btree (warehouse);


--
-- Name: idx_stocks_credential; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_stocks_credential ON public.stocks USING btree (credential_id);


--
-- Name: idx_stocks_sku; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_stocks_sku ON public.stocks USING btree (sku);


--
-- Name: idx_sync_history_marketplace; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sync_history_marketplace ON public.sync_history USING btree (marketplace);


--
-- Name: idx_sync_history_started_at; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sync_history_started_at ON public.sync_history USING btree (started_at DESC);


--
-- Name: idx_sync_jobs_credential; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sync_jobs_credential ON public.sync_jobs USING btree (credential_id);


--
-- Name: idx_sync_jobs_status; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_sync_jobs_status ON public.sync_jobs USING btree (status);


--
-- Name: idx_unified_cred; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_unified_cred ON public.unified_sales USING btree (credential_id);


--
-- Name: idx_unified_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_unified_date ON public.unified_sales USING btree (sale_date);


--
-- Name: idx_unified_mp; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_unified_mp ON public.unified_sales USING btree (marketplace_id);


--
-- Name: idx_unified_product; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_unified_product ON public.unified_sales USING btree (product_id);


--
-- Name: idx_unified_type; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_unified_type ON public.unified_sales USING btree (operation_type);


--
-- Name: idx_user_marketplaces_marketplace; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_user_marketplaces_marketplace ON public.user_marketplaces USING btree (marketplace_id);


--
-- Name: idx_user_marketplaces_user; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_user_marketplaces_user ON public.user_marketplaces USING btree (user_id);


--
-- Name: idx_users_deleted_at; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_users_deleted_at ON public.users USING btree (deleted_at) WHERE (deleted_at IS NULL);


--
-- Name: idx_wb_sales_country; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_wb_sales_country ON public.wb_sales USING btree (country_name);


--
-- Name: idx_wb_sales_credential; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_wb_sales_credential ON public.wb_sales USING btree (credential_id);


--
-- Name: idx_wb_sales_doc_type; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_wb_sales_doc_type ON public.wb_sales USING btree (doc_type_name);


--
-- Name: idx_wb_sales_nm_id; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_wb_sales_nm_id ON public.wb_sales USING btree (nm_id);


--
-- Name: idx_wb_sales_region; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_wb_sales_region ON public.wb_sales USING btree (oblast_okrug_name);


--
-- Name: idx_wb_sales_rrd_id; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_wb_sales_rrd_id ON public.wb_sales USING btree (rrd_id) WHERE (rrd_id IS NOT NULL);


--
-- Name: idx_wb_sales_sale_dt; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_wb_sales_sale_dt ON public.wb_sales USING btree (sale_dt);


--
-- Name: idx_wb_sales_srid; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_wb_sales_srid ON public.wb_sales USING btree (srid);


--
-- Name: idx_wb_sales_srid_sale_dt; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_wb_sales_srid_sale_dt ON public.wb_sales USING btree (srid, sale_dt) WHERE (srid IS NOT NULL);


--
-- Name: idx_ym_sales_cred; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_ym_sales_cred ON public.ym_sales USING btree (credential_id);


--
-- Name: idx_ym_sales_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_ym_sales_date ON public.ym_sales USING btree (order_date);


--
-- Name: idx_ym_sales_sku; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX idx_ym_sales_sku ON public.ym_sales USING btree (market_sku);


--
-- Name: idx_ym_sales_uniq; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX idx_ym_sales_uniq ON public.ym_sales USING btree (order_id, order_item_id) WHERE (order_id IS NOT NULL);


--
-- Name: mv_avg_daily_sales_uniq; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX mv_avg_daily_sales_uniq ON public.mv_avg_daily_sales USING btree (product_id);


--
-- Name: mv_daily_sales_date; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX mv_daily_sales_date ON public.mv_daily_sales USING btree (sale_date);


--
-- Name: mv_daily_sales_product; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE INDEX mv_daily_sales_product ON public.mv_daily_sales USING btree (product_id);


--
-- Name: mv_daily_sales_uniq; Type: INDEX; Schema: public; Owner: sportdata_admin
--

CREATE UNIQUE INDEX mv_daily_sales_uniq ON public.mv_daily_sales USING btree (sale_date, product_id, marketplace_id);


--
-- Name: rnp_items trg_rnp_attention; Type: TRIGGER; Schema: public; Owner: sportdata_admin
--

CREATE TRIGGER trg_rnp_attention BEFORE INSERT OR UPDATE ON public.rnp_items FOR EACH ROW EXECUTE FUNCTION public.update_rnp_attention();


--
-- Name: rnp_items trg_rnp_reviews_ok; Type: TRIGGER; Schema: public; Owner: sportdata_admin
--

CREATE TRIGGER trg_rnp_reviews_ok BEFORE INSERT OR UPDATE OF review_1_stars, review_2_stars, review_3_stars ON public.rnp_items FOR EACH ROW EXECUTE FUNCTION public.update_rnp_reviews_ok();


--
-- Name: audit_log audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: categories categories_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: categories categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id);


--
-- Name: import_logs import_logs_imported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.import_logs
    ADD CONSTRAINT import_logs_imported_by_fkey FOREIGN KEY (imported_by) REFERENCES public.users(id);


--
-- Name: inventory inventory_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: inventory inventory_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: invites invites_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.invites
    ADD CONSTRAINT invites_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: marketplace_credentials marketplace_credentials_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.marketplace_credentials
    ADD CONSTRAINT marketplace_credentials_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: marketplace_credentials marketplace_credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.marketplace_credentials
    ADD CONSTRAINT marketplace_credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: orders orders_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: orders orders_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: ozon_sales ozon_sales_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.ozon_sales
    ADD CONSTRAINT ozon_sales_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.marketplace_credentials(id);


--
-- Name: pickup_points pickup_points_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.pickup_points
    ADD CONSTRAINT pickup_points_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: product_mappings product_mappings_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: product_mappings product_mappings_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: project_members project_members_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: project_members project_members_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: project_members project_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.project_members
    ADD CONSTRAINT project_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: projects projects_director_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_director_id_fkey FOREIGN KEY (director_id) REFERENCES public.users(id);


--
-- Name: returns returns_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: returns returns_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: returns returns_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: rnp_checklist_items rnp_checklist_items_done_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_items
    ADD CONSTRAINT rnp_checklist_items_done_by_fkey FOREIGN KEY (done_by) REFERENCES public.users(id);


--
-- Name: rnp_checklist_items rnp_checklist_items_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_items
    ADD CONSTRAINT rnp_checklist_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.rnp_items(id) ON DELETE CASCADE;


--
-- Name: rnp_checklist_items rnp_checklist_items_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_checklist_items
    ADD CONSTRAINT rnp_checklist_items_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.rnp_checklist_templates(id);


--
-- Name: rnp_daily_facts rnp_daily_facts_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily_facts
    ADD CONSTRAINT rnp_daily_facts_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.rnp_items(id) ON DELETE CASCADE;


--
-- Name: rnp_daily rnp_daily_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_daily
    ADD CONSTRAINT rnp_daily_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.rnp_items(id) ON DELETE CASCADE;


--
-- Name: rnp_items_daily rnp_items_daily_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items_daily
    ADD CONSTRAINT rnp_items_daily_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.rnp_items(id) ON DELETE CASCADE;


--
-- Name: rnp_items rnp_items_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items
    ADD CONSTRAINT rnp_items_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.users(id);


--
-- Name: rnp_items rnp_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items
    ADD CONSTRAINT rnp_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: rnp_items rnp_items_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_items
    ADD CONSTRAINT rnp_items_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.rnp_templates(id) ON DELETE CASCADE;


--
-- Name: rnp rnp_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp
    ADD CONSTRAINT rnp_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: rnp_price_history rnp_price_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_price_history
    ADD CONSTRAINT rnp_price_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.users(id);


--
-- Name: rnp_price_history rnp_price_history_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_price_history
    ADD CONSTRAINT rnp_price_history_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.rnp_items(id) ON DELETE CASCADE;


--
-- Name: rnp_templates rnp_templates_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_templates
    ADD CONSTRAINT rnp_templates_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.users(id);


--
-- Name: rnp_templates rnp_templates_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_templates
    ADD CONSTRAINT rnp_templates_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: rnp_templates rnp_templates_project_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.rnp_templates
    ADD CONSTRAINT rnp_templates_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: sales sales_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: sales sales_pickup_point_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_pickup_point_id_fkey FOREIGN KEY (pickup_point_id) REFERENCES public.pickup_points(id);


--
-- Name: sales sales_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: staging_sales_update staging_sales_update_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.staging_sales_update
    ADD CONSTRAINT staging_sales_update_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: staging_sales_update staging_sales_update_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.staging_sales_update
    ADD CONSTRAINT staging_sales_update_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: stocks stocks_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.marketplace_credentials(id);


--
-- Name: sync_history sync_history_triggered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sync_history
    ADD CONSTRAINT sync_history_triggered_by_fkey FOREIGN KEY (triggered_by) REFERENCES public.users(id);


--
-- Name: sync_jobs sync_jobs_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sync_jobs
    ADD CONSTRAINT sync_jobs_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.marketplace_credentials(id);


--
-- Name: sync_jobs sync_jobs_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.sync_jobs
    ADD CONSTRAINT sync_jobs_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: unified_sales unified_sales_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.unified_sales
    ADD CONSTRAINT unified_sales_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.marketplace_credentials(id);


--
-- Name: unified_sales unified_sales_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.unified_sales
    ADD CONSTRAINT unified_sales_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: unified_sales unified_sales_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.unified_sales
    ADD CONSTRAINT unified_sales_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: user_departments user_departments_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.user_departments
    ADD CONSTRAINT user_departments_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE CASCADE;


--
-- Name: user_departments user_departments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.user_departments
    ADD CONSTRAINT user_departments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_marketplaces user_marketplaces_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.user_marketplaces
    ADD CONSTRAINT user_marketplaces_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id) ON DELETE CASCADE;


--
-- Name: user_marketplaces user_marketplaces_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.user_marketplaces
    ADD CONSTRAINT user_marketplaces_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- Name: ym_sales ym_sales_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: sportdata_admin
--

ALTER TABLE ONLY public.ym_sales
    ADD CONSTRAINT ym_sales_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.marketplace_credentials(id);


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.audit_log TO sportdata;


--
-- Name: SEQUENCE audit_log_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.audit_log_id_seq TO sportdata;


--
-- Name: TABLE categories; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.categories TO sportdata;


--
-- Name: SEQUENCE categories_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.categories_id_seq TO sportdata;


--
-- Name: TABLE departments; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.departments TO sportdata;


--
-- Name: SEQUENCE departments_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.departments_id_seq TO sportdata;


--
-- Name: TABLE import_logs; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.import_logs TO sportdata;


--
-- Name: SEQUENCE import_logs_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.import_logs_id_seq TO sportdata;


--
-- Name: TABLE inventory; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.inventory TO sportdata;


--
-- Name: SEQUENCE inventory_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.inventory_id_seq TO sportdata;


--
-- Name: TABLE invites; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.invites TO sportdata;


--
-- Name: SEQUENCE invites_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.invites_id_seq TO sportdata;


--
-- Name: TABLE marketplace_credentials; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.marketplace_credentials TO sportdata;


--
-- Name: SEQUENCE marketplace_credentials_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.marketplace_credentials_id_seq TO sportdata;


--
-- Name: TABLE marketplaces; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.marketplaces TO sportdata;


--
-- Name: SEQUENCE marketplaces_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.marketplaces_id_seq TO sportdata;


--
-- Name: TABLE sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.sales TO sportdata;


--
-- Name: TABLE mv_avg_daily_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.mv_avg_daily_sales TO sportdata;


--
-- Name: TABLE products; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.products TO sportdata;


--
-- Name: TABLE mv_daily_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.mv_daily_sales TO sportdata;


--
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.orders TO sportdata;


--
-- Name: SEQUENCE orders_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.orders_id_seq TO sportdata;


--
-- Name: TABLE ozon_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.ozon_sales TO sportdata;


--
-- Name: SEQUENCE ozon_sales_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.ozon_sales_id_seq TO sportdata;


--
-- Name: TABLE pickup_points; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.pickup_points TO sportdata;


--
-- Name: SEQUENCE pickup_points_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.pickup_points_id_seq TO sportdata;


--
-- Name: TABLE product_current_prices; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.product_current_prices TO sportdata;


--
-- Name: TABLE product_mappings; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.product_mappings TO sportdata;


--
-- Name: SEQUENCE product_mappings_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.product_mappings_id_seq TO sportdata;


--
-- Name: TABLE product_margin_analysis; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.product_margin_analysis TO sportdata;


--
-- Name: SEQUENCE products_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.products_id_seq TO sportdata;


--
-- Name: TABLE project_members; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.project_members TO sportdata;


--
-- Name: SEQUENCE project_members_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.project_members_id_seq TO sportdata;


--
-- Name: TABLE projects; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.projects TO sportdata;


--
-- Name: SEQUENCE projects_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.projects_id_seq TO sportdata;


--
-- Name: TABLE returns; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.returns TO sportdata;


--
-- Name: SEQUENCE returns_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.returns_id_seq TO sportdata;


--
-- Name: TABLE rnp; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp TO sportdata;


--
-- Name: TABLE rnp_categories; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_categories TO sportdata;


--
-- Name: SEQUENCE rnp_categories_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_categories_id_seq TO sportdata;


--
-- Name: TABLE rnp_checklist_items; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_checklist_items TO sportdata;


--
-- Name: SEQUENCE rnp_checklist_items_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_checklist_items_id_seq TO sportdata;


--
-- Name: TABLE rnp_checklist_templates; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_checklist_templates TO sportdata;


--
-- Name: SEQUENCE rnp_checklist_templates_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_checklist_templates_id_seq TO sportdata;


--
-- Name: TABLE rnp_daily; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_daily TO sportdata;


--
-- Name: TABLE rnp_daily_facts; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_daily_facts TO sportdata;


--
-- Name: SEQUENCE rnp_daily_facts_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_daily_facts_id_seq TO sportdata;


--
-- Name: SEQUENCE rnp_daily_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_daily_id_seq TO sportdata;


--
-- Name: SEQUENCE rnp_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_id_seq TO sportdata;


--
-- Name: TABLE rnp_items; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_items TO sportdata;


--
-- Name: TABLE rnp_items_daily; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_items_daily TO sportdata;


--
-- Name: SEQUENCE rnp_items_daily_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_items_daily_id_seq TO sportdata;


--
-- Name: SEQUENCE rnp_items_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_items_id_seq TO sportdata;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.users TO sportdata;


--
-- Name: TABLE rnp_items_summary; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_items_summary TO sportdata;


--
-- Name: TABLE rnp_price_history; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_price_history TO sportdata;


--
-- Name: SEQUENCE rnp_price_history_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_price_history_id_seq TO sportdata;


--
-- Name: TABLE rnp_templates; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.rnp_templates TO sportdata;


--
-- Name: SEQUENCE rnp_templates_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.rnp_templates_id_seq TO sportdata;


--
-- Name: TABLE roles; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.roles TO sportdata;


--
-- Name: SEQUENCE roles_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.roles_id_seq TO sportdata;


--
-- Name: SEQUENCE sales_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.sales_id_seq TO sportdata;


--
-- Name: TABLE schema_migrations; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.schema_migrations TO sportdata;


--
-- Name: TABLE staging_sales_update; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.staging_sales_update TO sportdata;


--
-- Name: SEQUENCE staging_sales_update_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.staging_sales_update_id_seq TO sportdata;


--
-- Name: TABLE stocks; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.stocks TO sportdata;


--
-- Name: SEQUENCE stocks_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.stocks_id_seq TO sportdata;


--
-- Name: TABLE sync_history; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.sync_history TO sportdata;


--
-- Name: TABLE sync_jobs; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.sync_jobs TO sportdata;


--
-- Name: SEQUENCE sync_jobs_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.sync_jobs_id_seq TO sportdata;


--
-- Name: TABLE trending_products; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.trending_products TO sportdata;


--
-- Name: TABLE unified_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.unified_sales TO sportdata;


--
-- Name: SEQUENCE unified_sales_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.unified_sales_id_seq TO sportdata;


--
-- Name: TABLE user_departments; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.user_departments TO sportdata;


--
-- Name: TABLE user_marketplaces; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.user_marketplaces TO sportdata;


--
-- Name: TABLE v_current_inventory; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.v_current_inventory TO sportdata;


--
-- Name: TABLE v_daily_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.v_daily_sales TO sportdata;


--
-- Name: TABLE v_product_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.v_product_sales TO sportdata;


--
-- Name: TABLE v_rnp_monthly; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.v_rnp_monthly TO sportdata;


--
-- Name: TABLE v_rnp_summary; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.v_rnp_summary TO sportdata;


--
-- Name: TABLE v_sales_summary; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.v_sales_summary TO sportdata;


--
-- Name: TABLE wb_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.wb_sales TO sportdata;


--
-- Name: SEQUENCE wb_sales_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.wb_sales_id_seq TO sportdata;


--
-- Name: TABLE ym_sales; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON TABLE public.ym_sales TO sportdata;


--
-- Name: SEQUENCE ym_sales_id_seq; Type: ACL; Schema: public; Owner: sportdata_admin
--

GRANT ALL ON SEQUENCE public.ym_sales_id_seq TO sportdata;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: sportdata_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE sportdata_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO sportdata;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: sportdata_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE sportdata_admin IN SCHEMA public GRANT ALL ON TABLES TO sportdata;


--
-- PostgreSQL database dump complete
--

\unrestrict ClneSdFzUHTggcFMnSt0CKdifPGRoO9bIMJ8O9H7JBFuDcMvTft8FYYK8z3TMxl

