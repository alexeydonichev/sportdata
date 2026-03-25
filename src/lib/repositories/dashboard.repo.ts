import pool from "@/lib/db";
import type {
  DashboardKPI,
  DashboardChanges,
  ChartDataPoint,
  MarketplaceStats,
  TopProduct,
} from "@/types/models";

function pctChange(current: number, previous: number): number | null {
  if (previous === 0 && current === 0) return 0;
  if (previous === 0) return current > 0 ? 100 : -100;
  return parseFloat((((current - previous) / previous) * 100).toFixed(1));
}

interface DashboardFilters {
  days: number;
  category?: string;
  marketplace?: string;
}

function buildFilters(
  filters: DashboardFilters,
  startIdx = 1
): { conditions: string[]; params: (string | number)[]; idx: number } {
  const conditions: string[] = [];
  const params: (string | number)[] = [];
  let idx = startIdx - 1;

  idx++;
  params.push(filters.days);

  if (filters.category && filters.category !== "all") {
    idx++;
    conditions.push(`c.slug = $${idx}`);
    params.push(filters.category);
  }

  if (filters.marketplace && filters.marketplace !== "all") {
    idx++;
    conditions.push(`mp.slug = $${idx}`);
    params.push(filters.marketplace);
  }

  return { conditions, params, idx };
}

/**
 * KPI + comparison with previous period
 * 
 * HONEST METRICS:
 * - revenue = finishedPrice from WB (real sale price)
 * - for_pay = what WB pays to seller (real)
 * - commission = revenue - for_pay (real WB commission)
 * - logistics_cost = 0 (WB sales API doesn't provide per-sale logistics)
 * - net_profit = for_pay - (cost_price * quantity)
 *   If cost_price = 0 (not filled), net_profit = for_pay
 */
export async function getKPI(
  days: number,
  category?: string,
  marketplace?: string
): Promise<{
  kpi: DashboardKPI;
  changes: DashboardChanges;
}> {
  const f = buildFilters({ days, category, marketplace });
  const catMpJoin = `
    JOIN products p ON p.id = s.product_id
    JOIN categories c ON c.id = p.category_id
    JOIN marketplaces mp ON mp.id = s.marketplace_id
  `;
  const extraWhere =
    f.conditions.length > 0 ? " AND " + f.conditions.join(" AND ") : "";

  const { rows } = await pool.query(
    `
    WITH current_period AS (
      SELECT
        COALESCE(SUM(s.revenue), 0)::float                          AS total_revenue,
        COALESCE(SUM((s.revenue - s.commission - s.logistics_cost)), 0)::float                          AS total_for_pay,
        COALESCE(SUM(s.net_profit), 0)::float AS total_profit,
        COALESCE(SUM(s.quantity), 0)::int                            AS total_quantity,
        COUNT(*)::int                                                AS total_orders,
        COUNT(DISTINCT s.product_id)::int                            AS total_sku,
        COALESCE(SUM(s.commission + s.logistics_cost), 0)::float               AS total_commission,
        COALESCE(SUM(s.logistics_cost), 0)::float                    AS total_logistics,
        COALESCE(SUM(s.penalty), 0)::float                         AS total_penalty,
        COALESCE(SUM(COALESCE(p.cost_price, 0) * s.quantity), 0)::float AS total_cogs,
        MIN(s.sale_date)::text                                       AS date_from,
        MAX(s.sale_date)::text                                       AS date_to
      FROM sales s
      ${catMpJoin}
      WHERE s.sale_date >= CURRENT_DATE - $1::int
      ${extraWhere}
    ),
    previous_period AS (
      SELECT
        COALESCE(SUM(s.revenue), 0)::float                          AS total_revenue,
        COALESCE(SUM((s.revenue - s.commission - s.logistics_cost)), 0)::float                          AS total_for_pay,
        COALESCE(SUM(s.net_profit), 0)::float AS total_profit,
        COALESCE(SUM(s.quantity), 0)::int                            AS total_quantity,
        COUNT(*)::int                                                AS total_orders,
        COUNT(DISTINCT s.product_id)::int                            AS total_sku,
        COALESCE(SUM(s.commission + s.logistics_cost), 0)::float               AS total_commission,
        COALESCE(SUM(s.logistics_cost), 0)::float                    AS total_logistics,
        COALESCE(SUM(s.penalty), 0)::float                         AS total_penalty
      FROM sales s
      ${catMpJoin}
      WHERE s.sale_date >= CURRENT_DATE - ($1::int * 2)
        AND s.sale_date <  CURRENT_DATE - $1::int
      ${extraWhere}
    )
    SELECT
      c.*,
      p.total_revenue    AS prev_revenue,
      p.total_for_pay    AS prev_for_pay,
      p.total_profit     AS prev_profit,
      p.total_quantity   AS prev_quantity,
      p.total_orders     AS prev_orders,
      p.total_sku        AS prev_sku,
      p.total_commission AS prev_commission,
      p.total_logistics  AS prev_logistics,
      p.total_penalty    AS prev_penalty
    FROM current_period c, previous_period p
    `,
    f.params
  );

  
  // Get returns for current and previous period
  const { rows: retRows } = await pool.query(`
    SELECT
      COALESCE(SUM(CASE WHEN r.return_date >= CURRENT_DATE - \$1::int THEN r.quantity ELSE 0 END), 0)::int AS cur_returns,
      COALESCE(SUM(CASE WHEN r.return_date < CURRENT_DATE - \$1::int THEN r.quantity ELSE 0 END), 0)::int AS prev_returns,
      COUNT(CASE WHEN r.return_date >= CURRENT_DATE - \$1::int THEN 1 END)::int AS cur_returns_count,
      COUNT(CASE WHEN r.return_date < CURRENT_DATE - \$1::int THEN 1 END)::int AS prev_returns_count
    FROM returns r
    WHERE r.return_date >= CURRENT_DATE - (\$1::int * 2)
  `, [days]);
  const ret = retRows[0];
  const m = rows[0];
  const avgOrder = m.total_orders > 0 ? m.total_revenue / m.total_orders : 0;
  const prevAvgOrder = m.prev_orders > 0 ? m.prev_revenue / m.prev_orders : 0;
  
  // Margin based on real profit (for_pay - cogs) / revenue
  const marginPct = m.total_revenue > 0 ? (m.total_profit / m.total_revenue) * 100 : 0;
  const prevMarginPct = m.prev_revenue > 0 ? (m.prev_profit / m.prev_revenue) * 100 : 0;

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
    total_penalty: m.total_penalty,
    total_returns: ret.cur_returns_count,
    total_returns_quantity: ret.cur_returns,
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
    penalty: pctChange(m.total_penalty, m.prev_penalty),
    returns: pctChange(ret.cur_returns_count, ret.prev_returns_count),
  };

  return { kpi, changes };
}

/**
 * Chart data by day
 */
export async function getChart(
  days: number,
  category?: string,
  marketplace?: string
): Promise<ChartDataPoint[]> {
  const f = buildFilters({ days, category, marketplace });
  const extraWhere =
    f.conditions.length > 0 ? " AND " + f.conditions.join(" AND ") : "";

  const needsJoin = !!(category || marketplace);
  const joins = needsJoin
    ? `JOIN products p ON p.id = s.product_id
       JOIN categories c ON c.id = p.category_id
       JOIN marketplaces mp ON mp.id = s.marketplace_id`
    : "";

  const { rows } = await pool.query(
    `
    SELECT
      s.sale_date::text                      AS date,
      COALESCE(SUM(s.revenue), 0)::float     AS revenue,
      COALESCE(SUM((s.revenue - s.commission - s.logistics_cost)), 0)::float     AS profit,
      COUNT(*)::int                          AS orders,
      COALESCE(SUM(s.quantity), 0)::int      AS quantity
    FROM sales s
    ${joins}
    WHERE s.sale_date >= CURRENT_DATE - $1::int
    ${extraWhere}
    GROUP BY s.sale_date
    ORDER BY s.sale_date
    `,
    f.params
  );
  return rows;
}

/**
 * Breakdown by marketplace
 */
export async function getByMarketplace(
  days: number,
  totalRevenue: number,
  category?: string
): Promise<MarketplaceStats[]> {
  const conditions: string[] = [];
  const params: (string | number)[] = [days];
  let idx = 1;

  if (category && category !== "all") {
    idx++;
    conditions.push(`c.slug = $${idx}`);
    params.push(category);
  }

  const extraWhere =
    conditions.length > 0 ? " AND " + conditions.join(" AND ") : "";
  const needsCatJoin = !!(category && category !== "all");

  const { rows } = await pool.query(
    `
    SELECT
      mp.slug                              AS marketplace,
      mp.name,
      COALESCE(SUM(s.revenue), 0)::float   AS revenue,
      COALESCE(SUM((s.revenue - s.commission - s.logistics_cost)), 0)::float   AS profit,
      COALESCE(SUM(s.quantity), 0)::int    AS quantity
    FROM sales s
    JOIN marketplaces mp ON mp.id = s.marketplace_id
    ${needsCatJoin ? "JOIN products p ON p.id = s.product_id JOIN categories c ON c.id = p.category_id" : ""}
    WHERE s.sale_date >= CURRENT_DATE - $1::int
    ${extraWhere}
    GROUP BY mp.slug, mp.name
    ORDER BY revenue DESC
    `,
    params
  );

  const total = totalRevenue || 1;
  return rows.map((r: Record<string, number | string>) => ({
    ...r,
    share_pct: parseFloat(((Number(r.revenue) / total) * 100).toFixed(1)),
  })) as MarketplaceStats[];
}

/**
 * Top products by revenue
 */
export async function getTopProducts(
  days: number,
  limit = 10,
  category?: string,
  marketplace?: string
): Promise<TopProduct[]> {
  const conditions: string[] = [];
  const params: (string | number)[] = [days];
  let idx = 1;

  if (category && category !== "all") {
    idx++;
    conditions.push(`c.slug = $${idx}`);
    params.push(category);
  }

  if (marketplace && marketplace !== "all") {
    idx++;
    conditions.push(`mp.slug = $${idx}`);
    params.push(marketplace);
  }

  idx++;
  params.push(limit);

  const extraWhere =
    conditions.length > 0 ? " AND " + conditions.join(" AND ") : "";

  const { rows } = await pool.query(
    `
    SELECT
      p.id::text                             AS product_id,
      p.name,
      p.sku,
      COALESCE(SUM(s.revenue), 0)::float     AS revenue,
      COALESCE(SUM(s.quantity), 0)::int      AS quantity,
      COALESCE(SUM((s.revenue - s.commission - s.logistics_cost)), 0)::float     AS profit
    FROM sales s
    JOIN products p ON p.id = s.product_id
    JOIN categories c ON c.id = p.category_id
    JOIN marketplaces mp ON mp.id = s.marketplace_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int
    ${extraWhere}
    GROUP BY p.id, p.name, p.sku
    ORDER BY revenue DESC
    LIMIT $${idx}
    `,
    params
  );
  return rows;
}
