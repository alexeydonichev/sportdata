import pool from "@/lib/db";
import type {
  DashboardKPI,
  DashboardChanges,
  ChartDataPoint,
  MarketplaceStats,
  TopProduct,
} from "@/types/models";

// ============================================================
// Dashboard Repository — все SQL-запросы дашборда
// ============================================================

function pctChange(current: number, previous: number): number | null {
  if (previous === 0 && current === 0) return 0;
  if (previous === 0) return current > 0 ? 100 : -100;
  return parseFloat((((current - previous) / previous) * 100).toFixed(1));
}

/**
 * KPI + сравнение с предыдущим периодом
 */
export async function getKPI(days: number): Promise<{
  kpi: DashboardKPI;
  changes: DashboardChanges;
}> {
  const { rows } = await pool.query(
    `
    WITH current_period AS (
      SELECT
        COALESCE(SUM(revenue), 0)::float       AS total_revenue,
        COALESCE(SUM(net_profit), 0)::float     AS total_profit,
        COALESCE(SUM(quantity), 0)::int         AS total_quantity,
        COUNT(*)::int                           AS total_orders,
        COUNT(DISTINCT product_id)::int         AS total_sku,
        COALESCE(SUM(commission), 0)::float     AS total_commission,
        COALESCE(SUM(logistics_cost), 0)::float AS total_logistics,
        MIN(sale_date)::text                    AS date_from,
        MAX(sale_date)::text                    AS date_to
      FROM sales
      WHERE sale_date >= CURRENT_DATE - $1::int
    ),
    previous_period AS (
      SELECT
        COALESCE(SUM(revenue), 0)::float       AS total_revenue,
        COALESCE(SUM(net_profit), 0)::float     AS total_profit,
        COALESCE(SUM(quantity), 0)::int         AS total_quantity,
        COUNT(*)::int                           AS total_orders,
        COUNT(DISTINCT product_id)::int         AS total_sku,
        COALESCE(SUM(commission), 0)::float     AS total_commission,
        COALESCE(SUM(logistics_cost), 0)::float AS total_logistics
      FROM sales
      WHERE sale_date >= CURRENT_DATE - ($1::int * 2)
        AND sale_date <  CURRENT_DATE - $1::int
    )
    SELECT
      c.*,
      p.total_revenue    AS prev_revenue,
      p.total_profit     AS prev_profit,
      p.total_quantity   AS prev_quantity,
      p.total_orders     AS prev_orders,
      p.total_sku        AS prev_sku,
      p.total_commission AS prev_commission,
      p.total_logistics  AS prev_logistics
    FROM current_period c, previous_period p
    `,
    [days]
  );

  const m = rows[0];
  const avgOrder = m.total_orders > 0 ? m.total_revenue / m.total_orders : 0;
  const prevAvgOrder = m.prev_orders > 0 ? m.prev_revenue / m.prev_orders : 0;
  const marginPct =
    m.total_revenue > 0 ? (m.total_profit / m.total_revenue) * 100 : 0;
  const prevMarginPct =
    m.prev_revenue > 0 ? (m.prev_profit / m.prev_revenue) * 100 : 0;

  const kpi: DashboardKPI = {
    total_revenue: m.total_revenue,
    total_profit: m.total_profit,
    total_orders: m.total_orders,
    total_quantity: m.total_quantity,
    total_sku: m.total_sku,
    avg_order_value: parseFloat(avgOrder.toFixed(0)),
    profit_margin_pct: parseFloat(marginPct.toFixed(1)),
    total_commission: m.total_commission,
    total_logistics: m.total_logistics,
    date_from: m.date_from,
    date_to: m.date_to,
  };

  const changes: DashboardChanges = {
    revenue: pctChange(m.total_revenue, m.prev_revenue),
    profit: pctChange(m.total_profit, m.prev_profit),
    orders: pctChange(m.total_orders, m.prev_orders),
    quantity: pctChange(m.total_quantity, m.prev_quantity),
    avg_order: pctChange(avgOrder, prevAvgOrder),
    margin: pctChange(marginPct, prevMarginPct),
    commission: pctChange(m.total_commission, m.prev_commission),
    logistics: pctChange(m.total_logistics, m.prev_logistics),
  };

  return { kpi, changes };
}

/**
 * Данные для графика по дням
 */
export async function getChart(days: number): Promise<ChartDataPoint[]> {
  const { rows } = await pool.query(
    `
    SELECT
      sale_date::text                      AS date,
      COALESCE(SUM(revenue), 0)::float     AS revenue,
      COALESCE(SUM(net_profit), 0)::float  AS profit,
      COUNT(*)::int                        AS orders,
      COALESCE(SUM(quantity), 0)::int      AS quantity
    FROM sales
    WHERE sale_date >= CURRENT_DATE - $1::int
    GROUP BY sale_date
    ORDER BY sale_date
    `,
    [days]
  );
  return rows;
}

/**
 * Разбивка по маркетплейсам
 */
export async function getByMarketplace(
  days: number,
  totalRevenue: number
): Promise<MarketplaceStats[]> {
  const { rows } = await pool.query(
    `
    SELECT
      mp.slug                              AS marketplace,
      mp.name,
      COALESCE(SUM(s.revenue), 0)::float   AS revenue,
      COALESCE(SUM(s.net_profit), 0)::float AS profit,
      COALESCE(SUM(s.quantity), 0)::int    AS quantity
    FROM sales s
    JOIN marketplaces mp ON mp.id = s.marketplace_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int
    GROUP BY mp.slug, mp.name
    ORDER BY revenue DESC
    `,
    [days]
  );

  const total = totalRevenue || 1;
  return rows.map((r: Record<string, number | string>) => ({
    ...r,
    share_pct: parseFloat(((Number(r.revenue) / total) * 100).toFixed(1)),
  })) as MarketplaceStats[];
}

/**
 * Топ товаров по выручке
 */
export async function getTopProducts(
  days: number,
  limit = 10
): Promise<TopProduct[]> {
  const { rows } = await pool.query(
    `
    SELECT
      p.id::text                             AS product_id,
      p.name,
      p.sku,
      COALESCE(SUM(s.revenue), 0)::float     AS revenue,
      COALESCE(SUM(s.quantity), 0)::int      AS quantity,
      COALESCE(SUM(s.net_profit), 0)::float  AS profit
    FROM sales s
    JOIN products p ON p.id = s.product_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int
    GROUP BY p.id, p.name, p.sku
    ORDER BY revenue DESC
    LIMIT $2
    `,
    [days, limit]
  );
  return rows;
}
