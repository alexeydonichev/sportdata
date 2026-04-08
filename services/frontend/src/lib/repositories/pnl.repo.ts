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
    seller_income: number;
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
  warnings: string[];
  changes: Record<string, number>;
  daily: { date: string; revenue: number; returns: number; commission: number; logistics: number; profit: number }[];
  by_category: { category: string; slug: string; revenue: number; commission: number; logistics: number; cogs: number; profit: number; units: number; margin_pct: number }[];
}

function pctChange(cur: number, prev: number): number {
  if (prev === 0 && cur === 0) return 0;
  if (prev === 0) return cur > 0 ? 100 : -100;
  return parseFloat((((cur - prev) / Math.abs(prev)) * 100).toFixed(1));
}

export async function getPnL(days: number, categorySlug?: string, marketplace?: string): Promise<PnLData> {
  const params: (number | string)[] = [days];
  let catFilter = "";
  let mpJoin = "";
  let mpFilter = "";

  if (categorySlug && categorySlug !== "all") {
    params.push(categorySlug);
    catFilter = `AND c.slug = $${params.length}`;
  }

  if (marketplace && marketplace !== "all") {
    params.push(marketplace);
    mpJoin = "JOIN marketplaces mp ON mp.id = s.marketplace_id";
    mpFilter = `AND mp.slug = $${params.length}`;
  }

  // Main aggregation — use commission column directly (filled by Report Detail)
  // Fallback: if commission column is 0, calculate from commission + logistics_cost
  const pnlRes = await pool.query(`
    WITH filtered_sales AS (
      SELECT s.*, COALESCE(p.cost_price, 0) AS product_cost
      FROM sales s
      JOIN products p ON p.id = s.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      ${mpJoin}
      WHERE s.sale_date >= CURRENT_DATE - $1::int
      ${catFilter} ${mpFilter}
    ),
    current_agg AS (
      SELECT
        COALESCE(SUM(CASE WHEN quantity > 0 THEN revenue ELSE 0 END), 0)::float AS gross_revenue,
        COALESCE(SUM(CASE WHEN quantity < 0 THEN ABS(revenue) ELSE 0 END), 0)::float AS returns_amount,
        COALESCE(SUM(revenue), 0)::float AS net_revenue,
        -- Use commission column; if all zeros, fallback to commission + logistics_cost
        CASE 
          WHEN COALESCE(SUM(CASE WHEN quantity > 0 THEN commission ELSE 0 END), 0) > 0 
          THEN COALESCE(SUM(CASE WHEN quantity > 0 THEN commission ELSE 0 END), 0)::float
          ELSE COALESCE(SUM(CASE WHEN quantity > 0 THEN commission + logistics_cost ELSE 0 END), 0)::float
        END AS commission,
        COALESCE(SUM(logistics_cost), 0)::float AS logistics,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN product_cost * quantity ELSE 0 END), 0)::float AS cogs,
        COALESCE(SUM(revenue - commission - logistics_cost), 0)::float AS total_seller_income,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END), 0)::int AS units_sold,
        COALESCE(SUM(CASE WHEN quantity < 0 THEN ABS(quantity) ELSE 0 END), 0)::int AS units_returned,
        COUNT(DISTINCT CASE WHEN quantity > 0 THEN product_id END)::int AS active_skus
      FROM filtered_sales
    ),
    prev_sales AS (
      SELECT s.*, COALESCE(p.cost_price, 0) AS product_cost
      FROM sales s
      JOIN products p ON p.id = s.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      ${mpJoin}
      WHERE s.sale_date >= CURRENT_DATE - ($1::int * 2)
        AND s.sale_date < CURRENT_DATE - $1::int
      ${catFilter} ${mpFilter}
    ),
    prev_agg AS (
      SELECT
        COALESCE(SUM(CASE WHEN quantity > 0 THEN revenue ELSE 0 END), 0)::float AS gross_revenue,
        COALESCE(SUM(revenue), 0)::float AS net_revenue,
        CASE 
          WHEN COALESCE(SUM(CASE WHEN quantity > 0 THEN commission ELSE 0 END), 0) > 0 
          THEN COALESCE(SUM(CASE WHEN quantity > 0 THEN commission ELSE 0 END), 0)::float
          ELSE COALESCE(SUM(CASE WHEN quantity > 0 THEN commission + logistics_cost ELSE 0 END), 0)::float
        END AS commission,
        COALESCE(SUM(logistics_cost), 0)::float AS logistics,
        COALESCE(SUM(CASE WHEN quantity > 0 THEN product_cost * quantity ELSE 0 END), 0)::float AS cogs,
        COALESCE(SUM(revenue - commission - logistics_cost), 0)::float AS total_seller_income
      FROM prev_sales
    )
    SELECT c.*, p.gross_revenue AS prev_gross_revenue, p.net_revenue AS prev_net_revenue,
      p.commission AS prev_commission, p.logistics AS prev_logistics,
      p.cogs AS prev_cogs, p.total_seller_income AS prev_seller_income
    FROM current_agg c, prev_agg p
  `, params);

  const m = pnlRes.rows[0];

  // Daily breakdown
  const dailyRes = await pool.query(`
    SELECT s.sale_date::text AS date,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS returns,
      CASE 
        WHEN COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.commission ELSE 0 END), 0) > 0
        THEN COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.commission ELSE 0 END), 0)::float
        ELSE COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue - (s.revenue - s.commission - s.logistics_cost) ELSE 0 END), 0)::float
      END AS commission,
      COALESCE(SUM(s.logistics_cost), 0)::float AS logistics,
      COALESCE(SUM((s.revenue - s.commission - s.logistics_cost)), 0)::float AS profit
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    ${mpJoin}
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter} ${mpFilter}
    GROUP BY s.sale_date ORDER BY s.sale_date
  `, params);

  // By category
  const byCatRes = await pool.query(`
    SELECT COALESCE(c.name, 'Без категории') AS category, COALESCE(c.slug, 'none') AS slug,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue,
      CASE 
        WHEN COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.commission ELSE 0 END), 0) > 0
        THEN COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.commission ELSE 0 END), 0)::float
        ELSE COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue - (s.revenue - s.commission - s.logistics_cost) ELSE 0 END), 0)::float
      END AS commission,
      COALESCE(SUM(s.logistics_cost), 0)::float AS logistics,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN COALESCE(p.cost_price, 0) * s.quantity ELSE 0 END), 0)::float AS cogs,
      COALESCE(SUM((s.revenue - s.commission - s.logistics_cost)), 0)::float AS profit,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS units
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    ${mpJoin}
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter} ${mpFilter}
    GROUP BY c.name, c.slug ORDER BY revenue DESC
  `, params);

  const cogs = m.cogs;
  const grossProfit = m.net_revenue - cogs;
  const operatingExpenses = m.commission + m.logistics;
  const operatingProfit = grossProfit - operatingExpenses;
  // net_profit = for_pay - cogs - logistics (what seller really earns after all deductions)
  const netProfit = m.total_seller_income - cogs - m.logistics;

  const grossMargin = m.gross_revenue > 0 ? (grossProfit / m.gross_revenue) * 100 : 0;
  const operatingMargin = m.gross_revenue > 0 ? (operatingProfit / m.gross_revenue) * 100 : 0;
  const netMargin = m.gross_revenue > 0 ? (netProfit / m.gross_revenue) * 100 : 0;
  const returnRate = m.units_sold > 0 ? (m.units_returned / (m.units_sold + m.units_returned)) * 100 : 0;
  const avgCheck = m.units_sold > 0 ? m.gross_revenue / m.units_sold : 0;
  const avgProfit = m.units_sold > 0 ? netProfit / m.units_sold : 0;

  const prevGrossProfit = m.prev_net_revenue - m.prev_cogs;
  const prevOperating = prevGrossProfit - m.prev_commission - m.prev_logistics;
  const prevNetProfit = m.prev_seller_income - m.prev_cogs - m.prev_logistics;

  // Warnings
  const warnings: string[] = [];
  if (cogs === 0) {
    warnings.push("Себестоимость товаров не заполнена (0 ₽). Прибыль считается без учёта себестоимости. Заполните себестоимость в разделе «Товары».");
  }
  if (m.logistics === 0) {
    warnings.push("Логистика = 0 ₽. Запустите синхронизацию — данные подтягиваются из отчёта WB (reportDetailByPeriod). Отчёт может быть доступен с задержкой 1–3 дня.");
  }

  // by_category with margin
  interface CatRow { category: string; slug: string; revenue: number; commission: number; logistics: number; cogs: number; profit: number; units: number }
  const byCategory = (byCatRes.rows as CatRow[]).map((cat) => ({
    ...cat,
    margin_pct: cat.revenue > 0
      ? parseFloat(((cat.profit / cat.revenue) * 100).toFixed(1))
      : 0,
  }));

  return {
    pnl: {
      gross_revenue: m.gross_revenue,
      returns_amount: m.returns_amount,
      net_revenue: m.net_revenue,
      cogs,
      gross_profit: grossProfit,
      commission: m.commission,
      logistics: m.logistics,
      operating_expenses: operatingExpenses,
      operating_profit: operatingProfit,
      advertising: 0,
      seller_income: m.total_seller_income,
      net_profit: netProfit,
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
    warnings,
    changes: {
      gross_revenue: pctChange(m.gross_revenue, m.prev_gross_revenue),
      net_revenue: pctChange(m.net_revenue, m.prev_net_revenue),
      cogs: pctChange(cogs, m.prev_cogs),
      gross_profit: pctChange(grossProfit, prevGrossProfit),
      commission: pctChange(m.commission, m.prev_commission),
      logistics: pctChange(m.logistics, m.prev_logistics),
      operating_profit: pctChange(operatingProfit, prevOperating),
      net_profit: pctChange(netProfit, prevNetProfit),
    },
    daily: dailyRes.rows,
    by_category: byCategory,
  };
}
