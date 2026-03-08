import pool from "@/lib/db";

export interface PnLData {
  pnl: {
    gross_revenue: number;
    returns_amount: number;
    net_revenue: number;
    cogs: number;
    gross_profit: number;
    commission: number;
    logistics: number;
    operating_expenses: number;
    operating_profit: number;
    advertising: number;
    net_profit: number;
  };
  margins: {
    gross_margin: number;
    operating_margin: number;
    net_margin: number;
    return_rate: number;
  };
  metrics: {
    units_sold: number;
    units_returned: number;
    active_skus: number;
    avg_check: number;
    avg_profit_per_unit: number;
  };
  changes: Record<string, number>;
  daily: { date: string; revenue: number; returns: number; commission: number; logistics: number; profit: number }[];
  by_category: { category: string; slug: string; revenue: number; commission: number; logistics: number; cogs: number; profit: number; units: number }[];
}

function pctChange(cur: number, prev: number): number {
  if (prev === 0 && cur === 0) return 0;
  if (prev === 0) return cur > 0 ? 100 : -100;
  return parseFloat((((cur - prev) / Math.abs(prev)) * 100).toFixed(1));
}

export async function getPnL(days: number, categorySlug?: string): Promise<PnLData> {
  const params: (number | string)[] = [days];
  let catFilter = "";
  if (categorySlug) {
    params.push(categorySlug);
    catFilter = "AND c.slug = $2";
  }

  const pnlRes = await pool.query(`
    WITH filtered_sales AS (
      SELECT s.*
      FROM sales s
      JOIN products p ON p.id = s.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE s.sale_date >= CURRENT_DATE - $1::int
      ${catFilter}
    ),
    current_agg AS (
      SELECT
        COALESCE(SUM(CASE WHEN quantity > 0 THEN revenue ELSE 0 END), 0)::float AS gross_revenue,
        COALESCE(SUM(CASE WHEN quantity < 0 THEN ABS(revenue) ELSE 0 END), 0)::float AS returns_amount,
        COALESCE(SUM(revenue), 0)::float AS net_revenue,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN commission ELSE 0 END), 0)::float AS commission,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN logistics_cost ELSE 0 END), 0)::float AS logistics,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END), 0)::int AS units_sold,
        COALESCE(SUM(CASE WHEN quantity < 0 THEN ABS(quantity) ELSE 0 END), 0)::int AS units_returned,
        COUNT(DISTINCT CASE WHEN quantity > 0 THEN product_id END)::int AS active_skus,
        COALESCE(SUM(net_profit), 0)::float AS net_profit
      FROM filtered_sales
    ),
    prev_sales AS (
      SELECT s.*
      FROM sales s
      JOIN products p ON p.id = s.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE s.sale_date >= CURRENT_DATE - ($1::int * 2)
        AND s.sale_date < CURRENT_DATE - $1::int
      ${catFilter}
    ),
    prev_agg AS (
      SELECT
        COALESCE(SUM(CASE WHEN quantity > 0 THEN revenue ELSE 0 END), 0)::float AS gross_revenue,
        COALESCE(SUM(revenue), 0)::float AS net_revenue,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN commission ELSE 0 END), 0)::float AS commission,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN logistics_cost ELSE 0 END), 0)::float AS logistics,
        COALESCE(SUM(net_profit), 0)::float AS net_profit
      FROM prev_sales
    )
    SELECT c.*, p.gross_revenue AS prev_gross_revenue, p.net_revenue AS prev_net_revenue,
      p.commission AS prev_commission, p.logistics AS prev_logistics, p.net_profit AS prev_net_profit
    FROM current_agg c, prev_agg p
  `, params);

  const m = pnlRes.rows[0];

  const cogsRes = await pool.query(`
    SELECT COALESCE(SUM(p.cost_price * s.quantity), 0)::float AS cogs
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int AND s.quantity > 0
    ${catFilter}
  `, params);
  const cogs = cogsRes.rows[0].cogs;

  const prevCogsRes = await pool.query(`
    SELECT COALESCE(SUM(p.cost_price * s.quantity), 0)::float AS cogs
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - ($1::int * 2)
      AND s.sale_date < CURRENT_DATE - $1::int AND s.quantity > 0
    ${catFilter}
  `, params);
  const prevCogs = prevCogsRes.rows[0].cogs;

  const dailyRes = await pool.query(`
    SELECT s.sale_date::text AS date,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS returns,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.commission ELSE 0 END), 0)::float AS commission,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.logistics_cost ELSE 0 END), 0)::float AS logistics,
      COALESCE(SUM(s.net_profit), 0)::float AS profit
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter}
    GROUP BY s.sale_date ORDER BY s.sale_date
  `, params);

  const byCatRes = await pool.query(`
    SELECT COALESCE(c.name, 'Without category') AS category, COALESCE(c.slug, 'none') AS slug,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.commission ELSE 0 END), 0)::float AS commission,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.logistics_cost ELSE 0 END), 0)::float AS logistics,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN p.cost_price * s.quantity ELSE 0 END), 0)::float AS cogs,
      COALESCE(SUM(s.net_profit), 0)::float AS profit,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS units
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter}
    GROUP BY c.name, c.slug ORDER BY revenue DESC
  `, params);

  const grossProfit = m.net_revenue - cogs;
  const operatingProfit = grossProfit - m.commission - m.logistics;
  const grossMargin = m.gross_revenue > 0 ? (grossProfit / m.gross_revenue) * 100 : 0;
  const operatingMargin = m.gross_revenue > 0 ? (operatingProfit / m.gross_revenue) * 100 : 0;
  const netMargin = m.gross_revenue > 0 ? (m.net_profit / m.gross_revenue) * 100 : 0;
  const returnRate = m.units_sold > 0 ? (m.units_returned / (m.units_sold + m.units_returned)) * 100 : 0;
  const avgCheck = m.units_sold > 0 ? m.gross_revenue / m.units_sold : 0;
  const avgProfit = m.units_sold > 0 ? m.net_profit / m.units_sold : 0;
  const prevGrossProfit = m.prev_net_revenue - prevCogs;
  const prevOperating = prevGrossProfit - m.prev_commission - m.prev_logistics;

  return {
    pnl: {
      gross_revenue: m.gross_revenue,
      returns_amount: m.returns_amount,
      net_revenue: m.net_revenue,
      cogs,
      gross_profit: grossProfit,
      commission: m.commission,
      logistics: m.logistics,
      operating_expenses: m.commission + m.logistics,
      operating_profit: operatingProfit,
      advertising: 0,
      net_profit: m.net_profit,
    },
    margins: {
      gross_margin: parseFloat(grossMargin.toFixed(1)),
      operating_margin: parseFloat(operatingMargin.toFixed(1)),
      net_margin: parseFloat(netMargin.toFixed(1)),
      return_rate: parseFloat(returnRate.toFixed(1)),
    },
    metrics: {
      units_sold: m.units_sold,
      units_returned: m.units_returned,
      active_skus: m.active_skus,
      avg_check: parseFloat(avgCheck.toFixed(0)),
      avg_profit_per_unit: parseFloat(avgProfit.toFixed(0)),
    },
    changes: {
      gross_revenue: pctChange(m.gross_revenue, m.prev_gross_revenue),
      net_revenue: pctChange(m.net_revenue, m.prev_net_revenue),
      cogs: pctChange(cogs, prevCogs),
      gross_profit: pctChange(grossProfit, prevGrossProfit),
      commission: pctChange(m.commission, m.prev_commission),
      logistics: pctChange(m.logistics, m.prev_logistics),
      operating_profit: pctChange(operatingProfit, prevOperating),
      net_profit: pctChange(m.net_profit, m.prev_net_profit),
    },
    daily: dailyRes.rows,
    by_category: byCatRes.rows,
  };
}
