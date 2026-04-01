--
-- PostgreSQL database dump
--

\restrict ebBjs7nHSbG3AGpl6GbXcIQH9oyeueoXNQmGdzuogJkln8oxZW1NcW7hO5eKGJM

-- Dumped from database version 16.13 (Homebrew)
-- Dumped by pg_dump version 16.13 (Homebrew)

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
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: create_sales_partition(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_sales_partition(p_date date) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    start_date date;
    end_date date;
    partition_name text;
BEGIN
    start_date := date_trunc('month', p_date);
    end_date := start_date + interval '1 month';
    partition_name := 'sales_' || to_char(start_date, 'YYYY_MM');

    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS %I PARTITION OF sales
         FOR VALUES FROM (%L) TO (%L)',
        partition_name,
        start_date,
        end_date
    );
END;
$$;


--
-- Name: generate_product_alerts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_product_alerts() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

-- trending
INSERT INTO product_alerts (product_id, alert_type, alert_message)
SELECT
product_id,
'TRENDING',
'Product sales growing fast'
FROM trending_products
WHERE prev_sales_7d > 0
AND sales_7d > prev_sales_7d * 2;

-- high revenue
INSERT INTO product_alerts (product_id, alert_type, alert_message)
SELECT
product_id,
'HIGH_REVENUE',
'Product generating high revenue'
FROM product_competition
WHERE revenue_30d > 100000;

-- low competition
INSERT INTO product_alerts (product_id, alert_type, alert_message)
SELECT
product_id,
'LOW_COMPETITION',
'Product has sales with low competition'
FROM product_competition
WHERE revenue_30d > 50000
AND competition_score < 50000;

END;
$$;


--
-- Name: refresh_analytics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_analytics() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

REFRESH MATERIALIZED VIEW trending_products;
REFRESH MATERIALIZED VIEW product_competition;
REFRESH MATERIALIZED VIEW goldmine_products;

END;
$$;


--
-- Name: refresh_category_metrics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_category_metrics() RETURNS void
    LANGUAGE sql
    AS $$
INSERT INTO category_market_metrics
SELECT
    f.sale_date,
    p.category_id,
    SUM(f.total_revenue),
    SUM(f.total_qty),
    COUNT(DISTINCT f.product_id)
FROM daily_sales_fact f
JOIN products p
ON p.id = f.product_id
WHERE p.category_id IS NOT NULL
GROUP BY 1,2
ON CONFLICT (sale_date, category_id)
DO UPDATE SET
    total_revenue = EXCLUDED.total_revenue,
    total_units = EXCLUDED.total_units,
    product_count = EXCLUDED.product_count;
$$;


--
-- Name: refresh_incremental(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_incremental() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    last_date date;
BEGIN

SELECT last_processed_date
INTO last_date
FROM analytics_state
WHERE key = 'daily_sales_fact';

INSERT INTO daily_sales_fact
SELECT
    sale_date,
    marketplace_id,
    product_id,
    SUM(quantity) as total_qty,
    SUM(revenue) as total_revenue,
    SUM(net_profit) as total_profit
FROM sales
WHERE sale_date > last_date
GROUP BY 1,2,3
ON CONFLICT (sale_date, marketplace_id, product_id)
DO UPDATE SET
    total_qty = EXCLUDED.total_qty,
    total_revenue = EXCLUDED.total_revenue,
    total_profit = EXCLUDED.total_profit;

UPDATE analytics_state
SET last_processed_date = CURRENT_DATE
WHERE key = 'daily_sales_fact';

PERFORM refresh_analytics();

END;
$$;


--
-- Name: run_daily_market_analytics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.run_daily_market_analytics() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN

PERFORM refresh_analytics();

REFRESH MATERIALIZED VIEW trending_products;
REFRESH MATERIALIZED VIEW product_competition;
REFRESH MATERIALIZED VIEW goldmine_products;

PERFORM generate_product_alerts();

END;
$$;


--
-- Name: sales_force_date(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sales_force_date() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.sale_date IS NULL THEN
    NEW.sale_date := CURRENT_DATE;
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: analytics_meta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analytics_meta (
    key text NOT NULL,
    value timestamp with time zone
);


--
-- Name: analytics_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analytics_state (
    key text NOT NULL,
    last_processed_date date
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;


--
-- Name: category_market_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.category_market_metrics (
    sale_date date NOT NULL,
    category_id integer NOT NULL,
    total_revenue numeric,
    total_units integer,
    product_count integer
);


--
-- Name: category_opportunities; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.category_opportunities AS
 SELECT c.id AS category_id,
    c.name,
    sum(m.total_revenue) AS revenue_30d,
    sum(m.total_units) AS units_30d,
    avg(m.product_count) AS avg_products,
    (sum(m.total_revenue) / sqrt(NULLIF(avg(m.product_count), (0)::numeric))) AS opportunity_score
   FROM (public.category_market_metrics m
     JOIN public.categories c ON ((c.id = m.category_id)))
  WHERE (m.sale_date >= (CURRENT_DATE - '30 days'::interval))
  GROUP BY c.id, c.name
 HAVING ((sum(m.total_revenue) > (10000)::numeric) AND (avg(m.product_count) >= (5)::numeric))
  WITH NO DATA;


--
-- Name: daily_sales_fact; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_sales_fact (
    sale_date date NOT NULL,
    product_id integer NOT NULL,
    marketplace_id integer NOT NULL,
    total_qty integer,
    total_revenue numeric(14,2),
    total_commission numeric(14,2),
    total_logistics numeric(14,2),
    total_profit numeric(14,2)
);


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id integer NOT NULL,
    slug character varying(50) NOT NULL,
    name character varying(200) NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: departments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departments_id_seq OWNED BY public.departments.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
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
    nm_id bigint,
    width numeric(8,2) DEFAULT 0,
    height numeric(8,2) DEFAULT 0,
    length numeric(8,2) DEFAULT 0,
    image_url text,
    retail_price numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0
);


--
-- Name: product_competition; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.product_competition AS
 SELECT p.id AS product_id,
    p.name,
    p.category_id,
    sum(f.total_revenue) AS revenue_30d,
    sum(f.total_qty) AS units_30d,
    count(DISTINCT f.sale_date) AS active_days,
    (sum(f.total_revenue) / (NULLIF(sum(f.total_qty), 0))::numeric) AS avg_price,
    (((sum(f.total_revenue) * 0.6) + ((sum(f.total_qty))::numeric * 0.3)) + ((count(DISTINCT f.sale_date))::numeric * 0.1)) AS competition_score
   FROM (public.daily_sales_fact f
     JOIN public.products p ON ((p.id = f.product_id)))
  WHERE (f.sale_date >= (CURRENT_DATE - '30 days'::interval))
  GROUP BY p.id, p.name, p.category_id
  WITH NO DATA;


--
-- Name: product_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_metrics (
    product_id integer NOT NULL,
    revenue_7d numeric(14,2),
    revenue_30d numeric(14,2),
    profit_30d numeric(14,2),
    units_30d integer,
    margin_30d numeric(6,2),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: goldmine_products; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.goldmine_products AS
 SELECT p.id AS product_id,
    p.name,
    p.category_id,
    m.revenue_30d,
    m.units_30d,
    m.margin_30d,
    c.competition_score,
    ((m.revenue_30d * m.margin_30d) / ln((c.competition_score + (10)::numeric))) AS goldmine_score
   FROM ((public.product_metrics m
     JOIN public.product_competition c ON ((c.product_id = m.product_id)))
     JOIN public.products p ON ((p.id = m.product_id)))
  WHERE ((m.revenue_30d > (10000)::numeric) AND (m.margin_30d > (50)::numeric))
  ORDER BY ((m.revenue_30d * m.margin_30d) / ln((c.competition_score + (10)::numeric))) DESC
  WITH NO DATA;


--
-- Name: import_logs; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: import_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_logs_id_seq OWNED BY public.import_logs.id;


--
-- Name: inventory; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_id_seq OWNED BY public.inventory.id;


--
-- Name: leaderboard_top_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leaderboard_top_products (
    rank integer NOT NULL,
    product_id integer,
    revenue_30d numeric(14,2),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: market_insights; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.market_insights (
    sale_date date NOT NULL,
    marketplace_id integer NOT NULL,
    product_id integer NOT NULL,
    market_revenue numeric(14,2),
    product_revenue numeric(14,2),
    market_units integer,
    product_units integer,
    revenue_share numeric(8,4),
    units_share numeric(8,4)
);


--
-- Name: marketplace_credentials; Type: TABLE; Schema: public; Owner: -
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
    api_key_hint character varying(20) DEFAULT ''::character varying
);


--
-- Name: marketplace_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.marketplace_credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: marketplace_credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.marketplace_credentials_id_seq OWNED BY public.marketplace_credentials.id;


--
-- Name: marketplaces; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.marketplaces (
    id integer NOT NULL,
    slug character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    api_base_url character varying(500),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: marketplaces_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.marketplaces_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: marketplaces_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.marketplaces_id_seq OWNED BY public.marketplaces.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: product_alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_alerts (
    id integer NOT NULL,
    product_id integer,
    alert_type text,
    alert_message text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: product_alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_alerts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_alerts_id_seq OWNED BY public.product_alerts.id;


--
-- Name: product_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_categories (
    product_id integer NOT NULL,
    category_id integer
);


--
-- Name: product_mappings; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: product_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_mappings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_mappings_id_seq OWNED BY public.product_mappings.id;


--
-- Name: product_trends; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_trends (
    product_id integer NOT NULL,
    revenue_today numeric(14,2),
    revenue_yesterday numeric(14,2),
    revenue_growth numeric(14,2),
    units_today integer,
    units_yesterday integer,
    units_growth integer,
    trend_score numeric(14,2),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: product_velocity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_velocity (
    product_id integer NOT NULL,
    sales_per_day numeric(10,2),
    revenue_per_day numeric(14,2),
    units_7d integer,
    revenue_7d numeric(14,2),
    velocity_score numeric(14,2),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: sales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales (
    id bigint NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
)
PARTITION BY RANGE (sale_date);


--
-- Name: profit_daily; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.profit_daily AS
 SELECT (date_trunc('day'::text, (sale_date)::timestamp with time zone))::date AS date,
    nm_id,
    brand,
    subject_name,
    count(*) FILTER (WHERE ((supplier_oper_name)::text = 'Продажа'::text)) AS orders,
    sum(quantity) FILTER (WHERE ((supplier_oper_name)::text = 'Продажа'::text)) AS items,
    sum(revenue) AS revenue,
    sum(for_pay) AS payout,
    sum(net_profit) AS profit,
    sum(commission) AS commission,
    sum(logistics_cost) AS logistics
   FROM public.sales
  GROUP BY ((date_trunc('day'::text, (sale_date)::timestamp with time zone))::date), nm_id, brand, subject_name
  WITH NO DATA;


--
-- Name: returns; Type: TABLE; Schema: public; Owner: -
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
    rrd_id bigint,
    return_amount numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    site_country character varying(50),
    office_name character varying(200),
    srid character varying(100),
    supplier_oper_name character varying(100)
);


--
-- Name: returns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.returns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: returns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.returns_id_seq OWNED BY public.returns.id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id integer NOT NULL,
    slug character varying(20) NOT NULL,
    name character varying(100) NOT NULL,
    level integer NOT NULL,
    is_hidden boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: sales_new_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sales_new_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sales_new_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sales_new_id_seq OWNED BY public.sales.id;


--
-- Name: sales_2023_01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_01 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_02 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_03 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_04 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_05 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_06 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_07 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_08 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_09; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_09 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_10; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_10 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_11; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_11 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2023_12; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2023_12 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_01 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_02 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_03 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_04 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_05 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_06 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_07 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_08 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_09; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_09 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_10; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_10 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_11; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_11 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2024_12; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2024_12 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_01 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_02 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_03 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_04 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_05 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_06 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_07 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_08 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_09; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_09 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_10; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_10 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_11; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_11 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2025_12; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2025_12 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_01 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_02 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_03 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_04 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_05 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_06 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_07 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_08 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_09; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_09 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_10; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_10 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_11; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_11 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2026_12; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2026_12 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_01; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_01 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_02; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_02 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_03; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_03 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_04 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_05 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_06 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_07 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_08 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_09; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_09 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_10; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_10 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_11; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_11 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_2027_12; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sales_2027_12 (
    id bigint DEFAULT nextval('public.sales_new_id_seq'::regclass) NOT NULL,
    product_id integer,
    marketplace_id integer,
    sale_date date DEFAULT now() NOT NULL,
    quantity integer DEFAULT 0,
    revenue numeric(14,2) DEFAULT 0,
    commission numeric(14,2) DEFAULT 0,
    logistics_cost numeric(14,2) DEFAULT 0,
    net_profit numeric(14,2) DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    for_pay numeric(12,2) DEFAULT 0,
    sale_id character varying(100),
    penalty numeric(12,2) DEFAULT 0,
    retail_price numeric(14,2) DEFAULT 0,
    retail_amount numeric(14,2) DEFAULT 0,
    discount_price numeric(14,2) DEFAULT 0,
    spp_percent numeric(6,2) DEFAULT 0,
    commission_percent numeric(6,2) DEFAULT 0,
    acquiring_fee numeric(14,2) DEFAULT 0,
    storage_fee numeric(14,2) DEFAULT 0,
    deduction numeric(14,2) DEFAULT 0,
    acceptance_cost numeric(14,2) DEFAULT 0,
    return_logistic_cost numeric(14,2) DEFAULT 0,
    additional_payment numeric(14,2) DEFAULT 0,
    supplier_oper_name character varying(100),
    site_country character varying(50),
    office_name character varying(200),
    ppvz_office_name character varying(200),
    srid character varying(100),
    rid bigint,
    report_id bigint,
    sticker_id bigint,
    kiz character varying(200),
    nm_id bigint,
    finished_price numeric,
    brand text,
    subject_name text,
    supplier_article text,
    barcode text,
    warehouse_name text,
    discount_percent numeric,
    spp numeric,
    tech_size text,
    oblast text,
    income_id bigint
);


--
-- Name: sales_stage; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.sales_stage (
    product_id bigint,
    marketplace_id integer,
    sale_date date,
    quantity integer,
    revenue numeric,
    for_pay numeric,
    net_profit numeric,
    commission numeric,
    logistics_cost numeric,
    sale_id text
);


--
-- Name: staging_sales_update; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staging_sales_update (
    product_id integer,
    sale_date date,
    logistics_cost numeric,
    commission numeric,
    penalty numeric,
    acquiring_fee numeric,
    storage_fee numeric,
    deduction numeric,
    acceptance_cost numeric,
    return_logistic_cost numeric,
    additional_payment numeric,
    spp_percent numeric,
    commission_percent numeric,
    retail_price numeric,
    discount_price numeric,
    site_country text,
    office_name text,
    ppvz_office_name text,
    report_id bigint
);


--
-- Name: sync_jobs; Type: TABLE; Schema: public; Owner: -
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
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: sync_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sync_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sync_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sync_jobs_id_seq OWNED BY public.sync_jobs.id;


--
-- Name: trending_products; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trending_products AS
 SELECT p.id AS product_id,
    p.name,
    p.category_id,
    count(*) FILTER (WHERE (s.sale_date >= (CURRENT_DATE - '7 days'::interval))) AS sales_7d,
    count(*) FILTER (WHERE ((s.sale_date >= (CURRENT_DATE - '14 days'::interval)) AND (s.sale_date < (CURRENT_DATE - '7 days'::interval)))) AS prev_sales_7d
   FROM (public.products p
     LEFT JOIN public.sales s ON ((s.product_id = p.id)))
  GROUP BY p.id, p.name, p.category_id;


--
-- Name: user_departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_departments (
    user_id uuid NOT NULL,
    department_id integer NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
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
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: v_current_inventory; Type: VIEW; Schema: public; Owner: -
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


--
-- Name: v_daily_sales_hist; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.v_daily_sales_hist AS
 SELECT s.sale_date,
    p.sku,
    p.name AS product_name,
    c.name AS category_name,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    sum(s.quantity) AS total_qty,
    sum(s.revenue) AS total_revenue,
    sum(s.commission) AS total_commission,
    sum(s.logistics_cost) AS total_logistics,
    sum(s.net_profit) AS total_profit
   FROM (((public.sales s
     JOIN public.products p ON ((p.id = s.product_id)))
     JOIN public.marketplaces m ON ((m.id = s.marketplace_id)))
     LEFT JOIN public.categories c ON ((c.id = p.category_id)))
  WHERE (s.sale_date < CURRENT_DATE)
  GROUP BY s.sale_date, p.sku, p.name, c.name, m.slug, m.name
  WITH NO DATA;


--
-- Name: v_daily_sales; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_daily_sales AS
 SELECT v_daily_sales_hist.sale_date,
    v_daily_sales_hist.sku,
    v_daily_sales_hist.product_name,
    v_daily_sales_hist.category_name,
    v_daily_sales_hist.marketplace,
    v_daily_sales_hist.marketplace_name,
    v_daily_sales_hist.total_qty,
    v_daily_sales_hist.total_revenue,
    v_daily_sales_hist.total_commission,
    v_daily_sales_hist.total_logistics,
    v_daily_sales_hist.total_profit
   FROM public.v_daily_sales_hist
UNION ALL
 SELECT s.sale_date,
    p.sku,
    p.name AS product_name,
    c.name AS category_name,
    m.slug AS marketplace,
    m.name AS marketplace_name,
    sum(s.quantity) AS total_qty,
    sum(s.revenue) AS total_revenue,
    sum(s.commission) AS total_commission,
    sum(s.logistics_cost) AS total_logistics,
    sum(s.net_profit) AS total_profit
   FROM (((public.sales s
     JOIN public.products p ON ((p.id = s.product_id)))
     JOIN public.marketplaces m ON ((m.id = s.marketplace_id)))
     LEFT JOIN public.categories c ON ((c.id = p.category_id)))
  WHERE (s.sale_date = CURRENT_DATE)
  GROUP BY s.sale_date, p.sku, p.name, c.name, m.slug, m.name;


--
-- Name: sales_2023_01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_01 FOR VALUES FROM ('2023-01-01') TO ('2023-02-01');


--
-- Name: sales_2023_02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_02 FOR VALUES FROM ('2023-02-01') TO ('2023-03-01');


--
-- Name: sales_2023_03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_03 FOR VALUES FROM ('2023-03-01') TO ('2023-04-01');


--
-- Name: sales_2023_04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_04 FOR VALUES FROM ('2023-04-01') TO ('2023-05-01');


--
-- Name: sales_2023_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_05 FOR VALUES FROM ('2023-05-01') TO ('2023-06-01');


--
-- Name: sales_2023_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_06 FOR VALUES FROM ('2023-06-01') TO ('2023-07-01');


--
-- Name: sales_2023_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_07 FOR VALUES FROM ('2023-07-01') TO ('2023-08-01');


--
-- Name: sales_2023_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_08 FOR VALUES FROM ('2023-08-01') TO ('2023-09-01');


--
-- Name: sales_2023_09; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_09 FOR VALUES FROM ('2023-09-01') TO ('2023-10-01');


--
-- Name: sales_2023_10; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_10 FOR VALUES FROM ('2023-10-01') TO ('2023-11-01');


--
-- Name: sales_2023_11; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_11 FOR VALUES FROM ('2023-11-01') TO ('2023-12-01');


--
-- Name: sales_2023_12; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2023_12 FOR VALUES FROM ('2023-12-01') TO ('2024-01-01');


--
-- Name: sales_2024_01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_01 FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');


--
-- Name: sales_2024_02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_02 FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');


--
-- Name: sales_2024_03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_03 FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');


--
-- Name: sales_2024_04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_04 FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');


--
-- Name: sales_2024_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_05 FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');


--
-- Name: sales_2024_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_06 FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');


--
-- Name: sales_2024_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_07 FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');


--
-- Name: sales_2024_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_08 FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');


--
-- Name: sales_2024_09; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_09 FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');


--
-- Name: sales_2024_10; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_10 FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');


--
-- Name: sales_2024_11; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_11 FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');


--
-- Name: sales_2024_12; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2024_12 FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');


--
-- Name: sales_2025_01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_01 FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');


--
-- Name: sales_2025_02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_02 FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');


--
-- Name: sales_2025_03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_03 FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');


--
-- Name: sales_2025_04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_04 FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');


--
-- Name: sales_2025_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_05 FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');


--
-- Name: sales_2025_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_06 FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');


--
-- Name: sales_2025_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_07 FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');


--
-- Name: sales_2025_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_08 FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');


--
-- Name: sales_2025_09; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_09 FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');


--
-- Name: sales_2025_10; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_10 FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');


--
-- Name: sales_2025_11; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_11 FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');


--
-- Name: sales_2025_12; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2025_12 FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');


--
-- Name: sales_2026_01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_01 FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');


--
-- Name: sales_2026_02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_02 FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');


--
-- Name: sales_2026_03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_03 FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');


--
-- Name: sales_2026_04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_04 FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');


--
-- Name: sales_2026_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_05 FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');


--
-- Name: sales_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_06 FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');


--
-- Name: sales_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_07 FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');


--
-- Name: sales_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_08 FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');


--
-- Name: sales_2026_09; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_09 FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');


--
-- Name: sales_2026_10; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_10 FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');


--
-- Name: sales_2026_11; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_11 FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');


--
-- Name: sales_2026_12; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2026_12 FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');


--
-- Name: sales_2027_01; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_01 FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');


--
-- Name: sales_2027_02; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_02 FOR VALUES FROM ('2027-02-01') TO ('2027-03-01');


--
-- Name: sales_2027_03; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_03 FOR VALUES FROM ('2027-03-01') TO ('2027-04-01');


--
-- Name: sales_2027_04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_04 FOR VALUES FROM ('2027-04-01') TO ('2027-05-01');


--
-- Name: sales_2027_05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_05 FOR VALUES FROM ('2027-05-01') TO ('2027-06-01');


--
-- Name: sales_2027_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_06 FOR VALUES FROM ('2027-06-01') TO ('2027-07-01');


--
-- Name: sales_2027_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_07 FOR VALUES FROM ('2027-07-01') TO ('2027-08-01');


--
-- Name: sales_2027_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_08 FOR VALUES FROM ('2027-08-01') TO ('2027-09-01');


--
-- Name: sales_2027_09; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_09 FOR VALUES FROM ('2027-09-01') TO ('2027-10-01');


--
-- Name: sales_2027_10; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_10 FOR VALUES FROM ('2027-10-01') TO ('2027-11-01');


--
-- Name: sales_2027_11; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_11 FOR VALUES FROM ('2027-11-01') TO ('2027-12-01');


--
-- Name: sales_2027_12; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ATTACH PARTITION public.sales_2027_12 FOR VALUES FROM ('2027-12-01') TO ('2028-01-01');


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);


--
-- Name: departments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments ALTER COLUMN id SET DEFAULT nextval('public.departments_id_seq'::regclass);


--
-- Name: import_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_logs ALTER COLUMN id SET DEFAULT nextval('public.import_logs_id_seq'::regclass);


--
-- Name: inventory id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory ALTER COLUMN id SET DEFAULT nextval('public.inventory_id_seq'::regclass);


--
-- Name: marketplace_credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_credentials ALTER COLUMN id SET DEFAULT nextval('public.marketplace_credentials_id_seq'::regclass);


--
-- Name: marketplaces id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplaces ALTER COLUMN id SET DEFAULT nextval('public.marketplaces_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: product_alerts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_alerts ALTER COLUMN id SET DEFAULT nextval('public.product_alerts_id_seq'::regclass);


--
-- Name: product_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_mappings ALTER COLUMN id SET DEFAULT nextval('public.product_mappings_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: returns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns ALTER COLUMN id SET DEFAULT nextval('public.returns_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: sales id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales ALTER COLUMN id SET DEFAULT nextval('public.sales_new_id_seq'::regclass);


--
-- Name: sync_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_jobs ALTER COLUMN id SET DEFAULT nextval('public.sync_jobs_id_seq'::regclass);


--
-- Name: analytics_meta analytics_meta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analytics_meta
    ADD CONSTRAINT analytics_meta_pkey PRIMARY KEY (key);


--
-- Name: analytics_state analytics_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analytics_state
    ADD CONSTRAINT analytics_state_pkey PRIMARY KEY (key);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories categories_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_slug_key UNIQUE (slug);


--
-- Name: category_market_metrics category_market_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category_market_metrics
    ADD CONSTRAINT category_market_metrics_pkey PRIMARY KEY (sale_date, category_id);


--
-- Name: daily_sales_fact daily_sales_fact_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_sales_fact
    ADD CONSTRAINT daily_sales_fact_pkey PRIMARY KEY (sale_date, product_id, marketplace_id);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: departments departments_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_slug_key UNIQUE (slug);


--
-- Name: import_logs import_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_logs
    ADD CONSTRAINT import_logs_pkey PRIMARY KEY (id);


--
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (id);


--
-- Name: leaderboard_top_products leaderboard_top_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leaderboard_top_products
    ADD CONSTRAINT leaderboard_top_products_pkey PRIMARY KEY (rank);


--
-- Name: market_insights market_insights_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.market_insights
    ADD CONSTRAINT market_insights_pkey PRIMARY KEY (sale_date, marketplace_id, product_id);


--
-- Name: marketplace_credentials marketplace_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_credentials
    ADD CONSTRAINT marketplace_credentials_pkey PRIMARY KEY (id);


--
-- Name: marketplaces marketplaces_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplaces
    ADD CONSTRAINT marketplaces_pkey PRIMARY KEY (id);


--
-- Name: marketplaces marketplaces_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplaces
    ADD CONSTRAINT marketplaces_slug_key UNIQUE (slug);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: product_alerts product_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_alerts
    ADD CONSTRAINT product_alerts_pkey PRIMARY KEY (id);


--
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (product_id);


--
-- Name: product_mappings product_mappings_marketplace_id_external_sku_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_marketplace_id_external_sku_key UNIQUE (marketplace_id, external_sku);


--
-- Name: product_mappings product_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_pkey PRIMARY KEY (id);


--
-- Name: product_metrics product_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_metrics
    ADD CONSTRAINT product_metrics_pkey PRIMARY KEY (product_id);


--
-- Name: product_trends product_trends_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_trends
    ADD CONSTRAINT product_trends_pkey PRIMARY KEY (product_id);


--
-- Name: product_velocity product_velocity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_velocity
    ADD CONSTRAINT product_velocity_pkey PRIMARY KEY (product_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: products products_sku_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_sku_key UNIQUE (sku);


--
-- Name: returns returns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: roles roles_slug_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_slug_key UNIQUE (slug);


--
-- Name: sales sales_new_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales
    ADD CONSTRAINT sales_new_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_01 sales_2023_01_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_01
    ADD CONSTRAINT sales_2023_01_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_02 sales_2023_02_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_02
    ADD CONSTRAINT sales_2023_02_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_03 sales_2023_03_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_03
    ADD CONSTRAINT sales_2023_03_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_04 sales_2023_04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_04
    ADD CONSTRAINT sales_2023_04_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_05 sales_2023_05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_05
    ADD CONSTRAINT sales_2023_05_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_06 sales_2023_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_06
    ADD CONSTRAINT sales_2023_06_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_07 sales_2023_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_07
    ADD CONSTRAINT sales_2023_07_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_08 sales_2023_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_08
    ADD CONSTRAINT sales_2023_08_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_09 sales_2023_09_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_09
    ADD CONSTRAINT sales_2023_09_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_10 sales_2023_10_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_10
    ADD CONSTRAINT sales_2023_10_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_11 sales_2023_11_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_11
    ADD CONSTRAINT sales_2023_11_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2023_12 sales_2023_12_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2023_12
    ADD CONSTRAINT sales_2023_12_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_01 sales_2024_01_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_01
    ADD CONSTRAINT sales_2024_01_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_02 sales_2024_02_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_02
    ADD CONSTRAINT sales_2024_02_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_03 sales_2024_03_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_03
    ADD CONSTRAINT sales_2024_03_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_04 sales_2024_04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_04
    ADD CONSTRAINT sales_2024_04_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_05 sales_2024_05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_05
    ADD CONSTRAINT sales_2024_05_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_06 sales_2024_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_06
    ADD CONSTRAINT sales_2024_06_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_07 sales_2024_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_07
    ADD CONSTRAINT sales_2024_07_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_08 sales_2024_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_08
    ADD CONSTRAINT sales_2024_08_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_09 sales_2024_09_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_09
    ADD CONSTRAINT sales_2024_09_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_10 sales_2024_10_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_10
    ADD CONSTRAINT sales_2024_10_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_11 sales_2024_11_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_11
    ADD CONSTRAINT sales_2024_11_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2024_12 sales_2024_12_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2024_12
    ADD CONSTRAINT sales_2024_12_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_01 sales_2025_01_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_01
    ADD CONSTRAINT sales_2025_01_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_02 sales_2025_02_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_02
    ADD CONSTRAINT sales_2025_02_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_03 sales_2025_03_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_03
    ADD CONSTRAINT sales_2025_03_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_04 sales_2025_04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_04
    ADD CONSTRAINT sales_2025_04_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_05 sales_2025_05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_05
    ADD CONSTRAINT sales_2025_05_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_06 sales_2025_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_06
    ADD CONSTRAINT sales_2025_06_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_07 sales_2025_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_07
    ADD CONSTRAINT sales_2025_07_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_08 sales_2025_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_08
    ADD CONSTRAINT sales_2025_08_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_09 sales_2025_09_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_09
    ADD CONSTRAINT sales_2025_09_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_10 sales_2025_10_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_10
    ADD CONSTRAINT sales_2025_10_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_11 sales_2025_11_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_11
    ADD CONSTRAINT sales_2025_11_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2025_12 sales_2025_12_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2025_12
    ADD CONSTRAINT sales_2025_12_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_01 sales_2026_01_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_01
    ADD CONSTRAINT sales_2026_01_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_02 sales_2026_02_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_02
    ADD CONSTRAINT sales_2026_02_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_03 sales_2026_03_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_03
    ADD CONSTRAINT sales_2026_03_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_04 sales_2026_04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_04
    ADD CONSTRAINT sales_2026_04_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_05 sales_2026_05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_05
    ADD CONSTRAINT sales_2026_05_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_06 sales_2026_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_06
    ADD CONSTRAINT sales_2026_06_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_07 sales_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_07
    ADD CONSTRAINT sales_2026_07_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_08 sales_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_08
    ADD CONSTRAINT sales_2026_08_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_09 sales_2026_09_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_09
    ADD CONSTRAINT sales_2026_09_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_10 sales_2026_10_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_10
    ADD CONSTRAINT sales_2026_10_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_11 sales_2026_11_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_11
    ADD CONSTRAINT sales_2026_11_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2026_12 sales_2026_12_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2026_12
    ADD CONSTRAINT sales_2026_12_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_01 sales_2027_01_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_01
    ADD CONSTRAINT sales_2027_01_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_02 sales_2027_02_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_02
    ADD CONSTRAINT sales_2027_02_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_03 sales_2027_03_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_03
    ADD CONSTRAINT sales_2027_03_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_04 sales_2027_04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_04
    ADD CONSTRAINT sales_2027_04_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_05 sales_2027_05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_05
    ADD CONSTRAINT sales_2027_05_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_06 sales_2027_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_06
    ADD CONSTRAINT sales_2027_06_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_07 sales_2027_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_07
    ADD CONSTRAINT sales_2027_07_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_08 sales_2027_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_08
    ADD CONSTRAINT sales_2027_08_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_09 sales_2027_09_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_09
    ADD CONSTRAINT sales_2027_09_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_10 sales_2027_10_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_10
    ADD CONSTRAINT sales_2027_10_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_11 sales_2027_11_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_11
    ADD CONSTRAINT sales_2027_11_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sales_2027_12 sales_2027_12_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sales_2027_12
    ADD CONSTRAINT sales_2027_12_pkey PRIMARY KEY (sale_date, id);


--
-- Name: sync_jobs sync_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_jobs
    ADD CONSTRAINT sync_jobs_pkey PRIMARY KEY (id);


--
-- Name: user_departments user_departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_departments
    ADD CONSTRAINT user_departments_pkey PRIMARY KEY (user_id, department_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_audit_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_created ON public.audit_log USING btree (created_at);


--
-- Name: idx_audit_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_user ON public.audit_log USING btree (user_id);


--
-- Name: idx_category_market_metrics_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_category_market_metrics_category ON public.category_market_metrics USING btree (category_id, sale_date DESC);


--
-- Name: idx_category_opportunity_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_category_opportunity_score ON public.category_opportunities USING btree (opportunity_score DESC);


--
-- Name: idx_daily_sales_fact_product_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_sales_fact_product_date ON public.daily_sales_fact USING btree (product_id, sale_date DESC) INCLUDE (total_qty, total_revenue, total_profit);


--
-- Name: idx_daily_sales_marketplace; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_sales_marketplace ON public.daily_sales_fact USING btree (marketplace_id, sale_date);


--
-- Name: idx_daily_sales_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_sales_product ON public.daily_sales_fact USING btree (product_id, sale_date);


--
-- Name: idx_daily_sales_top_profit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_sales_top_profit ON public.daily_sales_fact USING btree (sale_date DESC, total_profit DESC);


--
-- Name: idx_daily_sales_top_revenue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_daily_sales_top_revenue ON public.daily_sales_fact USING btree (sale_date DESC, total_revenue DESC);


--
-- Name: idx_inventory_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_product ON public.inventory USING btree (product_id);


--
-- Name: idx_inventory_recorded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_inventory_recorded ON public.inventory USING btree (recorded_at);


--
-- Name: idx_leaderboard_rank; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leaderboard_rank ON public.leaderboard_top_products USING btree (rank);


--
-- Name: idx_market_insights_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_market_insights_product ON public.market_insights USING btree (product_id, sale_date DESC);


--
-- Name: idx_market_insights_top_share; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_market_insights_top_share ON public.market_insights USING btree (sale_date DESC, revenue_share DESC);


--
-- Name: idx_mv_hist_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mv_hist_date ON public.v_daily_sales_hist USING btree (sale_date DESC);


--
-- Name: idx_mv_hist_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mv_hist_sku ON public.v_daily_sales_hist USING btree (sku);


--
-- Name: idx_orders_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_date ON public.orders USING btree (order_date);


--
-- Name: idx_orders_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_product ON public.orders USING btree (product_id);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_product_alerts_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_alerts_created ON public.product_alerts USING btree (created_at DESC);


--
-- Name: idx_product_categories_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_categories_category ON public.product_categories USING btree (category_id);


--
-- Name: idx_product_competition_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_competition_score ON public.product_competition USING btree (competition_score DESC);


--
-- Name: idx_product_metrics_revenue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_metrics_revenue ON public.product_metrics USING btree (revenue_30d DESC);


--
-- Name: idx_product_trends_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_trends_score ON public.product_trends USING btree (trend_score DESC);


--
-- Name: idx_product_velocity_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_product_velocity_score ON public.product_velocity USING btree (velocity_score DESC);


--
-- Name: idx_products_brand; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_brand ON public.products USING btree (brand);


--
-- Name: idx_returns_rrd_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_returns_rrd_id ON public.returns USING btree (rrd_id) WHERE (rrd_id IS NOT NULL);


--
-- Name: idx_sales_brin_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_brin_date ON ONLY public.sales USING brin (sale_date);


--
-- Name: idx_sales_marketplace_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_marketplace_date ON ONLY public.sales USING btree (marketplace_id, sale_date);


--
-- Name: idx_sales_product_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_product_date ON ONLY public.sales USING btree (product_id, sale_date DESC);


--
-- Name: idx_sales_stage_sale_id_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sales_stage_sale_id_date ON public.sales_stage USING btree (sale_id, sale_date);


--
-- Name: idx_staging_sales_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staging_sales_lookup ON public.staging_sales_update USING btree (product_id, sale_date);


--
-- Name: products_nm_id_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX products_nm_id_key ON public.products USING btree (nm_id);


--
-- Name: profit_daily_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX profit_daily_date_idx ON public.profit_daily USING btree (date);


--
-- Name: profit_daily_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX profit_daily_uidx ON public.profit_daily USING btree (date, nm_id);


--
-- Name: sales_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_brand_idx ON ONLY public.sales USING btree (brand);


--
-- Name: sales_2023_01_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_01_brand_idx ON public.sales_2023_01 USING btree (brand);


--
-- Name: sales_2023_01_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_01_marketplace_id_sale_date_idx ON public.sales_2023_01 USING btree (marketplace_id, sale_date);


--
-- Name: sales_nm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_nm_idx ON ONLY public.sales USING btree (nm_id);


--
-- Name: sales_2023_01_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_01_nm_id_idx ON public.sales_2023_01 USING btree (nm_id);


--
-- Name: sales_2023_01_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_01_product_id_sale_date_idx ON public.sales_2023_01 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_01_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_01_sale_date_idx ON public.sales_2023_01 USING brin (sale_date);


--
-- Name: sales_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_date_idx ON ONLY public.sales USING btree (sale_date);


--
-- Name: sales_2023_01_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_01_sale_date_idx1 ON public.sales_2023_01 USING btree (sale_date);


--
-- Name: sales_sale_unique_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_sale_unique_idx ON ONLY public.sales USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_01_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_01 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_sale_id_date_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_sale_id_date_uidx ON ONLY public.sales USING btree (sale_id, sale_date);


--
-- Name: sales_2023_01_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_01_sale_id_sale_date_idx ON public.sales_2023_01 USING btree (sale_id, sale_date);


--
-- Name: sales_saleid_date_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_saleid_date_uidx ON ONLY public.sales USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_01_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_01_sale_id_sale_date_idx1 ON public.sales_2023_01 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_srid_date_uidx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_srid_date_uidx ON ONLY public.sales USING btree (srid, sale_date);


--
-- Name: sales_2023_01_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_01_srid_sale_date_idx ON public.sales_2023_01 USING btree (srid, sale_date);


--
-- Name: sales_wh_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_wh_idx ON ONLY public.sales USING btree (warehouse_name);


--
-- Name: sales_2023_01_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_01_warehouse_name_idx ON public.sales_2023_01 USING btree (warehouse_name);


--
-- Name: sales_2023_02_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_02_brand_idx ON public.sales_2023_02 USING btree (brand);


--
-- Name: sales_2023_02_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_02_marketplace_id_sale_date_idx ON public.sales_2023_02 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_02_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_02_nm_id_idx ON public.sales_2023_02 USING btree (nm_id);


--
-- Name: sales_2023_02_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_02_product_id_sale_date_idx ON public.sales_2023_02 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_02_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_02_sale_date_idx ON public.sales_2023_02 USING brin (sale_date);


--
-- Name: sales_2023_02_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_02_sale_date_idx1 ON public.sales_2023_02 USING btree (sale_date);


--
-- Name: sales_2023_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_02_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_02 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_02_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_02_sale_id_sale_date_idx ON public.sales_2023_02 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_02_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_02_sale_id_sale_date_idx1 ON public.sales_2023_02 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_02_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_02_srid_sale_date_idx ON public.sales_2023_02 USING btree (srid, sale_date);


--
-- Name: sales_2023_02_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_02_warehouse_name_idx ON public.sales_2023_02 USING btree (warehouse_name);


--
-- Name: sales_2023_03_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_03_brand_idx ON public.sales_2023_03 USING btree (brand);


--
-- Name: sales_2023_03_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_03_marketplace_id_sale_date_idx ON public.sales_2023_03 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_03_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_03_nm_id_idx ON public.sales_2023_03 USING btree (nm_id);


--
-- Name: sales_2023_03_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_03_product_id_sale_date_idx ON public.sales_2023_03 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_03_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_03_sale_date_idx ON public.sales_2023_03 USING brin (sale_date);


--
-- Name: sales_2023_03_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_03_sale_date_idx1 ON public.sales_2023_03 USING btree (sale_date);


--
-- Name: sales_2023_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_03_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_03 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_03_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_03_sale_id_sale_date_idx ON public.sales_2023_03 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_03_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_03_sale_id_sale_date_idx1 ON public.sales_2023_03 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_03_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_03_srid_sale_date_idx ON public.sales_2023_03 USING btree (srid, sale_date);


--
-- Name: sales_2023_03_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_03_warehouse_name_idx ON public.sales_2023_03 USING btree (warehouse_name);


--
-- Name: sales_2023_04_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_04_brand_idx ON public.sales_2023_04 USING btree (brand);


--
-- Name: sales_2023_04_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_04_marketplace_id_sale_date_idx ON public.sales_2023_04 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_04_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_04_nm_id_idx ON public.sales_2023_04 USING btree (nm_id);


--
-- Name: sales_2023_04_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_04_product_id_sale_date_idx ON public.sales_2023_04 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_04_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_04_sale_date_idx ON public.sales_2023_04 USING brin (sale_date);


--
-- Name: sales_2023_04_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_04_sale_date_idx1 ON public.sales_2023_04 USING btree (sale_date);


--
-- Name: sales_2023_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_04_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_04 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_04_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_04_sale_id_sale_date_idx ON public.sales_2023_04 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_04_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_04_sale_id_sale_date_idx1 ON public.sales_2023_04 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_04_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_04_srid_sale_date_idx ON public.sales_2023_04 USING btree (srid, sale_date);


--
-- Name: sales_2023_04_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_04_warehouse_name_idx ON public.sales_2023_04 USING btree (warehouse_name);


--
-- Name: sales_2023_05_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_05_brand_idx ON public.sales_2023_05 USING btree (brand);


--
-- Name: sales_2023_05_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_05_marketplace_id_sale_date_idx ON public.sales_2023_05 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_05_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_05_nm_id_idx ON public.sales_2023_05 USING btree (nm_id);


--
-- Name: sales_2023_05_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_05_product_id_sale_date_idx ON public.sales_2023_05 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_05_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_05_sale_date_idx ON public.sales_2023_05 USING brin (sale_date);


--
-- Name: sales_2023_05_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_05_sale_date_idx1 ON public.sales_2023_05 USING btree (sale_date);


--
-- Name: sales_2023_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_05_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_05 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_05_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_05_sale_id_sale_date_idx ON public.sales_2023_05 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_05_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_05_sale_id_sale_date_idx1 ON public.sales_2023_05 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_05_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_05_srid_sale_date_idx ON public.sales_2023_05 USING btree (srid, sale_date);


--
-- Name: sales_2023_05_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_05_warehouse_name_idx ON public.sales_2023_05 USING btree (warehouse_name);


--
-- Name: sales_2023_06_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_06_brand_idx ON public.sales_2023_06 USING btree (brand);


--
-- Name: sales_2023_06_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_06_marketplace_id_sale_date_idx ON public.sales_2023_06 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_06_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_06_nm_id_idx ON public.sales_2023_06 USING btree (nm_id);


--
-- Name: sales_2023_06_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_06_product_id_sale_date_idx ON public.sales_2023_06 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_06_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_06_sale_date_idx ON public.sales_2023_06 USING brin (sale_date);


--
-- Name: sales_2023_06_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_06_sale_date_idx1 ON public.sales_2023_06 USING btree (sale_date);


--
-- Name: sales_2023_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_06_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_06 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_06_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_06_sale_id_sale_date_idx ON public.sales_2023_06 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_06_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_06_sale_id_sale_date_idx1 ON public.sales_2023_06 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_06_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_06_srid_sale_date_idx ON public.sales_2023_06 USING btree (srid, sale_date);


--
-- Name: sales_2023_06_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_06_warehouse_name_idx ON public.sales_2023_06 USING btree (warehouse_name);


--
-- Name: sales_2023_07_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_07_brand_idx ON public.sales_2023_07 USING btree (brand);


--
-- Name: sales_2023_07_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_07_marketplace_id_sale_date_idx ON public.sales_2023_07 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_07_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_07_nm_id_idx ON public.sales_2023_07 USING btree (nm_id);


--
-- Name: sales_2023_07_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_07_product_id_sale_date_idx ON public.sales_2023_07 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_07_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_07_sale_date_idx ON public.sales_2023_07 USING brin (sale_date);


--
-- Name: sales_2023_07_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_07_sale_date_idx1 ON public.sales_2023_07 USING btree (sale_date);


--
-- Name: sales_2023_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_07_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_07 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_07_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_07_sale_id_sale_date_idx ON public.sales_2023_07 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_07_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_07_sale_id_sale_date_idx1 ON public.sales_2023_07 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_07_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_07_srid_sale_date_idx ON public.sales_2023_07 USING btree (srid, sale_date);


--
-- Name: sales_2023_07_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_07_warehouse_name_idx ON public.sales_2023_07 USING btree (warehouse_name);


--
-- Name: sales_2023_08_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_08_brand_idx ON public.sales_2023_08 USING btree (brand);


--
-- Name: sales_2023_08_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_08_marketplace_id_sale_date_idx ON public.sales_2023_08 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_08_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_08_nm_id_idx ON public.sales_2023_08 USING btree (nm_id);


--
-- Name: sales_2023_08_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_08_product_id_sale_date_idx ON public.sales_2023_08 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_08_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_08_sale_date_idx ON public.sales_2023_08 USING brin (sale_date);


--
-- Name: sales_2023_08_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_08_sale_date_idx1 ON public.sales_2023_08 USING btree (sale_date);


--
-- Name: sales_2023_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_08_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_08 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_08_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_08_sale_id_sale_date_idx ON public.sales_2023_08 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_08_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_08_sale_id_sale_date_idx1 ON public.sales_2023_08 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_08_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_08_srid_sale_date_idx ON public.sales_2023_08 USING btree (srid, sale_date);


--
-- Name: sales_2023_08_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_08_warehouse_name_idx ON public.sales_2023_08 USING btree (warehouse_name);


--
-- Name: sales_2023_09_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_09_brand_idx ON public.sales_2023_09 USING btree (brand);


--
-- Name: sales_2023_09_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_09_marketplace_id_sale_date_idx ON public.sales_2023_09 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_09_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_09_nm_id_idx ON public.sales_2023_09 USING btree (nm_id);


--
-- Name: sales_2023_09_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_09_product_id_sale_date_idx ON public.sales_2023_09 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_09_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_09_sale_date_idx ON public.sales_2023_09 USING brin (sale_date);


--
-- Name: sales_2023_09_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_09_sale_date_idx1 ON public.sales_2023_09 USING btree (sale_date);


--
-- Name: sales_2023_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_09_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_09 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_09_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_09_sale_id_sale_date_idx ON public.sales_2023_09 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_09_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_09_sale_id_sale_date_idx1 ON public.sales_2023_09 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_09_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_09_srid_sale_date_idx ON public.sales_2023_09 USING btree (srid, sale_date);


--
-- Name: sales_2023_09_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_09_warehouse_name_idx ON public.sales_2023_09 USING btree (warehouse_name);


--
-- Name: sales_2023_10_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_10_brand_idx ON public.sales_2023_10 USING btree (brand);


--
-- Name: sales_2023_10_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_10_marketplace_id_sale_date_idx ON public.sales_2023_10 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_10_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_10_nm_id_idx ON public.sales_2023_10 USING btree (nm_id);


--
-- Name: sales_2023_10_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_10_product_id_sale_date_idx ON public.sales_2023_10 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_10_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_10_sale_date_idx ON public.sales_2023_10 USING brin (sale_date);


--
-- Name: sales_2023_10_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_10_sale_date_idx1 ON public.sales_2023_10 USING btree (sale_date);


--
-- Name: sales_2023_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_10_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_10 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_10_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_10_sale_id_sale_date_idx ON public.sales_2023_10 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_10_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_10_sale_id_sale_date_idx1 ON public.sales_2023_10 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_10_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_10_srid_sale_date_idx ON public.sales_2023_10 USING btree (srid, sale_date);


--
-- Name: sales_2023_10_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_10_warehouse_name_idx ON public.sales_2023_10 USING btree (warehouse_name);


--
-- Name: sales_2023_11_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_11_brand_idx ON public.sales_2023_11 USING btree (brand);


--
-- Name: sales_2023_11_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_11_marketplace_id_sale_date_idx ON public.sales_2023_11 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_11_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_11_nm_id_idx ON public.sales_2023_11 USING btree (nm_id);


--
-- Name: sales_2023_11_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_11_product_id_sale_date_idx ON public.sales_2023_11 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_11_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_11_sale_date_idx ON public.sales_2023_11 USING brin (sale_date);


--
-- Name: sales_2023_11_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_11_sale_date_idx1 ON public.sales_2023_11 USING btree (sale_date);


--
-- Name: sales_2023_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_11_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_11 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_11_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_11_sale_id_sale_date_idx ON public.sales_2023_11 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_11_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_11_sale_id_sale_date_idx1 ON public.sales_2023_11 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_11_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_11_srid_sale_date_idx ON public.sales_2023_11 USING btree (srid, sale_date);


--
-- Name: sales_2023_11_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_11_warehouse_name_idx ON public.sales_2023_11 USING btree (warehouse_name);


--
-- Name: sales_2023_12_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_12_brand_idx ON public.sales_2023_12 USING btree (brand);


--
-- Name: sales_2023_12_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_12_marketplace_id_sale_date_idx ON public.sales_2023_12 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2023_12_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_12_nm_id_idx ON public.sales_2023_12 USING btree (nm_id);


--
-- Name: sales_2023_12_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_12_product_id_sale_date_idx ON public.sales_2023_12 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2023_12_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_12_sale_date_idx ON public.sales_2023_12 USING brin (sale_date);


--
-- Name: sales_2023_12_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_12_sale_date_idx1 ON public.sales_2023_12 USING btree (sale_date);


--
-- Name: sales_2023_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_12_sale_id_marketplace_id_sale_date_idx ON public.sales_2023_12 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2023_12_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_12_sale_id_sale_date_idx ON public.sales_2023_12 USING btree (sale_id, sale_date);


--
-- Name: sales_2023_12_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_12_sale_id_sale_date_idx1 ON public.sales_2023_12 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2023_12_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2023_12_srid_sale_date_idx ON public.sales_2023_12 USING btree (srid, sale_date);


--
-- Name: sales_2023_12_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2023_12_warehouse_name_idx ON public.sales_2023_12 USING btree (warehouse_name);


--
-- Name: sales_2024_01_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_01_brand_idx ON public.sales_2024_01 USING btree (brand);


--
-- Name: sales_2024_01_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_01_marketplace_id_sale_date_idx ON public.sales_2024_01 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_01_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_01_nm_id_idx ON public.sales_2024_01 USING btree (nm_id);


--
-- Name: sales_2024_01_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_01_product_id_sale_date_idx ON public.sales_2024_01 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_01_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_01_sale_date_idx ON public.sales_2024_01 USING brin (sale_date);


--
-- Name: sales_2024_01_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_01_sale_date_idx1 ON public.sales_2024_01 USING btree (sale_date);


--
-- Name: sales_2024_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_01_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_01 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_01_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_01_sale_id_sale_date_idx ON public.sales_2024_01 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_01_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_01_sale_id_sale_date_idx1 ON public.sales_2024_01 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_01_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_01_srid_sale_date_idx ON public.sales_2024_01 USING btree (srid, sale_date);


--
-- Name: sales_2024_01_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_01_warehouse_name_idx ON public.sales_2024_01 USING btree (warehouse_name);


--
-- Name: sales_2024_02_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_02_brand_idx ON public.sales_2024_02 USING btree (brand);


--
-- Name: sales_2024_02_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_02_marketplace_id_sale_date_idx ON public.sales_2024_02 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_02_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_02_nm_id_idx ON public.sales_2024_02 USING btree (nm_id);


--
-- Name: sales_2024_02_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_02_product_id_sale_date_idx ON public.sales_2024_02 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_02_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_02_sale_date_idx ON public.sales_2024_02 USING brin (sale_date);


--
-- Name: sales_2024_02_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_02_sale_date_idx1 ON public.sales_2024_02 USING btree (sale_date);


--
-- Name: sales_2024_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_02_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_02 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_02_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_02_sale_id_sale_date_idx ON public.sales_2024_02 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_02_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_02_sale_id_sale_date_idx1 ON public.sales_2024_02 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_02_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_02_srid_sale_date_idx ON public.sales_2024_02 USING btree (srid, sale_date);


--
-- Name: sales_2024_02_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_02_warehouse_name_idx ON public.sales_2024_02 USING btree (warehouse_name);


--
-- Name: sales_2024_03_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_03_brand_idx ON public.sales_2024_03 USING btree (brand);


--
-- Name: sales_2024_03_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_03_marketplace_id_sale_date_idx ON public.sales_2024_03 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_03_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_03_nm_id_idx ON public.sales_2024_03 USING btree (nm_id);


--
-- Name: sales_2024_03_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_03_product_id_sale_date_idx ON public.sales_2024_03 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_03_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_03_sale_date_idx ON public.sales_2024_03 USING brin (sale_date);


--
-- Name: sales_2024_03_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_03_sale_date_idx1 ON public.sales_2024_03 USING btree (sale_date);


--
-- Name: sales_2024_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_03_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_03 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_03_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_03_sale_id_sale_date_idx ON public.sales_2024_03 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_03_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_03_sale_id_sale_date_idx1 ON public.sales_2024_03 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_03_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_03_srid_sale_date_idx ON public.sales_2024_03 USING btree (srid, sale_date);


--
-- Name: sales_2024_03_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_03_warehouse_name_idx ON public.sales_2024_03 USING btree (warehouse_name);


--
-- Name: sales_2024_04_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_04_brand_idx ON public.sales_2024_04 USING btree (brand);


--
-- Name: sales_2024_04_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_04_marketplace_id_sale_date_idx ON public.sales_2024_04 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_04_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_04_nm_id_idx ON public.sales_2024_04 USING btree (nm_id);


--
-- Name: sales_2024_04_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_04_product_id_sale_date_idx ON public.sales_2024_04 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_04_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_04_sale_date_idx ON public.sales_2024_04 USING brin (sale_date);


--
-- Name: sales_2024_04_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_04_sale_date_idx1 ON public.sales_2024_04 USING btree (sale_date);


--
-- Name: sales_2024_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_04_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_04 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_04_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_04_sale_id_sale_date_idx ON public.sales_2024_04 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_04_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_04_sale_id_sale_date_idx1 ON public.sales_2024_04 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_04_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_04_srid_sale_date_idx ON public.sales_2024_04 USING btree (srid, sale_date);


--
-- Name: sales_2024_04_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_04_warehouse_name_idx ON public.sales_2024_04 USING btree (warehouse_name);


--
-- Name: sales_2024_05_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_05_brand_idx ON public.sales_2024_05 USING btree (brand);


--
-- Name: sales_2024_05_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_05_marketplace_id_sale_date_idx ON public.sales_2024_05 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_05_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_05_nm_id_idx ON public.sales_2024_05 USING btree (nm_id);


--
-- Name: sales_2024_05_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_05_product_id_sale_date_idx ON public.sales_2024_05 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_05_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_05_sale_date_idx ON public.sales_2024_05 USING brin (sale_date);


--
-- Name: sales_2024_05_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_05_sale_date_idx1 ON public.sales_2024_05 USING btree (sale_date);


--
-- Name: sales_2024_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_05_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_05 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_05_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_05_sale_id_sale_date_idx ON public.sales_2024_05 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_05_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_05_sale_id_sale_date_idx1 ON public.sales_2024_05 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_05_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_05_srid_sale_date_idx ON public.sales_2024_05 USING btree (srid, sale_date);


--
-- Name: sales_2024_05_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_05_warehouse_name_idx ON public.sales_2024_05 USING btree (warehouse_name);


--
-- Name: sales_2024_06_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_06_brand_idx ON public.sales_2024_06 USING btree (brand);


--
-- Name: sales_2024_06_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_06_marketplace_id_sale_date_idx ON public.sales_2024_06 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_06_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_06_nm_id_idx ON public.sales_2024_06 USING btree (nm_id);


--
-- Name: sales_2024_06_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_06_product_id_sale_date_idx ON public.sales_2024_06 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_06_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_06_sale_date_idx ON public.sales_2024_06 USING brin (sale_date);


--
-- Name: sales_2024_06_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_06_sale_date_idx1 ON public.sales_2024_06 USING btree (sale_date);


--
-- Name: sales_2024_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_06_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_06 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_06_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_06_sale_id_sale_date_idx ON public.sales_2024_06 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_06_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_06_sale_id_sale_date_idx1 ON public.sales_2024_06 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_06_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_06_srid_sale_date_idx ON public.sales_2024_06 USING btree (srid, sale_date);


--
-- Name: sales_2024_06_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_06_warehouse_name_idx ON public.sales_2024_06 USING btree (warehouse_name);


--
-- Name: sales_2024_07_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_07_brand_idx ON public.sales_2024_07 USING btree (brand);


--
-- Name: sales_2024_07_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_07_marketplace_id_sale_date_idx ON public.sales_2024_07 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_07_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_07_nm_id_idx ON public.sales_2024_07 USING btree (nm_id);


--
-- Name: sales_2024_07_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_07_product_id_sale_date_idx ON public.sales_2024_07 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_07_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_07_sale_date_idx ON public.sales_2024_07 USING brin (sale_date);


--
-- Name: sales_2024_07_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_07_sale_date_idx1 ON public.sales_2024_07 USING btree (sale_date);


--
-- Name: sales_2024_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_07_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_07 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_07_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_07_sale_id_sale_date_idx ON public.sales_2024_07 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_07_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_07_sale_id_sale_date_idx1 ON public.sales_2024_07 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_07_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_07_srid_sale_date_idx ON public.sales_2024_07 USING btree (srid, sale_date);


--
-- Name: sales_2024_07_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_07_warehouse_name_idx ON public.sales_2024_07 USING btree (warehouse_name);


--
-- Name: sales_2024_08_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_08_brand_idx ON public.sales_2024_08 USING btree (brand);


--
-- Name: sales_2024_08_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_08_marketplace_id_sale_date_idx ON public.sales_2024_08 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_08_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_08_nm_id_idx ON public.sales_2024_08 USING btree (nm_id);


--
-- Name: sales_2024_08_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_08_product_id_sale_date_idx ON public.sales_2024_08 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_08_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_08_sale_date_idx ON public.sales_2024_08 USING brin (sale_date);


--
-- Name: sales_2024_08_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_08_sale_date_idx1 ON public.sales_2024_08 USING btree (sale_date);


--
-- Name: sales_2024_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_08_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_08 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_08_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_08_sale_id_sale_date_idx ON public.sales_2024_08 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_08_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_08_sale_id_sale_date_idx1 ON public.sales_2024_08 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_08_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_08_srid_sale_date_idx ON public.sales_2024_08 USING btree (srid, sale_date);


--
-- Name: sales_2024_08_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_08_warehouse_name_idx ON public.sales_2024_08 USING btree (warehouse_name);


--
-- Name: sales_2024_09_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_09_brand_idx ON public.sales_2024_09 USING btree (brand);


--
-- Name: sales_2024_09_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_09_marketplace_id_sale_date_idx ON public.sales_2024_09 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_09_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_09_nm_id_idx ON public.sales_2024_09 USING btree (nm_id);


--
-- Name: sales_2024_09_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_09_product_id_sale_date_idx ON public.sales_2024_09 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_09_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_09_sale_date_idx ON public.sales_2024_09 USING brin (sale_date);


--
-- Name: sales_2024_09_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_09_sale_date_idx1 ON public.sales_2024_09 USING btree (sale_date);


--
-- Name: sales_2024_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_09_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_09 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_09_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_09_sale_id_sale_date_idx ON public.sales_2024_09 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_09_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_09_sale_id_sale_date_idx1 ON public.sales_2024_09 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_09_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_09_srid_sale_date_idx ON public.sales_2024_09 USING btree (srid, sale_date);


--
-- Name: sales_2024_09_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_09_warehouse_name_idx ON public.sales_2024_09 USING btree (warehouse_name);


--
-- Name: sales_2024_10_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_10_brand_idx ON public.sales_2024_10 USING btree (brand);


--
-- Name: sales_2024_10_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_10_marketplace_id_sale_date_idx ON public.sales_2024_10 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_10_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_10_nm_id_idx ON public.sales_2024_10 USING btree (nm_id);


--
-- Name: sales_2024_10_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_10_product_id_sale_date_idx ON public.sales_2024_10 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_10_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_10_sale_date_idx ON public.sales_2024_10 USING brin (sale_date);


--
-- Name: sales_2024_10_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_10_sale_date_idx1 ON public.sales_2024_10 USING btree (sale_date);


--
-- Name: sales_2024_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_10_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_10 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_10_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_10_sale_id_sale_date_idx ON public.sales_2024_10 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_10_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_10_sale_id_sale_date_idx1 ON public.sales_2024_10 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_10_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_10_srid_sale_date_idx ON public.sales_2024_10 USING btree (srid, sale_date);


--
-- Name: sales_2024_10_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_10_warehouse_name_idx ON public.sales_2024_10 USING btree (warehouse_name);


--
-- Name: sales_2024_11_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_11_brand_idx ON public.sales_2024_11 USING btree (brand);


--
-- Name: sales_2024_11_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_11_marketplace_id_sale_date_idx ON public.sales_2024_11 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_11_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_11_nm_id_idx ON public.sales_2024_11 USING btree (nm_id);


--
-- Name: sales_2024_11_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_11_product_id_sale_date_idx ON public.sales_2024_11 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_11_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_11_sale_date_idx ON public.sales_2024_11 USING brin (sale_date);


--
-- Name: sales_2024_11_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_11_sale_date_idx1 ON public.sales_2024_11 USING btree (sale_date);


--
-- Name: sales_2024_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_11_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_11 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_11_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_11_sale_id_sale_date_idx ON public.sales_2024_11 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_11_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_11_sale_id_sale_date_idx1 ON public.sales_2024_11 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_11_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_11_srid_sale_date_idx ON public.sales_2024_11 USING btree (srid, sale_date);


--
-- Name: sales_2024_11_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_11_warehouse_name_idx ON public.sales_2024_11 USING btree (warehouse_name);


--
-- Name: sales_2024_12_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_12_brand_idx ON public.sales_2024_12 USING btree (brand);


--
-- Name: sales_2024_12_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_12_marketplace_id_sale_date_idx ON public.sales_2024_12 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2024_12_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_12_nm_id_idx ON public.sales_2024_12 USING btree (nm_id);


--
-- Name: sales_2024_12_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_12_product_id_sale_date_idx ON public.sales_2024_12 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2024_12_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_12_sale_date_idx ON public.sales_2024_12 USING brin (sale_date);


--
-- Name: sales_2024_12_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_12_sale_date_idx1 ON public.sales_2024_12 USING btree (sale_date);


--
-- Name: sales_2024_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_12_sale_id_marketplace_id_sale_date_idx ON public.sales_2024_12 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2024_12_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_12_sale_id_sale_date_idx ON public.sales_2024_12 USING btree (sale_id, sale_date);


--
-- Name: sales_2024_12_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_12_sale_id_sale_date_idx1 ON public.sales_2024_12 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2024_12_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2024_12_srid_sale_date_idx ON public.sales_2024_12 USING btree (srid, sale_date);


--
-- Name: sales_2024_12_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2024_12_warehouse_name_idx ON public.sales_2024_12 USING btree (warehouse_name);


--
-- Name: sales_2025_01_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_01_brand_idx ON public.sales_2025_01 USING btree (brand);


--
-- Name: sales_2025_01_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_01_marketplace_id_sale_date_idx ON public.sales_2025_01 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_01_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_01_nm_id_idx ON public.sales_2025_01 USING btree (nm_id);


--
-- Name: sales_2025_01_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_01_product_id_sale_date_idx ON public.sales_2025_01 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_01_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_01_sale_date_idx ON public.sales_2025_01 USING brin (sale_date);


--
-- Name: sales_2025_01_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_01_sale_date_idx1 ON public.sales_2025_01 USING btree (sale_date);


--
-- Name: sales_2025_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_01_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_01 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_01_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_01_sale_id_sale_date_idx ON public.sales_2025_01 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_01_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_01_sale_id_sale_date_idx1 ON public.sales_2025_01 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_01_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_01_srid_sale_date_idx ON public.sales_2025_01 USING btree (srid, sale_date);


--
-- Name: sales_2025_01_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_01_warehouse_name_idx ON public.sales_2025_01 USING btree (warehouse_name);


--
-- Name: sales_2025_02_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_02_brand_idx ON public.sales_2025_02 USING btree (brand);


--
-- Name: sales_2025_02_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_02_marketplace_id_sale_date_idx ON public.sales_2025_02 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_02_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_02_nm_id_idx ON public.sales_2025_02 USING btree (nm_id);


--
-- Name: sales_2025_02_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_02_product_id_sale_date_idx ON public.sales_2025_02 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_02_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_02_sale_date_idx ON public.sales_2025_02 USING brin (sale_date);


--
-- Name: sales_2025_02_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_02_sale_date_idx1 ON public.sales_2025_02 USING btree (sale_date);


--
-- Name: sales_2025_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_02_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_02 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_02_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_02_sale_id_sale_date_idx ON public.sales_2025_02 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_02_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_02_sale_id_sale_date_idx1 ON public.sales_2025_02 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_02_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_02_srid_sale_date_idx ON public.sales_2025_02 USING btree (srid, sale_date);


--
-- Name: sales_2025_02_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_02_warehouse_name_idx ON public.sales_2025_02 USING btree (warehouse_name);


--
-- Name: sales_2025_03_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_03_brand_idx ON public.sales_2025_03 USING btree (brand);


--
-- Name: sales_2025_03_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_03_marketplace_id_sale_date_idx ON public.sales_2025_03 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_03_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_03_nm_id_idx ON public.sales_2025_03 USING btree (nm_id);


--
-- Name: sales_2025_03_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_03_product_id_sale_date_idx ON public.sales_2025_03 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_03_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_03_sale_date_idx ON public.sales_2025_03 USING brin (sale_date);


--
-- Name: sales_2025_03_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_03_sale_date_idx1 ON public.sales_2025_03 USING btree (sale_date);


--
-- Name: sales_2025_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_03_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_03 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_03_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_03_sale_id_sale_date_idx ON public.sales_2025_03 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_03_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_03_sale_id_sale_date_idx1 ON public.sales_2025_03 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_03_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_03_srid_sale_date_idx ON public.sales_2025_03 USING btree (srid, sale_date);


--
-- Name: sales_2025_03_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_03_warehouse_name_idx ON public.sales_2025_03 USING btree (warehouse_name);


--
-- Name: sales_2025_04_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_04_brand_idx ON public.sales_2025_04 USING btree (brand);


--
-- Name: sales_2025_04_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_04_marketplace_id_sale_date_idx ON public.sales_2025_04 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_04_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_04_nm_id_idx ON public.sales_2025_04 USING btree (nm_id);


--
-- Name: sales_2025_04_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_04_product_id_sale_date_idx ON public.sales_2025_04 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_04_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_04_sale_date_idx ON public.sales_2025_04 USING brin (sale_date);


--
-- Name: sales_2025_04_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_04_sale_date_idx1 ON public.sales_2025_04 USING btree (sale_date);


--
-- Name: sales_2025_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_04_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_04 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_04_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_04_sale_id_sale_date_idx ON public.sales_2025_04 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_04_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_04_sale_id_sale_date_idx1 ON public.sales_2025_04 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_04_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_04_srid_sale_date_idx ON public.sales_2025_04 USING btree (srid, sale_date);


--
-- Name: sales_2025_04_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_04_warehouse_name_idx ON public.sales_2025_04 USING btree (warehouse_name);


--
-- Name: sales_2025_05_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_05_brand_idx ON public.sales_2025_05 USING btree (brand);


--
-- Name: sales_2025_05_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_05_marketplace_id_sale_date_idx ON public.sales_2025_05 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_05_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_05_nm_id_idx ON public.sales_2025_05 USING btree (nm_id);


--
-- Name: sales_2025_05_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_05_product_id_sale_date_idx ON public.sales_2025_05 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_05_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_05_sale_date_idx ON public.sales_2025_05 USING brin (sale_date);


--
-- Name: sales_2025_05_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_05_sale_date_idx1 ON public.sales_2025_05 USING btree (sale_date);


--
-- Name: sales_2025_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_05_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_05 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_05_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_05_sale_id_sale_date_idx ON public.sales_2025_05 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_05_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_05_sale_id_sale_date_idx1 ON public.sales_2025_05 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_05_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_05_srid_sale_date_idx ON public.sales_2025_05 USING btree (srid, sale_date);


--
-- Name: sales_2025_05_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_05_warehouse_name_idx ON public.sales_2025_05 USING btree (warehouse_name);


--
-- Name: sales_2025_06_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_06_brand_idx ON public.sales_2025_06 USING btree (brand);


--
-- Name: sales_2025_06_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_06_marketplace_id_sale_date_idx ON public.sales_2025_06 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_06_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_06_nm_id_idx ON public.sales_2025_06 USING btree (nm_id);


--
-- Name: sales_2025_06_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_06_product_id_sale_date_idx ON public.sales_2025_06 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_06_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_06_sale_date_idx ON public.sales_2025_06 USING brin (sale_date);


--
-- Name: sales_2025_06_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_06_sale_date_idx1 ON public.sales_2025_06 USING btree (sale_date);


--
-- Name: sales_2025_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_06_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_06 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_06_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_06_sale_id_sale_date_idx ON public.sales_2025_06 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_06_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_06_sale_id_sale_date_idx1 ON public.sales_2025_06 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_06_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_06_srid_sale_date_idx ON public.sales_2025_06 USING btree (srid, sale_date);


--
-- Name: sales_2025_06_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_06_warehouse_name_idx ON public.sales_2025_06 USING btree (warehouse_name);


--
-- Name: sales_2025_07_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_07_brand_idx ON public.sales_2025_07 USING btree (brand);


--
-- Name: sales_2025_07_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_07_marketplace_id_sale_date_idx ON public.sales_2025_07 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_07_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_07_nm_id_idx ON public.sales_2025_07 USING btree (nm_id);


--
-- Name: sales_2025_07_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_07_product_id_sale_date_idx ON public.sales_2025_07 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_07_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_07_sale_date_idx ON public.sales_2025_07 USING brin (sale_date);


--
-- Name: sales_2025_07_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_07_sale_date_idx1 ON public.sales_2025_07 USING btree (sale_date);


--
-- Name: sales_2025_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_07_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_07 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_07_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_07_sale_id_sale_date_idx ON public.sales_2025_07 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_07_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_07_sale_id_sale_date_idx1 ON public.sales_2025_07 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_07_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_07_srid_sale_date_idx ON public.sales_2025_07 USING btree (srid, sale_date);


--
-- Name: sales_2025_07_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_07_warehouse_name_idx ON public.sales_2025_07 USING btree (warehouse_name);


--
-- Name: sales_2025_08_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_08_brand_idx ON public.sales_2025_08 USING btree (brand);


--
-- Name: sales_2025_08_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_08_marketplace_id_sale_date_idx ON public.sales_2025_08 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_08_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_08_nm_id_idx ON public.sales_2025_08 USING btree (nm_id);


--
-- Name: sales_2025_08_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_08_product_id_sale_date_idx ON public.sales_2025_08 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_08_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_08_sale_date_idx ON public.sales_2025_08 USING brin (sale_date);


--
-- Name: sales_2025_08_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_08_sale_date_idx1 ON public.sales_2025_08 USING btree (sale_date);


--
-- Name: sales_2025_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_08_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_08 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_08_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_08_sale_id_sale_date_idx ON public.sales_2025_08 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_08_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_08_sale_id_sale_date_idx1 ON public.sales_2025_08 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_08_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_08_srid_sale_date_idx ON public.sales_2025_08 USING btree (srid, sale_date);


--
-- Name: sales_2025_08_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_08_warehouse_name_idx ON public.sales_2025_08 USING btree (warehouse_name);


--
-- Name: sales_2025_09_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_09_brand_idx ON public.sales_2025_09 USING btree (brand);


--
-- Name: sales_2025_09_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_09_marketplace_id_sale_date_idx ON public.sales_2025_09 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_09_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_09_nm_id_idx ON public.sales_2025_09 USING btree (nm_id);


--
-- Name: sales_2025_09_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_09_product_id_sale_date_idx ON public.sales_2025_09 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_09_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_09_sale_date_idx ON public.sales_2025_09 USING brin (sale_date);


--
-- Name: sales_2025_09_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_09_sale_date_idx1 ON public.sales_2025_09 USING btree (sale_date);


--
-- Name: sales_2025_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_09_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_09 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_09_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_09_sale_id_sale_date_idx ON public.sales_2025_09 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_09_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_09_sale_id_sale_date_idx1 ON public.sales_2025_09 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_09_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_09_srid_sale_date_idx ON public.sales_2025_09 USING btree (srid, sale_date);


--
-- Name: sales_2025_09_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_09_warehouse_name_idx ON public.sales_2025_09 USING btree (warehouse_name);


--
-- Name: sales_2025_10_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_10_brand_idx ON public.sales_2025_10 USING btree (brand);


--
-- Name: sales_2025_10_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_10_marketplace_id_sale_date_idx ON public.sales_2025_10 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_10_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_10_nm_id_idx ON public.sales_2025_10 USING btree (nm_id);


--
-- Name: sales_2025_10_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_10_product_id_sale_date_idx ON public.sales_2025_10 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_10_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_10_sale_date_idx ON public.sales_2025_10 USING brin (sale_date);


--
-- Name: sales_2025_10_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_10_sale_date_idx1 ON public.sales_2025_10 USING btree (sale_date);


--
-- Name: sales_2025_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_10_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_10 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_10_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_10_sale_id_sale_date_idx ON public.sales_2025_10 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_10_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_10_sale_id_sale_date_idx1 ON public.sales_2025_10 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_10_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_10_srid_sale_date_idx ON public.sales_2025_10 USING btree (srid, sale_date);


--
-- Name: sales_2025_10_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_10_warehouse_name_idx ON public.sales_2025_10 USING btree (warehouse_name);


--
-- Name: sales_2025_11_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_11_brand_idx ON public.sales_2025_11 USING btree (brand);


--
-- Name: sales_2025_11_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_11_marketplace_id_sale_date_idx ON public.sales_2025_11 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_11_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_11_nm_id_idx ON public.sales_2025_11 USING btree (nm_id);


--
-- Name: sales_2025_11_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_11_product_id_sale_date_idx ON public.sales_2025_11 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_11_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_11_sale_date_idx ON public.sales_2025_11 USING brin (sale_date);


--
-- Name: sales_2025_11_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_11_sale_date_idx1 ON public.sales_2025_11 USING btree (sale_date);


--
-- Name: sales_2025_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_11_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_11 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_11_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_11_sale_id_sale_date_idx ON public.sales_2025_11 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_11_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_11_sale_id_sale_date_idx1 ON public.sales_2025_11 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_11_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_11_srid_sale_date_idx ON public.sales_2025_11 USING btree (srid, sale_date);


--
-- Name: sales_2025_11_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_11_warehouse_name_idx ON public.sales_2025_11 USING btree (warehouse_name);


--
-- Name: sales_2025_12_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_12_brand_idx ON public.sales_2025_12 USING btree (brand);


--
-- Name: sales_2025_12_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_12_marketplace_id_sale_date_idx ON public.sales_2025_12 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2025_12_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_12_nm_id_idx ON public.sales_2025_12 USING btree (nm_id);


--
-- Name: sales_2025_12_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_12_product_id_sale_date_idx ON public.sales_2025_12 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2025_12_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_12_sale_date_idx ON public.sales_2025_12 USING brin (sale_date);


--
-- Name: sales_2025_12_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_12_sale_date_idx1 ON public.sales_2025_12 USING btree (sale_date);


--
-- Name: sales_2025_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_12_sale_id_marketplace_id_sale_date_idx ON public.sales_2025_12 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2025_12_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_12_sale_id_sale_date_idx ON public.sales_2025_12 USING btree (sale_id, sale_date);


--
-- Name: sales_2025_12_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_12_sale_id_sale_date_idx1 ON public.sales_2025_12 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2025_12_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2025_12_srid_sale_date_idx ON public.sales_2025_12 USING btree (srid, sale_date);


--
-- Name: sales_2025_12_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2025_12_warehouse_name_idx ON public.sales_2025_12 USING btree (warehouse_name);


--
-- Name: sales_2026_01_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_01_brand_idx ON public.sales_2026_01 USING btree (brand);


--
-- Name: sales_2026_01_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_01_marketplace_id_sale_date_idx ON public.sales_2026_01 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_01_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_01_nm_id_idx ON public.sales_2026_01 USING btree (nm_id);


--
-- Name: sales_2026_01_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_01_product_id_sale_date_idx ON public.sales_2026_01 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_01_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_01_sale_date_idx ON public.sales_2026_01 USING brin (sale_date);


--
-- Name: sales_2026_01_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_01_sale_date_idx1 ON public.sales_2026_01 USING btree (sale_date);


--
-- Name: sales_2026_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_01_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_01 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_01_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_01_sale_id_sale_date_idx ON public.sales_2026_01 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_01_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_01_sale_id_sale_date_idx1 ON public.sales_2026_01 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_01_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_01_srid_sale_date_idx ON public.sales_2026_01 USING btree (srid, sale_date);


--
-- Name: sales_2026_01_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_01_warehouse_name_idx ON public.sales_2026_01 USING btree (warehouse_name);


--
-- Name: sales_2026_02_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_02_brand_idx ON public.sales_2026_02 USING btree (brand);


--
-- Name: sales_2026_02_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_02_marketplace_id_sale_date_idx ON public.sales_2026_02 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_02_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_02_nm_id_idx ON public.sales_2026_02 USING btree (nm_id);


--
-- Name: sales_2026_02_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_02_product_id_sale_date_idx ON public.sales_2026_02 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_02_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_02_sale_date_idx ON public.sales_2026_02 USING brin (sale_date);


--
-- Name: sales_2026_02_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_02_sale_date_idx1 ON public.sales_2026_02 USING btree (sale_date);


--
-- Name: sales_2026_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_02_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_02 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_02_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_02_sale_id_sale_date_idx ON public.sales_2026_02 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_02_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_02_sale_id_sale_date_idx1 ON public.sales_2026_02 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_02_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_02_srid_sale_date_idx ON public.sales_2026_02 USING btree (srid, sale_date);


--
-- Name: sales_2026_02_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_02_warehouse_name_idx ON public.sales_2026_02 USING btree (warehouse_name);


--
-- Name: sales_2026_03_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_03_brand_idx ON public.sales_2026_03 USING btree (brand);


--
-- Name: sales_2026_03_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_03_marketplace_id_sale_date_idx ON public.sales_2026_03 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_03_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_03_nm_id_idx ON public.sales_2026_03 USING btree (nm_id);


--
-- Name: sales_2026_03_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_03_product_id_sale_date_idx ON public.sales_2026_03 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_03_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_03_sale_date_idx ON public.sales_2026_03 USING brin (sale_date);


--
-- Name: sales_2026_03_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_03_sale_date_idx1 ON public.sales_2026_03 USING btree (sale_date);


--
-- Name: sales_2026_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_03_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_03 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_03_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_03_sale_id_sale_date_idx ON public.sales_2026_03 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_03_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_03_sale_id_sale_date_idx1 ON public.sales_2026_03 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_03_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_03_srid_sale_date_idx ON public.sales_2026_03 USING btree (srid, sale_date);


--
-- Name: sales_2026_03_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_03_warehouse_name_idx ON public.sales_2026_03 USING btree (warehouse_name);


--
-- Name: sales_2026_04_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_04_brand_idx ON public.sales_2026_04 USING btree (brand);


--
-- Name: sales_2026_04_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_04_marketplace_id_sale_date_idx ON public.sales_2026_04 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_04_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_04_nm_id_idx ON public.sales_2026_04 USING btree (nm_id);


--
-- Name: sales_2026_04_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_04_product_id_sale_date_idx ON public.sales_2026_04 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_04_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_04_sale_date_idx ON public.sales_2026_04 USING brin (sale_date);


--
-- Name: sales_2026_04_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_04_sale_date_idx1 ON public.sales_2026_04 USING btree (sale_date);


--
-- Name: sales_2026_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_04_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_04 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_04_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_04_sale_id_sale_date_idx ON public.sales_2026_04 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_04_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_04_sale_id_sale_date_idx1 ON public.sales_2026_04 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_04_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_04_srid_sale_date_idx ON public.sales_2026_04 USING btree (srid, sale_date);


--
-- Name: sales_2026_04_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_04_warehouse_name_idx ON public.sales_2026_04 USING btree (warehouse_name);


--
-- Name: sales_2026_05_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_05_brand_idx ON public.sales_2026_05 USING btree (brand);


--
-- Name: sales_2026_05_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_05_marketplace_id_sale_date_idx ON public.sales_2026_05 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_05_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_05_nm_id_idx ON public.sales_2026_05 USING btree (nm_id);


--
-- Name: sales_2026_05_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_05_product_id_sale_date_idx ON public.sales_2026_05 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_05_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_05_sale_date_idx ON public.sales_2026_05 USING brin (sale_date);


--
-- Name: sales_2026_05_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_05_sale_date_idx1 ON public.sales_2026_05 USING btree (sale_date);


--
-- Name: sales_2026_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_05_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_05 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_05_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_05_sale_id_sale_date_idx ON public.sales_2026_05 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_05_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_05_sale_id_sale_date_idx1 ON public.sales_2026_05 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_05_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_05_srid_sale_date_idx ON public.sales_2026_05 USING btree (srid, sale_date);


--
-- Name: sales_2026_05_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_05_warehouse_name_idx ON public.sales_2026_05 USING btree (warehouse_name);


--
-- Name: sales_2026_06_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_06_brand_idx ON public.sales_2026_06 USING btree (brand);


--
-- Name: sales_2026_06_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_06_marketplace_id_sale_date_idx ON public.sales_2026_06 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_06_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_06_nm_id_idx ON public.sales_2026_06 USING btree (nm_id);


--
-- Name: sales_2026_06_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_06_product_id_sale_date_idx ON public.sales_2026_06 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_06_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_06_sale_date_idx ON public.sales_2026_06 USING brin (sale_date);


--
-- Name: sales_2026_06_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_06_sale_date_idx1 ON public.sales_2026_06 USING btree (sale_date);


--
-- Name: sales_2026_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_06_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_06 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_06_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_06_sale_id_sale_date_idx ON public.sales_2026_06 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_06_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_06_sale_id_sale_date_idx1 ON public.sales_2026_06 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_06_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_06_srid_sale_date_idx ON public.sales_2026_06 USING btree (srid, sale_date);


--
-- Name: sales_2026_06_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_06_warehouse_name_idx ON public.sales_2026_06 USING btree (warehouse_name);


--
-- Name: sales_2026_07_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_07_brand_idx ON public.sales_2026_07 USING btree (brand);


--
-- Name: sales_2026_07_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_07_marketplace_id_sale_date_idx ON public.sales_2026_07 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_07_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_07_nm_id_idx ON public.sales_2026_07 USING btree (nm_id);


--
-- Name: sales_2026_07_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_07_product_id_sale_date_idx ON public.sales_2026_07 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_07_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_07_sale_date_idx ON public.sales_2026_07 USING brin (sale_date);


--
-- Name: sales_2026_07_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_07_sale_date_idx1 ON public.sales_2026_07 USING btree (sale_date);


--
-- Name: sales_2026_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_07_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_07 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_07_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_07_sale_id_sale_date_idx ON public.sales_2026_07 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_07_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_07_sale_id_sale_date_idx1 ON public.sales_2026_07 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_07_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_07_srid_sale_date_idx ON public.sales_2026_07 USING btree (srid, sale_date);


--
-- Name: sales_2026_07_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_07_warehouse_name_idx ON public.sales_2026_07 USING btree (warehouse_name);


--
-- Name: sales_2026_08_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_08_brand_idx ON public.sales_2026_08 USING btree (brand);


--
-- Name: sales_2026_08_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_08_marketplace_id_sale_date_idx ON public.sales_2026_08 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_08_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_08_nm_id_idx ON public.sales_2026_08 USING btree (nm_id);


--
-- Name: sales_2026_08_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_08_product_id_sale_date_idx ON public.sales_2026_08 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_08_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_08_sale_date_idx ON public.sales_2026_08 USING brin (sale_date);


--
-- Name: sales_2026_08_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_08_sale_date_idx1 ON public.sales_2026_08 USING btree (sale_date);


--
-- Name: sales_2026_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_08_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_08 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_08_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_08_sale_id_sale_date_idx ON public.sales_2026_08 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_08_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_08_sale_id_sale_date_idx1 ON public.sales_2026_08 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_08_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_08_srid_sale_date_idx ON public.sales_2026_08 USING btree (srid, sale_date);


--
-- Name: sales_2026_08_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_08_warehouse_name_idx ON public.sales_2026_08 USING btree (warehouse_name);


--
-- Name: sales_2026_09_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_09_brand_idx ON public.sales_2026_09 USING btree (brand);


--
-- Name: sales_2026_09_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_09_marketplace_id_sale_date_idx ON public.sales_2026_09 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_09_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_09_nm_id_idx ON public.sales_2026_09 USING btree (nm_id);


--
-- Name: sales_2026_09_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_09_product_id_sale_date_idx ON public.sales_2026_09 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_09_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_09_sale_date_idx ON public.sales_2026_09 USING brin (sale_date);


--
-- Name: sales_2026_09_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_09_sale_date_idx1 ON public.sales_2026_09 USING btree (sale_date);


--
-- Name: sales_2026_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_09_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_09 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_09_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_09_sale_id_sale_date_idx ON public.sales_2026_09 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_09_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_09_sale_id_sale_date_idx1 ON public.sales_2026_09 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_09_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_09_srid_sale_date_idx ON public.sales_2026_09 USING btree (srid, sale_date);


--
-- Name: sales_2026_09_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_09_warehouse_name_idx ON public.sales_2026_09 USING btree (warehouse_name);


--
-- Name: sales_2026_10_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_10_brand_idx ON public.sales_2026_10 USING btree (brand);


--
-- Name: sales_2026_10_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_10_marketplace_id_sale_date_idx ON public.sales_2026_10 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_10_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_10_nm_id_idx ON public.sales_2026_10 USING btree (nm_id);


--
-- Name: sales_2026_10_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_10_product_id_sale_date_idx ON public.sales_2026_10 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_10_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_10_sale_date_idx ON public.sales_2026_10 USING brin (sale_date);


--
-- Name: sales_2026_10_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_10_sale_date_idx1 ON public.sales_2026_10 USING btree (sale_date);


--
-- Name: sales_2026_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_10_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_10 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_10_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_10_sale_id_sale_date_idx ON public.sales_2026_10 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_10_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_10_sale_id_sale_date_idx1 ON public.sales_2026_10 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_10_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_10_srid_sale_date_idx ON public.sales_2026_10 USING btree (srid, sale_date);


--
-- Name: sales_2026_10_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_10_warehouse_name_idx ON public.sales_2026_10 USING btree (warehouse_name);


--
-- Name: sales_2026_11_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_11_brand_idx ON public.sales_2026_11 USING btree (brand);


--
-- Name: sales_2026_11_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_11_marketplace_id_sale_date_idx ON public.sales_2026_11 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_11_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_11_nm_id_idx ON public.sales_2026_11 USING btree (nm_id);


--
-- Name: sales_2026_11_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_11_product_id_sale_date_idx ON public.sales_2026_11 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_11_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_11_sale_date_idx ON public.sales_2026_11 USING brin (sale_date);


--
-- Name: sales_2026_11_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_11_sale_date_idx1 ON public.sales_2026_11 USING btree (sale_date);


--
-- Name: sales_2026_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_11_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_11 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_11_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_11_sale_id_sale_date_idx ON public.sales_2026_11 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_11_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_11_sale_id_sale_date_idx1 ON public.sales_2026_11 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_11_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_11_srid_sale_date_idx ON public.sales_2026_11 USING btree (srid, sale_date);


--
-- Name: sales_2026_11_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_11_warehouse_name_idx ON public.sales_2026_11 USING btree (warehouse_name);


--
-- Name: sales_2026_12_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_12_brand_idx ON public.sales_2026_12 USING btree (brand);


--
-- Name: sales_2026_12_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_12_marketplace_id_sale_date_idx ON public.sales_2026_12 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2026_12_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_12_nm_id_idx ON public.sales_2026_12 USING btree (nm_id);


--
-- Name: sales_2026_12_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_12_product_id_sale_date_idx ON public.sales_2026_12 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2026_12_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_12_sale_date_idx ON public.sales_2026_12 USING brin (sale_date);


--
-- Name: sales_2026_12_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_12_sale_date_idx1 ON public.sales_2026_12 USING btree (sale_date);


--
-- Name: sales_2026_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_12_sale_id_marketplace_id_sale_date_idx ON public.sales_2026_12 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2026_12_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_12_sale_id_sale_date_idx ON public.sales_2026_12 USING btree (sale_id, sale_date);


--
-- Name: sales_2026_12_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_12_sale_id_sale_date_idx1 ON public.sales_2026_12 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2026_12_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2026_12_srid_sale_date_idx ON public.sales_2026_12 USING btree (srid, sale_date);


--
-- Name: sales_2026_12_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2026_12_warehouse_name_idx ON public.sales_2026_12 USING btree (warehouse_name);


--
-- Name: sales_2027_01_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_01_brand_idx ON public.sales_2027_01 USING btree (brand);


--
-- Name: sales_2027_01_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_01_marketplace_id_sale_date_idx ON public.sales_2027_01 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_01_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_01_nm_id_idx ON public.sales_2027_01 USING btree (nm_id);


--
-- Name: sales_2027_01_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_01_product_id_sale_date_idx ON public.sales_2027_01 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_01_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_01_sale_date_idx ON public.sales_2027_01 USING brin (sale_date);


--
-- Name: sales_2027_01_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_01_sale_date_idx1 ON public.sales_2027_01 USING btree (sale_date);


--
-- Name: sales_2027_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_01_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_01 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_01_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_01_sale_id_sale_date_idx ON public.sales_2027_01 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_01_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_01_sale_id_sale_date_idx1 ON public.sales_2027_01 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_01_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_01_srid_sale_date_idx ON public.sales_2027_01 USING btree (srid, sale_date);


--
-- Name: sales_2027_01_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_01_warehouse_name_idx ON public.sales_2027_01 USING btree (warehouse_name);


--
-- Name: sales_2027_02_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_02_brand_idx ON public.sales_2027_02 USING btree (brand);


--
-- Name: sales_2027_02_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_02_marketplace_id_sale_date_idx ON public.sales_2027_02 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_02_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_02_nm_id_idx ON public.sales_2027_02 USING btree (nm_id);


--
-- Name: sales_2027_02_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_02_product_id_sale_date_idx ON public.sales_2027_02 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_02_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_02_sale_date_idx ON public.sales_2027_02 USING brin (sale_date);


--
-- Name: sales_2027_02_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_02_sale_date_idx1 ON public.sales_2027_02 USING btree (sale_date);


--
-- Name: sales_2027_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_02_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_02 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_02_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_02_sale_id_sale_date_idx ON public.sales_2027_02 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_02_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_02_sale_id_sale_date_idx1 ON public.sales_2027_02 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_02_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_02_srid_sale_date_idx ON public.sales_2027_02 USING btree (srid, sale_date);


--
-- Name: sales_2027_02_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_02_warehouse_name_idx ON public.sales_2027_02 USING btree (warehouse_name);


--
-- Name: sales_2027_03_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_03_brand_idx ON public.sales_2027_03 USING btree (brand);


--
-- Name: sales_2027_03_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_03_marketplace_id_sale_date_idx ON public.sales_2027_03 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_03_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_03_nm_id_idx ON public.sales_2027_03 USING btree (nm_id);


--
-- Name: sales_2027_03_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_03_product_id_sale_date_idx ON public.sales_2027_03 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_03_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_03_sale_date_idx ON public.sales_2027_03 USING brin (sale_date);


--
-- Name: sales_2027_03_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_03_sale_date_idx1 ON public.sales_2027_03 USING btree (sale_date);


--
-- Name: sales_2027_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_03_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_03 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_03_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_03_sale_id_sale_date_idx ON public.sales_2027_03 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_03_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_03_sale_id_sale_date_idx1 ON public.sales_2027_03 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_03_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_03_srid_sale_date_idx ON public.sales_2027_03 USING btree (srid, sale_date);


--
-- Name: sales_2027_03_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_03_warehouse_name_idx ON public.sales_2027_03 USING btree (warehouse_name);


--
-- Name: sales_2027_04_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_04_brand_idx ON public.sales_2027_04 USING btree (brand);


--
-- Name: sales_2027_04_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_04_marketplace_id_sale_date_idx ON public.sales_2027_04 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_04_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_04_nm_id_idx ON public.sales_2027_04 USING btree (nm_id);


--
-- Name: sales_2027_04_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_04_product_id_sale_date_idx ON public.sales_2027_04 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_04_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_04_sale_date_idx ON public.sales_2027_04 USING brin (sale_date);


--
-- Name: sales_2027_04_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_04_sale_date_idx1 ON public.sales_2027_04 USING btree (sale_date);


--
-- Name: sales_2027_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_04_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_04 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_04_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_04_sale_id_sale_date_idx ON public.sales_2027_04 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_04_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_04_sale_id_sale_date_idx1 ON public.sales_2027_04 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_04_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_04_srid_sale_date_idx ON public.sales_2027_04 USING btree (srid, sale_date);


--
-- Name: sales_2027_04_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_04_warehouse_name_idx ON public.sales_2027_04 USING btree (warehouse_name);


--
-- Name: sales_2027_05_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_05_brand_idx ON public.sales_2027_05 USING btree (brand);


--
-- Name: sales_2027_05_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_05_marketplace_id_sale_date_idx ON public.sales_2027_05 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_05_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_05_nm_id_idx ON public.sales_2027_05 USING btree (nm_id);


--
-- Name: sales_2027_05_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_05_product_id_sale_date_idx ON public.sales_2027_05 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_05_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_05_sale_date_idx ON public.sales_2027_05 USING brin (sale_date);


--
-- Name: sales_2027_05_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_05_sale_date_idx1 ON public.sales_2027_05 USING btree (sale_date);


--
-- Name: sales_2027_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_05_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_05 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_05_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_05_sale_id_sale_date_idx ON public.sales_2027_05 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_05_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_05_sale_id_sale_date_idx1 ON public.sales_2027_05 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_05_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_05_srid_sale_date_idx ON public.sales_2027_05 USING btree (srid, sale_date);


--
-- Name: sales_2027_05_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_05_warehouse_name_idx ON public.sales_2027_05 USING btree (warehouse_name);


--
-- Name: sales_2027_06_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_06_brand_idx ON public.sales_2027_06 USING btree (brand);


--
-- Name: sales_2027_06_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_06_marketplace_id_sale_date_idx ON public.sales_2027_06 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_06_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_06_nm_id_idx ON public.sales_2027_06 USING btree (nm_id);


--
-- Name: sales_2027_06_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_06_product_id_sale_date_idx ON public.sales_2027_06 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_06_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_06_sale_date_idx ON public.sales_2027_06 USING brin (sale_date);


--
-- Name: sales_2027_06_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_06_sale_date_idx1 ON public.sales_2027_06 USING btree (sale_date);


--
-- Name: sales_2027_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_06_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_06 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_06_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_06_sale_id_sale_date_idx ON public.sales_2027_06 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_06_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_06_sale_id_sale_date_idx1 ON public.sales_2027_06 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_06_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_06_srid_sale_date_idx ON public.sales_2027_06 USING btree (srid, sale_date);


--
-- Name: sales_2027_06_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_06_warehouse_name_idx ON public.sales_2027_06 USING btree (warehouse_name);


--
-- Name: sales_2027_07_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_07_brand_idx ON public.sales_2027_07 USING btree (brand);


--
-- Name: sales_2027_07_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_07_marketplace_id_sale_date_idx ON public.sales_2027_07 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_07_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_07_nm_id_idx ON public.sales_2027_07 USING btree (nm_id);


--
-- Name: sales_2027_07_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_07_product_id_sale_date_idx ON public.sales_2027_07 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_07_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_07_sale_date_idx ON public.sales_2027_07 USING brin (sale_date);


--
-- Name: sales_2027_07_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_07_sale_date_idx1 ON public.sales_2027_07 USING btree (sale_date);


--
-- Name: sales_2027_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_07_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_07 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_07_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_07_sale_id_sale_date_idx ON public.sales_2027_07 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_07_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_07_sale_id_sale_date_idx1 ON public.sales_2027_07 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_07_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_07_srid_sale_date_idx ON public.sales_2027_07 USING btree (srid, sale_date);


--
-- Name: sales_2027_07_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_07_warehouse_name_idx ON public.sales_2027_07 USING btree (warehouse_name);


--
-- Name: sales_2027_08_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_08_brand_idx ON public.sales_2027_08 USING btree (brand);


--
-- Name: sales_2027_08_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_08_marketplace_id_sale_date_idx ON public.sales_2027_08 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_08_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_08_nm_id_idx ON public.sales_2027_08 USING btree (nm_id);


--
-- Name: sales_2027_08_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_08_product_id_sale_date_idx ON public.sales_2027_08 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_08_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_08_sale_date_idx ON public.sales_2027_08 USING brin (sale_date);


--
-- Name: sales_2027_08_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_08_sale_date_idx1 ON public.sales_2027_08 USING btree (sale_date);


--
-- Name: sales_2027_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_08_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_08 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_08_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_08_sale_id_sale_date_idx ON public.sales_2027_08 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_08_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_08_sale_id_sale_date_idx1 ON public.sales_2027_08 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_08_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_08_srid_sale_date_idx ON public.sales_2027_08 USING btree (srid, sale_date);


--
-- Name: sales_2027_08_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_08_warehouse_name_idx ON public.sales_2027_08 USING btree (warehouse_name);


--
-- Name: sales_2027_09_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_09_brand_idx ON public.sales_2027_09 USING btree (brand);


--
-- Name: sales_2027_09_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_09_marketplace_id_sale_date_idx ON public.sales_2027_09 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_09_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_09_nm_id_idx ON public.sales_2027_09 USING btree (nm_id);


--
-- Name: sales_2027_09_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_09_product_id_sale_date_idx ON public.sales_2027_09 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_09_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_09_sale_date_idx ON public.sales_2027_09 USING brin (sale_date);


--
-- Name: sales_2027_09_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_09_sale_date_idx1 ON public.sales_2027_09 USING btree (sale_date);


--
-- Name: sales_2027_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_09_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_09 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_09_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_09_sale_id_sale_date_idx ON public.sales_2027_09 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_09_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_09_sale_id_sale_date_idx1 ON public.sales_2027_09 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_09_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_09_srid_sale_date_idx ON public.sales_2027_09 USING btree (srid, sale_date);


--
-- Name: sales_2027_09_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_09_warehouse_name_idx ON public.sales_2027_09 USING btree (warehouse_name);


--
-- Name: sales_2027_10_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_10_brand_idx ON public.sales_2027_10 USING btree (brand);


--
-- Name: sales_2027_10_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_10_marketplace_id_sale_date_idx ON public.sales_2027_10 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_10_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_10_nm_id_idx ON public.sales_2027_10 USING btree (nm_id);


--
-- Name: sales_2027_10_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_10_product_id_sale_date_idx ON public.sales_2027_10 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_10_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_10_sale_date_idx ON public.sales_2027_10 USING brin (sale_date);


--
-- Name: sales_2027_10_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_10_sale_date_idx1 ON public.sales_2027_10 USING btree (sale_date);


--
-- Name: sales_2027_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_10_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_10 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_10_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_10_sale_id_sale_date_idx ON public.sales_2027_10 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_10_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_10_sale_id_sale_date_idx1 ON public.sales_2027_10 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_10_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_10_srid_sale_date_idx ON public.sales_2027_10 USING btree (srid, sale_date);


--
-- Name: sales_2027_10_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_10_warehouse_name_idx ON public.sales_2027_10 USING btree (warehouse_name);


--
-- Name: sales_2027_11_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_11_brand_idx ON public.sales_2027_11 USING btree (brand);


--
-- Name: sales_2027_11_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_11_marketplace_id_sale_date_idx ON public.sales_2027_11 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_11_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_11_nm_id_idx ON public.sales_2027_11 USING btree (nm_id);


--
-- Name: sales_2027_11_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_11_product_id_sale_date_idx ON public.sales_2027_11 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_11_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_11_sale_date_idx ON public.sales_2027_11 USING brin (sale_date);


--
-- Name: sales_2027_11_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_11_sale_date_idx1 ON public.sales_2027_11 USING btree (sale_date);


--
-- Name: sales_2027_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_11_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_11 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_11_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_11_sale_id_sale_date_idx ON public.sales_2027_11 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_11_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_11_sale_id_sale_date_idx1 ON public.sales_2027_11 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_11_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_11_srid_sale_date_idx ON public.sales_2027_11 USING btree (srid, sale_date);


--
-- Name: sales_2027_11_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_11_warehouse_name_idx ON public.sales_2027_11 USING btree (warehouse_name);


--
-- Name: sales_2027_12_brand_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_12_brand_idx ON public.sales_2027_12 USING btree (brand);


--
-- Name: sales_2027_12_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_12_marketplace_id_sale_date_idx ON public.sales_2027_12 USING btree (marketplace_id, sale_date);


--
-- Name: sales_2027_12_nm_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_12_nm_id_idx ON public.sales_2027_12 USING btree (nm_id);


--
-- Name: sales_2027_12_product_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_12_product_id_sale_date_idx ON public.sales_2027_12 USING btree (product_id, sale_date DESC);


--
-- Name: sales_2027_12_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_12_sale_date_idx ON public.sales_2027_12 USING brin (sale_date);


--
-- Name: sales_2027_12_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_12_sale_date_idx1 ON public.sales_2027_12 USING btree (sale_date);


--
-- Name: sales_2027_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_12_sale_id_marketplace_id_sale_date_idx ON public.sales_2027_12 USING btree (sale_id, marketplace_id, sale_date);


--
-- Name: sales_2027_12_sale_id_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_12_sale_id_sale_date_idx ON public.sales_2027_12 USING btree (sale_id, sale_date);


--
-- Name: sales_2027_12_sale_id_sale_date_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_12_sale_id_sale_date_idx1 ON public.sales_2027_12 USING btree (sale_id, sale_date) WHERE (sale_id IS NOT NULL);


--
-- Name: sales_2027_12_srid_sale_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sales_2027_12_srid_sale_date_idx ON public.sales_2027_12 USING btree (srid, sale_date);


--
-- Name: sales_2027_12_warehouse_name_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sales_2027_12_warehouse_name_idx ON public.sales_2027_12 USING btree (warehouse_name);


--
-- Name: sales_2023_01_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_01_brand_idx;


--
-- Name: sales_2023_01_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_01_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_01_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_01_nm_id_idx;


--
-- Name: sales_2023_01_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_01_pkey;


--
-- Name: sales_2023_01_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_01_product_id_sale_date_idx;


--
-- Name: sales_2023_01_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_01_sale_date_idx;


--
-- Name: sales_2023_01_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_01_sale_date_idx1;


--
-- Name: sales_2023_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_01_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_01_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_01_sale_id_sale_date_idx;


--
-- Name: sales_2023_01_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_01_sale_id_sale_date_idx1;


--
-- Name: sales_2023_01_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_01_srid_sale_date_idx;


--
-- Name: sales_2023_01_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_01_warehouse_name_idx;


--
-- Name: sales_2023_02_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_02_brand_idx;


--
-- Name: sales_2023_02_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_02_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_02_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_02_nm_id_idx;


--
-- Name: sales_2023_02_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_02_pkey;


--
-- Name: sales_2023_02_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_02_product_id_sale_date_idx;


--
-- Name: sales_2023_02_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_02_sale_date_idx;


--
-- Name: sales_2023_02_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_02_sale_date_idx1;


--
-- Name: sales_2023_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_02_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_02_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_02_sale_id_sale_date_idx;


--
-- Name: sales_2023_02_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_02_sale_id_sale_date_idx1;


--
-- Name: sales_2023_02_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_02_srid_sale_date_idx;


--
-- Name: sales_2023_02_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_02_warehouse_name_idx;


--
-- Name: sales_2023_03_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_03_brand_idx;


--
-- Name: sales_2023_03_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_03_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_03_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_03_nm_id_idx;


--
-- Name: sales_2023_03_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_03_pkey;


--
-- Name: sales_2023_03_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_03_product_id_sale_date_idx;


--
-- Name: sales_2023_03_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_03_sale_date_idx;


--
-- Name: sales_2023_03_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_03_sale_date_idx1;


--
-- Name: sales_2023_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_03_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_03_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_03_sale_id_sale_date_idx;


--
-- Name: sales_2023_03_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_03_sale_id_sale_date_idx1;


--
-- Name: sales_2023_03_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_03_srid_sale_date_idx;


--
-- Name: sales_2023_03_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_03_warehouse_name_idx;


--
-- Name: sales_2023_04_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_04_brand_idx;


--
-- Name: sales_2023_04_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_04_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_04_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_04_nm_id_idx;


--
-- Name: sales_2023_04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_04_pkey;


--
-- Name: sales_2023_04_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_04_product_id_sale_date_idx;


--
-- Name: sales_2023_04_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_04_sale_date_idx;


--
-- Name: sales_2023_04_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_04_sale_date_idx1;


--
-- Name: sales_2023_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_04_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_04_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_04_sale_id_sale_date_idx;


--
-- Name: sales_2023_04_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_04_sale_id_sale_date_idx1;


--
-- Name: sales_2023_04_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_04_srid_sale_date_idx;


--
-- Name: sales_2023_04_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_04_warehouse_name_idx;


--
-- Name: sales_2023_05_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_05_brand_idx;


--
-- Name: sales_2023_05_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_05_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_05_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_05_nm_id_idx;


--
-- Name: sales_2023_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_05_pkey;


--
-- Name: sales_2023_05_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_05_product_id_sale_date_idx;


--
-- Name: sales_2023_05_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_05_sale_date_idx;


--
-- Name: sales_2023_05_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_05_sale_date_idx1;


--
-- Name: sales_2023_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_05_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_05_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_05_sale_id_sale_date_idx;


--
-- Name: sales_2023_05_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_05_sale_id_sale_date_idx1;


--
-- Name: sales_2023_05_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_05_srid_sale_date_idx;


--
-- Name: sales_2023_05_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_05_warehouse_name_idx;


--
-- Name: sales_2023_06_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_06_brand_idx;


--
-- Name: sales_2023_06_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_06_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_06_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_06_nm_id_idx;


--
-- Name: sales_2023_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_06_pkey;


--
-- Name: sales_2023_06_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_06_product_id_sale_date_idx;


--
-- Name: sales_2023_06_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_06_sale_date_idx;


--
-- Name: sales_2023_06_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_06_sale_date_idx1;


--
-- Name: sales_2023_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_06_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_06_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_06_sale_id_sale_date_idx;


--
-- Name: sales_2023_06_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_06_sale_id_sale_date_idx1;


--
-- Name: sales_2023_06_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_06_srid_sale_date_idx;


--
-- Name: sales_2023_06_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_06_warehouse_name_idx;


--
-- Name: sales_2023_07_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_07_brand_idx;


--
-- Name: sales_2023_07_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_07_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_07_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_07_nm_id_idx;


--
-- Name: sales_2023_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_07_pkey;


--
-- Name: sales_2023_07_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_07_product_id_sale_date_idx;


--
-- Name: sales_2023_07_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_07_sale_date_idx;


--
-- Name: sales_2023_07_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_07_sale_date_idx1;


--
-- Name: sales_2023_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_07_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_07_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_07_sale_id_sale_date_idx;


--
-- Name: sales_2023_07_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_07_sale_id_sale_date_idx1;


--
-- Name: sales_2023_07_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_07_srid_sale_date_idx;


--
-- Name: sales_2023_07_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_07_warehouse_name_idx;


--
-- Name: sales_2023_08_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_08_brand_idx;


--
-- Name: sales_2023_08_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_08_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_08_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_08_nm_id_idx;


--
-- Name: sales_2023_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_08_pkey;


--
-- Name: sales_2023_08_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_08_product_id_sale_date_idx;


--
-- Name: sales_2023_08_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_08_sale_date_idx;


--
-- Name: sales_2023_08_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_08_sale_date_idx1;


--
-- Name: sales_2023_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_08_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_08_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_08_sale_id_sale_date_idx;


--
-- Name: sales_2023_08_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_08_sale_id_sale_date_idx1;


--
-- Name: sales_2023_08_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_08_srid_sale_date_idx;


--
-- Name: sales_2023_08_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_08_warehouse_name_idx;


--
-- Name: sales_2023_09_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_09_brand_idx;


--
-- Name: sales_2023_09_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_09_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_09_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_09_nm_id_idx;


--
-- Name: sales_2023_09_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_09_pkey;


--
-- Name: sales_2023_09_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_09_product_id_sale_date_idx;


--
-- Name: sales_2023_09_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_09_sale_date_idx;


--
-- Name: sales_2023_09_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_09_sale_date_idx1;


--
-- Name: sales_2023_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_09_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_09_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_09_sale_id_sale_date_idx;


--
-- Name: sales_2023_09_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_09_sale_id_sale_date_idx1;


--
-- Name: sales_2023_09_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_09_srid_sale_date_idx;


--
-- Name: sales_2023_09_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_09_warehouse_name_idx;


--
-- Name: sales_2023_10_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_10_brand_idx;


--
-- Name: sales_2023_10_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_10_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_10_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_10_nm_id_idx;


--
-- Name: sales_2023_10_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_10_pkey;


--
-- Name: sales_2023_10_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_10_product_id_sale_date_idx;


--
-- Name: sales_2023_10_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_10_sale_date_idx;


--
-- Name: sales_2023_10_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_10_sale_date_idx1;


--
-- Name: sales_2023_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_10_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_10_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_10_sale_id_sale_date_idx;


--
-- Name: sales_2023_10_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_10_sale_id_sale_date_idx1;


--
-- Name: sales_2023_10_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_10_srid_sale_date_idx;


--
-- Name: sales_2023_10_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_10_warehouse_name_idx;


--
-- Name: sales_2023_11_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_11_brand_idx;


--
-- Name: sales_2023_11_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_11_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_11_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_11_nm_id_idx;


--
-- Name: sales_2023_11_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_11_pkey;


--
-- Name: sales_2023_11_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_11_product_id_sale_date_idx;


--
-- Name: sales_2023_11_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_11_sale_date_idx;


--
-- Name: sales_2023_11_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_11_sale_date_idx1;


--
-- Name: sales_2023_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_11_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_11_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_11_sale_id_sale_date_idx;


--
-- Name: sales_2023_11_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_11_sale_id_sale_date_idx1;


--
-- Name: sales_2023_11_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_11_srid_sale_date_idx;


--
-- Name: sales_2023_11_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_11_warehouse_name_idx;


--
-- Name: sales_2023_12_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2023_12_brand_idx;


--
-- Name: sales_2023_12_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2023_12_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_12_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2023_12_nm_id_idx;


--
-- Name: sales_2023_12_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2023_12_pkey;


--
-- Name: sales_2023_12_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2023_12_product_id_sale_date_idx;


--
-- Name: sales_2023_12_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2023_12_sale_date_idx;


--
-- Name: sales_2023_12_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2023_12_sale_date_idx1;


--
-- Name: sales_2023_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2023_12_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2023_12_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2023_12_sale_id_sale_date_idx;


--
-- Name: sales_2023_12_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2023_12_sale_id_sale_date_idx1;


--
-- Name: sales_2023_12_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2023_12_srid_sale_date_idx;


--
-- Name: sales_2023_12_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2023_12_warehouse_name_idx;


--
-- Name: sales_2024_01_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_01_brand_idx;


--
-- Name: sales_2024_01_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_01_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_01_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_01_nm_id_idx;


--
-- Name: sales_2024_01_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_01_pkey;


--
-- Name: sales_2024_01_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_01_product_id_sale_date_idx;


--
-- Name: sales_2024_01_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_01_sale_date_idx;


--
-- Name: sales_2024_01_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_01_sale_date_idx1;


--
-- Name: sales_2024_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_01_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_01_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_01_sale_id_sale_date_idx;


--
-- Name: sales_2024_01_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_01_sale_id_sale_date_idx1;


--
-- Name: sales_2024_01_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_01_srid_sale_date_idx;


--
-- Name: sales_2024_01_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_01_warehouse_name_idx;


--
-- Name: sales_2024_02_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_02_brand_idx;


--
-- Name: sales_2024_02_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_02_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_02_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_02_nm_id_idx;


--
-- Name: sales_2024_02_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_02_pkey;


--
-- Name: sales_2024_02_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_02_product_id_sale_date_idx;


--
-- Name: sales_2024_02_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_02_sale_date_idx;


--
-- Name: sales_2024_02_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_02_sale_date_idx1;


--
-- Name: sales_2024_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_02_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_02_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_02_sale_id_sale_date_idx;


--
-- Name: sales_2024_02_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_02_sale_id_sale_date_idx1;


--
-- Name: sales_2024_02_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_02_srid_sale_date_idx;


--
-- Name: sales_2024_02_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_02_warehouse_name_idx;


--
-- Name: sales_2024_03_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_03_brand_idx;


--
-- Name: sales_2024_03_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_03_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_03_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_03_nm_id_idx;


--
-- Name: sales_2024_03_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_03_pkey;


--
-- Name: sales_2024_03_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_03_product_id_sale_date_idx;


--
-- Name: sales_2024_03_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_03_sale_date_idx;


--
-- Name: sales_2024_03_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_03_sale_date_idx1;


--
-- Name: sales_2024_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_03_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_03_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_03_sale_id_sale_date_idx;


--
-- Name: sales_2024_03_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_03_sale_id_sale_date_idx1;


--
-- Name: sales_2024_03_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_03_srid_sale_date_idx;


--
-- Name: sales_2024_03_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_03_warehouse_name_idx;


--
-- Name: sales_2024_04_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_04_brand_idx;


--
-- Name: sales_2024_04_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_04_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_04_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_04_nm_id_idx;


--
-- Name: sales_2024_04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_04_pkey;


--
-- Name: sales_2024_04_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_04_product_id_sale_date_idx;


--
-- Name: sales_2024_04_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_04_sale_date_idx;


--
-- Name: sales_2024_04_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_04_sale_date_idx1;


--
-- Name: sales_2024_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_04_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_04_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_04_sale_id_sale_date_idx;


--
-- Name: sales_2024_04_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_04_sale_id_sale_date_idx1;


--
-- Name: sales_2024_04_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_04_srid_sale_date_idx;


--
-- Name: sales_2024_04_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_04_warehouse_name_idx;


--
-- Name: sales_2024_05_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_05_brand_idx;


--
-- Name: sales_2024_05_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_05_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_05_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_05_nm_id_idx;


--
-- Name: sales_2024_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_05_pkey;


--
-- Name: sales_2024_05_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_05_product_id_sale_date_idx;


--
-- Name: sales_2024_05_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_05_sale_date_idx;


--
-- Name: sales_2024_05_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_05_sale_date_idx1;


--
-- Name: sales_2024_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_05_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_05_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_05_sale_id_sale_date_idx;


--
-- Name: sales_2024_05_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_05_sale_id_sale_date_idx1;


--
-- Name: sales_2024_05_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_05_srid_sale_date_idx;


--
-- Name: sales_2024_05_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_05_warehouse_name_idx;


--
-- Name: sales_2024_06_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_06_brand_idx;


--
-- Name: sales_2024_06_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_06_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_06_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_06_nm_id_idx;


--
-- Name: sales_2024_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_06_pkey;


--
-- Name: sales_2024_06_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_06_product_id_sale_date_idx;


--
-- Name: sales_2024_06_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_06_sale_date_idx;


--
-- Name: sales_2024_06_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_06_sale_date_idx1;


--
-- Name: sales_2024_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_06_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_06_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_06_sale_id_sale_date_idx;


--
-- Name: sales_2024_06_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_06_sale_id_sale_date_idx1;


--
-- Name: sales_2024_06_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_06_srid_sale_date_idx;


--
-- Name: sales_2024_06_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_06_warehouse_name_idx;


--
-- Name: sales_2024_07_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_07_brand_idx;


--
-- Name: sales_2024_07_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_07_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_07_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_07_nm_id_idx;


--
-- Name: sales_2024_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_07_pkey;


--
-- Name: sales_2024_07_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_07_product_id_sale_date_idx;


--
-- Name: sales_2024_07_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_07_sale_date_idx;


--
-- Name: sales_2024_07_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_07_sale_date_idx1;


--
-- Name: sales_2024_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_07_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_07_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_07_sale_id_sale_date_idx;


--
-- Name: sales_2024_07_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_07_sale_id_sale_date_idx1;


--
-- Name: sales_2024_07_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_07_srid_sale_date_idx;


--
-- Name: sales_2024_07_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_07_warehouse_name_idx;


--
-- Name: sales_2024_08_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_08_brand_idx;


--
-- Name: sales_2024_08_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_08_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_08_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_08_nm_id_idx;


--
-- Name: sales_2024_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_08_pkey;


--
-- Name: sales_2024_08_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_08_product_id_sale_date_idx;


--
-- Name: sales_2024_08_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_08_sale_date_idx;


--
-- Name: sales_2024_08_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_08_sale_date_idx1;


--
-- Name: sales_2024_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_08_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_08_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_08_sale_id_sale_date_idx;


--
-- Name: sales_2024_08_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_08_sale_id_sale_date_idx1;


--
-- Name: sales_2024_08_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_08_srid_sale_date_idx;


--
-- Name: sales_2024_08_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_08_warehouse_name_idx;


--
-- Name: sales_2024_09_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_09_brand_idx;


--
-- Name: sales_2024_09_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_09_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_09_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_09_nm_id_idx;


--
-- Name: sales_2024_09_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_09_pkey;


--
-- Name: sales_2024_09_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_09_product_id_sale_date_idx;


--
-- Name: sales_2024_09_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_09_sale_date_idx;


--
-- Name: sales_2024_09_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_09_sale_date_idx1;


--
-- Name: sales_2024_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_09_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_09_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_09_sale_id_sale_date_idx;


--
-- Name: sales_2024_09_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_09_sale_id_sale_date_idx1;


--
-- Name: sales_2024_09_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_09_srid_sale_date_idx;


--
-- Name: sales_2024_09_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_09_warehouse_name_idx;


--
-- Name: sales_2024_10_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_10_brand_idx;


--
-- Name: sales_2024_10_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_10_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_10_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_10_nm_id_idx;


--
-- Name: sales_2024_10_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_10_pkey;


--
-- Name: sales_2024_10_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_10_product_id_sale_date_idx;


--
-- Name: sales_2024_10_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_10_sale_date_idx;


--
-- Name: sales_2024_10_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_10_sale_date_idx1;


--
-- Name: sales_2024_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_10_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_10_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_10_sale_id_sale_date_idx;


--
-- Name: sales_2024_10_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_10_sale_id_sale_date_idx1;


--
-- Name: sales_2024_10_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_10_srid_sale_date_idx;


--
-- Name: sales_2024_10_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_10_warehouse_name_idx;


--
-- Name: sales_2024_11_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_11_brand_idx;


--
-- Name: sales_2024_11_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_11_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_11_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_11_nm_id_idx;


--
-- Name: sales_2024_11_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_11_pkey;


--
-- Name: sales_2024_11_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_11_product_id_sale_date_idx;


--
-- Name: sales_2024_11_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_11_sale_date_idx;


--
-- Name: sales_2024_11_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_11_sale_date_idx1;


--
-- Name: sales_2024_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_11_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_11_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_11_sale_id_sale_date_idx;


--
-- Name: sales_2024_11_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_11_sale_id_sale_date_idx1;


--
-- Name: sales_2024_11_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_11_srid_sale_date_idx;


--
-- Name: sales_2024_11_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_11_warehouse_name_idx;


--
-- Name: sales_2024_12_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2024_12_brand_idx;


--
-- Name: sales_2024_12_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2024_12_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_12_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2024_12_nm_id_idx;


--
-- Name: sales_2024_12_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2024_12_pkey;


--
-- Name: sales_2024_12_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2024_12_product_id_sale_date_idx;


--
-- Name: sales_2024_12_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2024_12_sale_date_idx;


--
-- Name: sales_2024_12_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2024_12_sale_date_idx1;


--
-- Name: sales_2024_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2024_12_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2024_12_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2024_12_sale_id_sale_date_idx;


--
-- Name: sales_2024_12_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2024_12_sale_id_sale_date_idx1;


--
-- Name: sales_2024_12_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2024_12_srid_sale_date_idx;


--
-- Name: sales_2024_12_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2024_12_warehouse_name_idx;


--
-- Name: sales_2025_01_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_01_brand_idx;


--
-- Name: sales_2025_01_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_01_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_01_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_01_nm_id_idx;


--
-- Name: sales_2025_01_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_01_pkey;


--
-- Name: sales_2025_01_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_01_product_id_sale_date_idx;


--
-- Name: sales_2025_01_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_01_sale_date_idx;


--
-- Name: sales_2025_01_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_01_sale_date_idx1;


--
-- Name: sales_2025_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_01_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_01_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_01_sale_id_sale_date_idx;


--
-- Name: sales_2025_01_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_01_sale_id_sale_date_idx1;


--
-- Name: sales_2025_01_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_01_srid_sale_date_idx;


--
-- Name: sales_2025_01_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_01_warehouse_name_idx;


--
-- Name: sales_2025_02_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_02_brand_idx;


--
-- Name: sales_2025_02_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_02_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_02_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_02_nm_id_idx;


--
-- Name: sales_2025_02_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_02_pkey;


--
-- Name: sales_2025_02_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_02_product_id_sale_date_idx;


--
-- Name: sales_2025_02_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_02_sale_date_idx;


--
-- Name: sales_2025_02_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_02_sale_date_idx1;


--
-- Name: sales_2025_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_02_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_02_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_02_sale_id_sale_date_idx;


--
-- Name: sales_2025_02_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_02_sale_id_sale_date_idx1;


--
-- Name: sales_2025_02_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_02_srid_sale_date_idx;


--
-- Name: sales_2025_02_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_02_warehouse_name_idx;


--
-- Name: sales_2025_03_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_03_brand_idx;


--
-- Name: sales_2025_03_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_03_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_03_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_03_nm_id_idx;


--
-- Name: sales_2025_03_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_03_pkey;


--
-- Name: sales_2025_03_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_03_product_id_sale_date_idx;


--
-- Name: sales_2025_03_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_03_sale_date_idx;


--
-- Name: sales_2025_03_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_03_sale_date_idx1;


--
-- Name: sales_2025_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_03_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_03_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_03_sale_id_sale_date_idx;


--
-- Name: sales_2025_03_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_03_sale_id_sale_date_idx1;


--
-- Name: sales_2025_03_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_03_srid_sale_date_idx;


--
-- Name: sales_2025_03_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_03_warehouse_name_idx;


--
-- Name: sales_2025_04_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_04_brand_idx;


--
-- Name: sales_2025_04_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_04_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_04_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_04_nm_id_idx;


--
-- Name: sales_2025_04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_04_pkey;


--
-- Name: sales_2025_04_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_04_product_id_sale_date_idx;


--
-- Name: sales_2025_04_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_04_sale_date_idx;


--
-- Name: sales_2025_04_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_04_sale_date_idx1;


--
-- Name: sales_2025_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_04_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_04_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_04_sale_id_sale_date_idx;


--
-- Name: sales_2025_04_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_04_sale_id_sale_date_idx1;


--
-- Name: sales_2025_04_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_04_srid_sale_date_idx;


--
-- Name: sales_2025_04_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_04_warehouse_name_idx;


--
-- Name: sales_2025_05_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_05_brand_idx;


--
-- Name: sales_2025_05_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_05_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_05_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_05_nm_id_idx;


--
-- Name: sales_2025_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_05_pkey;


--
-- Name: sales_2025_05_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_05_product_id_sale_date_idx;


--
-- Name: sales_2025_05_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_05_sale_date_idx;


--
-- Name: sales_2025_05_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_05_sale_date_idx1;


--
-- Name: sales_2025_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_05_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_05_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_05_sale_id_sale_date_idx;


--
-- Name: sales_2025_05_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_05_sale_id_sale_date_idx1;


--
-- Name: sales_2025_05_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_05_srid_sale_date_idx;


--
-- Name: sales_2025_05_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_05_warehouse_name_idx;


--
-- Name: sales_2025_06_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_06_brand_idx;


--
-- Name: sales_2025_06_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_06_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_06_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_06_nm_id_idx;


--
-- Name: sales_2025_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_06_pkey;


--
-- Name: sales_2025_06_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_06_product_id_sale_date_idx;


--
-- Name: sales_2025_06_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_06_sale_date_idx;


--
-- Name: sales_2025_06_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_06_sale_date_idx1;


--
-- Name: sales_2025_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_06_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_06_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_06_sale_id_sale_date_idx;


--
-- Name: sales_2025_06_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_06_sale_id_sale_date_idx1;


--
-- Name: sales_2025_06_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_06_srid_sale_date_idx;


--
-- Name: sales_2025_06_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_06_warehouse_name_idx;


--
-- Name: sales_2025_07_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_07_brand_idx;


--
-- Name: sales_2025_07_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_07_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_07_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_07_nm_id_idx;


--
-- Name: sales_2025_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_07_pkey;


--
-- Name: sales_2025_07_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_07_product_id_sale_date_idx;


--
-- Name: sales_2025_07_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_07_sale_date_idx;


--
-- Name: sales_2025_07_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_07_sale_date_idx1;


--
-- Name: sales_2025_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_07_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_07_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_07_sale_id_sale_date_idx;


--
-- Name: sales_2025_07_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_07_sale_id_sale_date_idx1;


--
-- Name: sales_2025_07_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_07_srid_sale_date_idx;


--
-- Name: sales_2025_07_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_07_warehouse_name_idx;


--
-- Name: sales_2025_08_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_08_brand_idx;


--
-- Name: sales_2025_08_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_08_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_08_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_08_nm_id_idx;


--
-- Name: sales_2025_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_08_pkey;


--
-- Name: sales_2025_08_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_08_product_id_sale_date_idx;


--
-- Name: sales_2025_08_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_08_sale_date_idx;


--
-- Name: sales_2025_08_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_08_sale_date_idx1;


--
-- Name: sales_2025_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_08_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_08_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_08_sale_id_sale_date_idx;


--
-- Name: sales_2025_08_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_08_sale_id_sale_date_idx1;


--
-- Name: sales_2025_08_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_08_srid_sale_date_idx;


--
-- Name: sales_2025_08_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_08_warehouse_name_idx;


--
-- Name: sales_2025_09_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_09_brand_idx;


--
-- Name: sales_2025_09_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_09_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_09_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_09_nm_id_idx;


--
-- Name: sales_2025_09_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_09_pkey;


--
-- Name: sales_2025_09_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_09_product_id_sale_date_idx;


--
-- Name: sales_2025_09_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_09_sale_date_idx;


--
-- Name: sales_2025_09_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_09_sale_date_idx1;


--
-- Name: sales_2025_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_09_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_09_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_09_sale_id_sale_date_idx;


--
-- Name: sales_2025_09_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_09_sale_id_sale_date_idx1;


--
-- Name: sales_2025_09_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_09_srid_sale_date_idx;


--
-- Name: sales_2025_09_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_09_warehouse_name_idx;


--
-- Name: sales_2025_10_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_10_brand_idx;


--
-- Name: sales_2025_10_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_10_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_10_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_10_nm_id_idx;


--
-- Name: sales_2025_10_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_10_pkey;


--
-- Name: sales_2025_10_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_10_product_id_sale_date_idx;


--
-- Name: sales_2025_10_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_10_sale_date_idx;


--
-- Name: sales_2025_10_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_10_sale_date_idx1;


--
-- Name: sales_2025_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_10_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_10_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_10_sale_id_sale_date_idx;


--
-- Name: sales_2025_10_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_10_sale_id_sale_date_idx1;


--
-- Name: sales_2025_10_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_10_srid_sale_date_idx;


--
-- Name: sales_2025_10_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_10_warehouse_name_idx;


--
-- Name: sales_2025_11_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_11_brand_idx;


--
-- Name: sales_2025_11_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_11_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_11_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_11_nm_id_idx;


--
-- Name: sales_2025_11_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_11_pkey;


--
-- Name: sales_2025_11_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_11_product_id_sale_date_idx;


--
-- Name: sales_2025_11_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_11_sale_date_idx;


--
-- Name: sales_2025_11_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_11_sale_date_idx1;


--
-- Name: sales_2025_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_11_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_11_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_11_sale_id_sale_date_idx;


--
-- Name: sales_2025_11_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_11_sale_id_sale_date_idx1;


--
-- Name: sales_2025_11_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_11_srid_sale_date_idx;


--
-- Name: sales_2025_11_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_11_warehouse_name_idx;


--
-- Name: sales_2025_12_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2025_12_brand_idx;


--
-- Name: sales_2025_12_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2025_12_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_12_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2025_12_nm_id_idx;


--
-- Name: sales_2025_12_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2025_12_pkey;


--
-- Name: sales_2025_12_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2025_12_product_id_sale_date_idx;


--
-- Name: sales_2025_12_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2025_12_sale_date_idx;


--
-- Name: sales_2025_12_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2025_12_sale_date_idx1;


--
-- Name: sales_2025_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2025_12_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2025_12_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2025_12_sale_id_sale_date_idx;


--
-- Name: sales_2025_12_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2025_12_sale_id_sale_date_idx1;


--
-- Name: sales_2025_12_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2025_12_srid_sale_date_idx;


--
-- Name: sales_2025_12_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2025_12_warehouse_name_idx;


--
-- Name: sales_2026_01_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_01_brand_idx;


--
-- Name: sales_2026_01_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_01_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_01_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_01_nm_id_idx;


--
-- Name: sales_2026_01_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_01_pkey;


--
-- Name: sales_2026_01_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_01_product_id_sale_date_idx;


--
-- Name: sales_2026_01_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_01_sale_date_idx;


--
-- Name: sales_2026_01_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_01_sale_date_idx1;


--
-- Name: sales_2026_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_01_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_01_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_01_sale_id_sale_date_idx;


--
-- Name: sales_2026_01_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_01_sale_id_sale_date_idx1;


--
-- Name: sales_2026_01_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_01_srid_sale_date_idx;


--
-- Name: sales_2026_01_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_01_warehouse_name_idx;


--
-- Name: sales_2026_02_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_02_brand_idx;


--
-- Name: sales_2026_02_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_02_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_02_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_02_nm_id_idx;


--
-- Name: sales_2026_02_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_02_pkey;


--
-- Name: sales_2026_02_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_02_product_id_sale_date_idx;


--
-- Name: sales_2026_02_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_02_sale_date_idx;


--
-- Name: sales_2026_02_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_02_sale_date_idx1;


--
-- Name: sales_2026_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_02_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_02_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_02_sale_id_sale_date_idx;


--
-- Name: sales_2026_02_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_02_sale_id_sale_date_idx1;


--
-- Name: sales_2026_02_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_02_srid_sale_date_idx;


--
-- Name: sales_2026_02_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_02_warehouse_name_idx;


--
-- Name: sales_2026_03_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_03_brand_idx;


--
-- Name: sales_2026_03_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_03_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_03_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_03_nm_id_idx;


--
-- Name: sales_2026_03_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_03_pkey;


--
-- Name: sales_2026_03_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_03_product_id_sale_date_idx;


--
-- Name: sales_2026_03_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_03_sale_date_idx;


--
-- Name: sales_2026_03_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_03_sale_date_idx1;


--
-- Name: sales_2026_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_03_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_03_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_03_sale_id_sale_date_idx;


--
-- Name: sales_2026_03_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_03_sale_id_sale_date_idx1;


--
-- Name: sales_2026_03_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_03_srid_sale_date_idx;


--
-- Name: sales_2026_03_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_03_warehouse_name_idx;


--
-- Name: sales_2026_04_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_04_brand_idx;


--
-- Name: sales_2026_04_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_04_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_04_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_04_nm_id_idx;


--
-- Name: sales_2026_04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_04_pkey;


--
-- Name: sales_2026_04_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_04_product_id_sale_date_idx;


--
-- Name: sales_2026_04_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_04_sale_date_idx;


--
-- Name: sales_2026_04_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_04_sale_date_idx1;


--
-- Name: sales_2026_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_04_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_04_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_04_sale_id_sale_date_idx;


--
-- Name: sales_2026_04_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_04_sale_id_sale_date_idx1;


--
-- Name: sales_2026_04_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_04_srid_sale_date_idx;


--
-- Name: sales_2026_04_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_04_warehouse_name_idx;


--
-- Name: sales_2026_05_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_05_brand_idx;


--
-- Name: sales_2026_05_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_05_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_05_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_05_nm_id_idx;


--
-- Name: sales_2026_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_05_pkey;


--
-- Name: sales_2026_05_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_05_product_id_sale_date_idx;


--
-- Name: sales_2026_05_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_05_sale_date_idx;


--
-- Name: sales_2026_05_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_05_sale_date_idx1;


--
-- Name: sales_2026_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_05_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_05_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_05_sale_id_sale_date_idx;


--
-- Name: sales_2026_05_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_05_sale_id_sale_date_idx1;


--
-- Name: sales_2026_05_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_05_srid_sale_date_idx;


--
-- Name: sales_2026_05_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_05_warehouse_name_idx;


--
-- Name: sales_2026_06_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_06_brand_idx;


--
-- Name: sales_2026_06_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_06_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_06_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_06_nm_id_idx;


--
-- Name: sales_2026_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_06_pkey;


--
-- Name: sales_2026_06_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_06_product_id_sale_date_idx;


--
-- Name: sales_2026_06_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_06_sale_date_idx;


--
-- Name: sales_2026_06_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_06_sale_date_idx1;


--
-- Name: sales_2026_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_06_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_06_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_06_sale_id_sale_date_idx;


--
-- Name: sales_2026_06_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_06_sale_id_sale_date_idx1;


--
-- Name: sales_2026_06_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_06_srid_sale_date_idx;


--
-- Name: sales_2026_06_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_06_warehouse_name_idx;


--
-- Name: sales_2026_07_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_07_brand_idx;


--
-- Name: sales_2026_07_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_07_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_07_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_07_nm_id_idx;


--
-- Name: sales_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_07_pkey;


--
-- Name: sales_2026_07_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_07_product_id_sale_date_idx;


--
-- Name: sales_2026_07_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_07_sale_date_idx;


--
-- Name: sales_2026_07_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_07_sale_date_idx1;


--
-- Name: sales_2026_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_07_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_07_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_07_sale_id_sale_date_idx;


--
-- Name: sales_2026_07_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_07_sale_id_sale_date_idx1;


--
-- Name: sales_2026_07_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_07_srid_sale_date_idx;


--
-- Name: sales_2026_07_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_07_warehouse_name_idx;


--
-- Name: sales_2026_08_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_08_brand_idx;


--
-- Name: sales_2026_08_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_08_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_08_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_08_nm_id_idx;


--
-- Name: sales_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_08_pkey;


--
-- Name: sales_2026_08_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_08_product_id_sale_date_idx;


--
-- Name: sales_2026_08_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_08_sale_date_idx;


--
-- Name: sales_2026_08_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_08_sale_date_idx1;


--
-- Name: sales_2026_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_08_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_08_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_08_sale_id_sale_date_idx;


--
-- Name: sales_2026_08_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_08_sale_id_sale_date_idx1;


--
-- Name: sales_2026_08_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_08_srid_sale_date_idx;


--
-- Name: sales_2026_08_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_08_warehouse_name_idx;


--
-- Name: sales_2026_09_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_09_brand_idx;


--
-- Name: sales_2026_09_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_09_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_09_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_09_nm_id_idx;


--
-- Name: sales_2026_09_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_09_pkey;


--
-- Name: sales_2026_09_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_09_product_id_sale_date_idx;


--
-- Name: sales_2026_09_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_09_sale_date_idx;


--
-- Name: sales_2026_09_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_09_sale_date_idx1;


--
-- Name: sales_2026_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_09_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_09_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_09_sale_id_sale_date_idx;


--
-- Name: sales_2026_09_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_09_sale_id_sale_date_idx1;


--
-- Name: sales_2026_09_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_09_srid_sale_date_idx;


--
-- Name: sales_2026_09_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_09_warehouse_name_idx;


--
-- Name: sales_2026_10_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_10_brand_idx;


--
-- Name: sales_2026_10_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_10_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_10_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_10_nm_id_idx;


--
-- Name: sales_2026_10_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_10_pkey;


--
-- Name: sales_2026_10_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_10_product_id_sale_date_idx;


--
-- Name: sales_2026_10_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_10_sale_date_idx;


--
-- Name: sales_2026_10_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_10_sale_date_idx1;


--
-- Name: sales_2026_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_10_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_10_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_10_sale_id_sale_date_idx;


--
-- Name: sales_2026_10_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_10_sale_id_sale_date_idx1;


--
-- Name: sales_2026_10_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_10_srid_sale_date_idx;


--
-- Name: sales_2026_10_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_10_warehouse_name_idx;


--
-- Name: sales_2026_11_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_11_brand_idx;


--
-- Name: sales_2026_11_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_11_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_11_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_11_nm_id_idx;


--
-- Name: sales_2026_11_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_11_pkey;


--
-- Name: sales_2026_11_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_11_product_id_sale_date_idx;


--
-- Name: sales_2026_11_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_11_sale_date_idx;


--
-- Name: sales_2026_11_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_11_sale_date_idx1;


--
-- Name: sales_2026_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_11_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_11_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_11_sale_id_sale_date_idx;


--
-- Name: sales_2026_11_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_11_sale_id_sale_date_idx1;


--
-- Name: sales_2026_11_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_11_srid_sale_date_idx;


--
-- Name: sales_2026_11_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_11_warehouse_name_idx;


--
-- Name: sales_2026_12_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2026_12_brand_idx;


--
-- Name: sales_2026_12_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2026_12_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_12_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2026_12_nm_id_idx;


--
-- Name: sales_2026_12_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2026_12_pkey;


--
-- Name: sales_2026_12_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2026_12_product_id_sale_date_idx;


--
-- Name: sales_2026_12_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2026_12_sale_date_idx;


--
-- Name: sales_2026_12_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2026_12_sale_date_idx1;


--
-- Name: sales_2026_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2026_12_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2026_12_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2026_12_sale_id_sale_date_idx;


--
-- Name: sales_2026_12_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2026_12_sale_id_sale_date_idx1;


--
-- Name: sales_2026_12_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2026_12_srid_sale_date_idx;


--
-- Name: sales_2026_12_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2026_12_warehouse_name_idx;


--
-- Name: sales_2027_01_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_01_brand_idx;


--
-- Name: sales_2027_01_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_01_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_01_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_01_nm_id_idx;


--
-- Name: sales_2027_01_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_01_pkey;


--
-- Name: sales_2027_01_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_01_product_id_sale_date_idx;


--
-- Name: sales_2027_01_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_01_sale_date_idx;


--
-- Name: sales_2027_01_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_01_sale_date_idx1;


--
-- Name: sales_2027_01_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_01_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_01_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_01_sale_id_sale_date_idx;


--
-- Name: sales_2027_01_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_01_sale_id_sale_date_idx1;


--
-- Name: sales_2027_01_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_01_srid_sale_date_idx;


--
-- Name: sales_2027_01_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_01_warehouse_name_idx;


--
-- Name: sales_2027_02_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_02_brand_idx;


--
-- Name: sales_2027_02_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_02_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_02_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_02_nm_id_idx;


--
-- Name: sales_2027_02_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_02_pkey;


--
-- Name: sales_2027_02_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_02_product_id_sale_date_idx;


--
-- Name: sales_2027_02_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_02_sale_date_idx;


--
-- Name: sales_2027_02_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_02_sale_date_idx1;


--
-- Name: sales_2027_02_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_02_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_02_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_02_sale_id_sale_date_idx;


--
-- Name: sales_2027_02_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_02_sale_id_sale_date_idx1;


--
-- Name: sales_2027_02_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_02_srid_sale_date_idx;


--
-- Name: sales_2027_02_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_02_warehouse_name_idx;


--
-- Name: sales_2027_03_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_03_brand_idx;


--
-- Name: sales_2027_03_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_03_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_03_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_03_nm_id_idx;


--
-- Name: sales_2027_03_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_03_pkey;


--
-- Name: sales_2027_03_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_03_product_id_sale_date_idx;


--
-- Name: sales_2027_03_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_03_sale_date_idx;


--
-- Name: sales_2027_03_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_03_sale_date_idx1;


--
-- Name: sales_2027_03_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_03_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_03_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_03_sale_id_sale_date_idx;


--
-- Name: sales_2027_03_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_03_sale_id_sale_date_idx1;


--
-- Name: sales_2027_03_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_03_srid_sale_date_idx;


--
-- Name: sales_2027_03_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_03_warehouse_name_idx;


--
-- Name: sales_2027_04_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_04_brand_idx;


--
-- Name: sales_2027_04_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_04_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_04_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_04_nm_id_idx;


--
-- Name: sales_2027_04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_04_pkey;


--
-- Name: sales_2027_04_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_04_product_id_sale_date_idx;


--
-- Name: sales_2027_04_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_04_sale_date_idx;


--
-- Name: sales_2027_04_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_04_sale_date_idx1;


--
-- Name: sales_2027_04_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_04_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_04_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_04_sale_id_sale_date_idx;


--
-- Name: sales_2027_04_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_04_sale_id_sale_date_idx1;


--
-- Name: sales_2027_04_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_04_srid_sale_date_idx;


--
-- Name: sales_2027_04_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_04_warehouse_name_idx;


--
-- Name: sales_2027_05_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_05_brand_idx;


--
-- Name: sales_2027_05_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_05_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_05_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_05_nm_id_idx;


--
-- Name: sales_2027_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_05_pkey;


--
-- Name: sales_2027_05_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_05_product_id_sale_date_idx;


--
-- Name: sales_2027_05_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_05_sale_date_idx;


--
-- Name: sales_2027_05_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_05_sale_date_idx1;


--
-- Name: sales_2027_05_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_05_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_05_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_05_sale_id_sale_date_idx;


--
-- Name: sales_2027_05_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_05_sale_id_sale_date_idx1;


--
-- Name: sales_2027_05_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_05_srid_sale_date_idx;


--
-- Name: sales_2027_05_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_05_warehouse_name_idx;


--
-- Name: sales_2027_06_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_06_brand_idx;


--
-- Name: sales_2027_06_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_06_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_06_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_06_nm_id_idx;


--
-- Name: sales_2027_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_06_pkey;


--
-- Name: sales_2027_06_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_06_product_id_sale_date_idx;


--
-- Name: sales_2027_06_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_06_sale_date_idx;


--
-- Name: sales_2027_06_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_06_sale_date_idx1;


--
-- Name: sales_2027_06_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_06_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_06_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_06_sale_id_sale_date_idx;


--
-- Name: sales_2027_06_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_06_sale_id_sale_date_idx1;


--
-- Name: sales_2027_06_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_06_srid_sale_date_idx;


--
-- Name: sales_2027_06_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_06_warehouse_name_idx;


--
-- Name: sales_2027_07_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_07_brand_idx;


--
-- Name: sales_2027_07_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_07_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_07_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_07_nm_id_idx;


--
-- Name: sales_2027_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_07_pkey;


--
-- Name: sales_2027_07_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_07_product_id_sale_date_idx;


--
-- Name: sales_2027_07_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_07_sale_date_idx;


--
-- Name: sales_2027_07_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_07_sale_date_idx1;


--
-- Name: sales_2027_07_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_07_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_07_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_07_sale_id_sale_date_idx;


--
-- Name: sales_2027_07_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_07_sale_id_sale_date_idx1;


--
-- Name: sales_2027_07_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_07_srid_sale_date_idx;


--
-- Name: sales_2027_07_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_07_warehouse_name_idx;


--
-- Name: sales_2027_08_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_08_brand_idx;


--
-- Name: sales_2027_08_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_08_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_08_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_08_nm_id_idx;


--
-- Name: sales_2027_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_08_pkey;


--
-- Name: sales_2027_08_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_08_product_id_sale_date_idx;


--
-- Name: sales_2027_08_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_08_sale_date_idx;


--
-- Name: sales_2027_08_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_08_sale_date_idx1;


--
-- Name: sales_2027_08_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_08_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_08_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_08_sale_id_sale_date_idx;


--
-- Name: sales_2027_08_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_08_sale_id_sale_date_idx1;


--
-- Name: sales_2027_08_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_08_srid_sale_date_idx;


--
-- Name: sales_2027_08_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_08_warehouse_name_idx;


--
-- Name: sales_2027_09_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_09_brand_idx;


--
-- Name: sales_2027_09_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_09_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_09_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_09_nm_id_idx;


--
-- Name: sales_2027_09_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_09_pkey;


--
-- Name: sales_2027_09_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_09_product_id_sale_date_idx;


--
-- Name: sales_2027_09_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_09_sale_date_idx;


--
-- Name: sales_2027_09_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_09_sale_date_idx1;


--
-- Name: sales_2027_09_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_09_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_09_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_09_sale_id_sale_date_idx;


--
-- Name: sales_2027_09_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_09_sale_id_sale_date_idx1;


--
-- Name: sales_2027_09_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_09_srid_sale_date_idx;


--
-- Name: sales_2027_09_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_09_warehouse_name_idx;


--
-- Name: sales_2027_10_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_10_brand_idx;


--
-- Name: sales_2027_10_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_10_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_10_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_10_nm_id_idx;


--
-- Name: sales_2027_10_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_10_pkey;


--
-- Name: sales_2027_10_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_10_product_id_sale_date_idx;


--
-- Name: sales_2027_10_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_10_sale_date_idx;


--
-- Name: sales_2027_10_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_10_sale_date_idx1;


--
-- Name: sales_2027_10_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_10_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_10_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_10_sale_id_sale_date_idx;


--
-- Name: sales_2027_10_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_10_sale_id_sale_date_idx1;


--
-- Name: sales_2027_10_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_10_srid_sale_date_idx;


--
-- Name: sales_2027_10_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_10_warehouse_name_idx;


--
-- Name: sales_2027_11_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_11_brand_idx;


--
-- Name: sales_2027_11_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_11_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_11_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_11_nm_id_idx;


--
-- Name: sales_2027_11_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_11_pkey;


--
-- Name: sales_2027_11_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_11_product_id_sale_date_idx;


--
-- Name: sales_2027_11_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_11_sale_date_idx;


--
-- Name: sales_2027_11_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_11_sale_date_idx1;


--
-- Name: sales_2027_11_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_11_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_11_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_11_sale_id_sale_date_idx;


--
-- Name: sales_2027_11_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_11_sale_id_sale_date_idx1;


--
-- Name: sales_2027_11_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_11_srid_sale_date_idx;


--
-- Name: sales_2027_11_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_11_warehouse_name_idx;


--
-- Name: sales_2027_12_brand_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_brand_idx ATTACH PARTITION public.sales_2027_12_brand_idx;


--
-- Name: sales_2027_12_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_marketplace_date ATTACH PARTITION public.sales_2027_12_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_12_nm_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_nm_idx ATTACH PARTITION public.sales_2027_12_nm_id_idx;


--
-- Name: sales_2027_12_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_new_pkey ATTACH PARTITION public.sales_2027_12_pkey;


--
-- Name: sales_2027_12_product_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_product_date ATTACH PARTITION public.sales_2027_12_product_id_sale_date_idx;


--
-- Name: sales_2027_12_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_sales_brin_date ATTACH PARTITION public.sales_2027_12_sale_date_idx;


--
-- Name: sales_2027_12_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_date_idx ATTACH PARTITION public.sales_2027_12_sale_date_idx1;


--
-- Name: sales_2027_12_sale_id_marketplace_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_unique_idx ATTACH PARTITION public.sales_2027_12_sale_id_marketplace_id_sale_date_idx;


--
-- Name: sales_2027_12_sale_id_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_sale_id_date_uidx ATTACH PARTITION public.sales_2027_12_sale_id_sale_date_idx;


--
-- Name: sales_2027_12_sale_id_sale_date_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_saleid_date_uidx ATTACH PARTITION public.sales_2027_12_sale_id_sale_date_idx1;


--
-- Name: sales_2027_12_srid_sale_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_srid_date_uidx ATTACH PARTITION public.sales_2027_12_srid_sale_date_idx;


--
-- Name: sales_2027_12_warehouse_name_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.sales_wh_idx ATTACH PARTITION public.sales_2027_12_warehouse_name_idx;


--
-- Name: sales trg_sales_force_date; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sales_force_date BEFORE INSERT ON public.sales FOR EACH ROW EXECUTE FUNCTION public.sales_force_date();


--
-- Name: audit_log audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: categories categories_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: categories categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.categories(id);


--
-- Name: import_logs import_logs_imported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_logs
    ADD CONSTRAINT import_logs_imported_by_fkey FOREIGN KEY (imported_by) REFERENCES public.users(id);


--
-- Name: inventory inventory_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: inventory inventory_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: marketplace_credentials marketplace_credentials_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.marketplace_credentials
    ADD CONSTRAINT marketplace_credentials_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: orders orders_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: orders orders_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: product_categories product_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: product_mappings product_mappings_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: product_mappings product_mappings_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_mappings
    ADD CONSTRAINT product_mappings_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: returns returns_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: returns returns_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: returns returns_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.returns
    ADD CONSTRAINT returns_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: sync_jobs sync_jobs_marketplace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sync_jobs
    ADD CONSTRAINT sync_jobs_marketplace_id_fkey FOREIGN KEY (marketplace_id) REFERENCES public.marketplaces(id);


--
-- Name: user_departments user_departments_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_departments
    ADD CONSTRAINT user_departments_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE CASCADE;


--
-- Name: user_departments user_departments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_departments
    ADD CONSTRAINT user_departments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id);


--
-- PostgreSQL database dump complete
--

\unrestrict ebBjs7nHSbG3AGpl6GbXcIQH9oyeueoXNQmGdzuogJkln8oxZW1NcW7hO5eKGJM

