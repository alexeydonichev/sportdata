import pool from "@/lib/db";
import type { DashboardKPI, DashboardChanges, ChartDataPoint, MarketplaceStats, TopProduct } from "@/types/models";

function pctChange(c: number, p: number): number | undefined {
  if (p === 0 && c === 0) return 0;
  if (p === 0) return c > 0 ? 100 : -100;
  return parseFloat((((c - p) / p) * 100).toFixed(1));
}

function buildFilters(days: number, category?: string, marketplace?: string) {
  const conds: string[] = [];
  const params: (string | number)[] = [days];
  let idx = 1;
  if (category && category !== "all") { idx++; conds.push(`c.slug = $${idx}`); params.push(category); }
  if (marketplace && marketplace !== "all") { idx++; conds.push(`mp.slug = $${idx}`); params.push(marketplace); }
  return { conds, params, idx };
}

export async function getKPI(days: number, category?: string, marketplace?: string): Promise<{ kpi: DashboardKPI; changes: DashboardChanges }> {
  const { conds, params } = buildFilters(days, category, marketplace);
  const joins = `JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id JOIN marketplaces mp ON mp.id=s.marketplace_id`;
  const w = conds.length ? " AND " + conds.join(" AND ") : "";

  const { rows } = await pool.query(`
    WITH cur AS (
      SELECT COALESCE(SUM(s.revenue),0)::float AS rev, COALESCE(SUM(s.net_profit),0)::float AS profit,
        COALESCE(SUM(s.quantity),0)::int AS qty, COUNT(*)::int AS orders, COUNT(DISTINCT s.product_id)::int AS sku,
        COALESCE(SUM(s.commission),0)::float AS comm, COALESCE(SUM(s.logistics_cost),0)::float AS logi,
        MIN(s.sale_date)::text AS d_from, MAX(s.sale_date)::text AS d_to
      FROM sales s ${joins} WHERE s.sale_date>=CURRENT_DATE-$1::int ${w}
    ), prev AS (
      SELECT COALESCE(SUM(s.revenue),0)::float AS rev, COALESCE(SUM(s.net_profit),0)::float AS profit,
        COALESCE(SUM(s.quantity),0)::int AS qty, COUNT(*)::int AS orders,
        COALESCE(SUM(s.commission),0)::float AS comm, COALESCE(SUM(s.logistics_cost),0)::float AS logi
      FROM sales s ${joins} WHERE s.sale_date>=CURRENT_DATE-($1::int*2) AND s.sale_date<CURRENT_DATE-$1::int ${w}
    ) SELECT cur.*, prev.rev AS p_rev, prev.profit AS p_profit, prev.qty AS p_qty,
        prev.orders AS p_orders, prev.comm AS p_comm, prev.logi AS p_logi FROM cur, prev
  `, params);

  const { rows: rr } = await pool.query(`
    SELECT COALESCE(SUM(CASE WHEN return_date>=CURRENT_DATE-$1::int THEN quantity ELSE 0 END),0)::int AS cr,
      COALESCE(SUM(CASE WHEN return_date<CURRENT_DATE-$1::int THEN quantity ELSE 0 END),0)::int AS pr,
      COUNT(CASE WHEN return_date>=CURRENT_DATE-$1::int THEN 1 END)::int AS crc,
      COUNT(CASE WHEN return_date<CURRENT_DATE-$1::int THEN 1 END)::int AS prc,
      COALESCE(SUM(CASE WHEN return_date>=CURRENT_DATE-$1::int THEN penalty ELSE 0 END),0)::float AS cp,
      COALESCE(SUM(CASE WHEN return_date<CURRENT_DATE-$1::int THEN penalty ELSE 0 END),0)::float AS pp
    FROM returns WHERE return_date>=CURRENT_DATE-($1::int*2)
  `, [days]);

  const m = rows[0]; const ret = rr[0];
  const avgOrd = m.orders > 0 ? m.rev / m.orders : 0;
  const pAvgOrd = m.p_orders > 0 ? m.p_rev / m.p_orders : 0;
  const mg = m.rev > 0 ? (m.profit / m.rev) * 100 : 0;
  const pmg = m.p_rev > 0 ? (m.p_profit / m.p_rev) * 100 : 0;

  return {
    kpi: { total_revenue: m.rev, total_profit: m.profit, total_orders: m.orders, total_quantity: m.qty,
      total_sku: m.sku, avg_order_value: +avgOrd.toFixed(0), profit_margin_pct: +mg.toFixed(1),
      total_commission: m.comm, total_logistics: m.logi, total_penalty: ret.cp,
      total_returns: ret.crc, total_returns_quantity: ret.cr, date_from: m.d_from, date_to: m.d_to },
    changes: { revenue: pctChange(m.rev, m.p_rev), profit: pctChange(m.profit, m.p_profit),
      orders: pctChange(m.orders, m.p_orders), quantity: pctChange(m.qty, m.p_qty),
      avg_order: pctChange(avgOrd, pAvgOrd), margin: pctChange(mg, pmg),
      commission: pctChange(m.comm, m.p_comm), logistics: pctChange(m.logi, m.p_logi),
      penalty: pctChange(ret.cp, ret.pp), returns: pctChange(ret.crc, ret.prc) }
  };
}

export async function getChart(days: number, category?: string, marketplace?: string): Promise<ChartDataPoint[]> {
  const { conds, params } = buildFilters(days, category, marketplace);
  const w = conds.length ? " AND " + conds.join(" AND ") : "";
  const j = (category || marketplace) ? `JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id JOIN marketplaces mp ON mp.id=s.marketplace_id` : "";
  const { rows } = await pool.query(`
    SELECT s.sale_date::text AS date, COALESCE(SUM(s.revenue),0)::float AS revenue,
      COALESCE(SUM(s.net_profit),0)::float AS profit, COUNT(*)::int AS orders,
      COALESCE(SUM(s.quantity),0)::int AS quantity
    FROM sales s ${j} WHERE s.sale_date>=CURRENT_DATE-$1::int ${w}
    GROUP BY s.sale_date ORDER BY s.sale_date
  `, params);
  return rows;
}

export async function getByMarketplace(days: number, totalRevenue: number, category?: string): Promise<MarketplaceStats[]> {
  const params: (string|number)[] = [days]; const conds: string[] = [];
  if (category && category !== "all") { params.push(category); conds.push(`c.slug=$${params.length}`); }
  const w = conds.length ? " AND " + conds.join(" AND ") : "";
  const cj = category ? "JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id" : "";
  const { rows } = await pool.query(`
    SELECT mp.slug AS marketplace, mp.name, COALESCE(SUM(s.revenue),0)::float AS revenue,
      COALESCE(SUM(s.net_profit),0)::float AS profit, COALESCE(SUM(s.quantity),0)::int AS quantity
    FROM sales s JOIN marketplaces mp ON mp.id=s.marketplace_id ${cj}
    WHERE s.sale_date>=CURRENT_DATE-$1::int ${w} GROUP BY mp.slug,mp.name ORDER BY revenue DESC
  `, params);
  const t = totalRevenue || 1;
  return rows.map((r: Record<string,number|string>) => ({ ...r, share_pct: +((Number(r.revenue)/t)*100).toFixed(1) })) as MarketplaceStats[];
}

export async function getTopProducts(days: number, limit=10, category?: string, marketplace?: string): Promise<TopProduct[]> {
  const params: (string|number)[] = [days]; const conds: string[] = []; let idx=1;
  if (category && category !== "all") { idx++; conds.push(`c.slug=$${idx}`); params.push(category); }
  if (marketplace && marketplace !== "all") { idx++; conds.push(`mp.slug=$${idx}`); params.push(marketplace); }
  idx++; params.push(limit);
  const w = conds.length ? " AND " + conds.join(" AND ") : "";
  const { rows } = await pool.query(`
    SELECT p.id::text AS product_id, p.name, p.sku, COALESCE(SUM(s.revenue),0)::float AS revenue,
      COALESCE(SUM(s.quantity),0)::int AS quantity, COALESCE(SUM(s.net_profit),0)::float AS profit
    FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id
      JOIN marketplaces mp ON mp.id=s.marketplace_id
    WHERE s.sale_date>=CURRENT_DATE-$1::int ${w}
    GROUP BY p.id,p.name,p.sku ORDER BY revenue DESC LIMIT $${idx}
  `, params);
  return rows;
}
