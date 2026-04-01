import pool from "@/lib/db";

export interface ReturnsData {
  summary: {
    total_returns: number;
    total_sales: number;
    return_rate: number;
    return_amount: number;
    return_logistics: number;
    lost_profit: number;
  };
  changes: {
    returns: number;
    return_rate: number;
    return_amount: number;
  };
  daily: {
    date: string;
    sales: number;
    returns: number;
    return_rate: number;
  }[];
  by_product: {
    product_id: number;
    name: string;
    sku: string;
    category: string;
    sales_qty: number;
    return_qty: number;
    return_rate: number;
    return_amount: number;
    return_logistics: number;
  }[];
  by_category: {
    category: string;
    sales_qty: number;
    return_qty: number;
    return_rate: number;
    return_amount: number;
  }[];
  by_warehouse: {
    warehouse: string;
    return_qty: number;
    return_amount: number;
  }[];
}

function pctChange(cur: number, prev: number): number {
  if (prev === 0 && cur === 0) return 0;
  if (prev === 0) return cur > 0 ? 100 : -100;
  return parseFloat((((cur - prev) / Math.abs(prev)) * 100).toFixed(1));
}

export async function getReturnsAnalytics(days: number, category?: string): Promise<ReturnsData> {
  const params: (number | string)[] = [days];
  let catFilter = "";

  if (category && category !== "all") {
    params.push(category);
    catFilter = `AND c.slug = $${params.length}`;
  }

  // Summary current period
  const summaryRes = await pool.query(`
    WITH period_data AS (
      SELECT
        COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS total_sales,
        COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS total_returns,
        COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS return_amount,
        COALESCE(SUM(CASE WHEN s.quantity < 0 THEN s.logistics_cost ELSE 0 END), 0)::float AS return_logistics,
        COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) - s.logistics_cost ELSE 0 END), 0)::float AS lost_profit
      FROM sales s
      JOIN products p ON p.id = s.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter}
    )
    SELECT * FROM period_data
  `, params);

  // Summary previous period
  const prevRes = await pool.query(`
    SELECT
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS total_sales,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS total_returns,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS return_amount
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - ($1::int * 2)
      AND s.sale_date < CURRENT_DATE - $1::int ${catFilter}
  `, params);

  const cur = summaryRes.rows[0];
  const prev = prevRes.rows[0];
  const curRate = (cur.total_sales + cur.total_returns) > 0
    ? (cur.total_returns / (cur.total_sales + cur.total_returns)) * 100 : 0;
  const prevRate = (prev.total_sales + prev.total_returns) > 0
    ? (prev.total_returns / (prev.total_sales + prev.total_returns)) * 100 : 0;

  // Daily breakdown
  const dailyRes = await pool.query(`
    SELECT
      s.sale_date::text AS date,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS sales,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS returns
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter}
    GROUP BY s.sale_date ORDER BY s.sale_date
  `, params);

  const daily = dailyRes.rows.map((d: { date: string; sales: number; returns: number }) => ({
    ...d,
    return_rate: (d.sales + d.returns) > 0
      ? parseFloat(((d.returns / (d.sales + d.returns)) * 100).toFixed(1)) : 0,
  }));

  // By product (top returnable)
  const byProductRes = await pool.query(`
    SELECT
      p.id AS product_id,
      p.name,
      p.sku,
      COALESCE(c.name, 'Без категории') AS category,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS sales_qty,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS return_qty,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS return_amount,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN s.logistics_cost ELSE 0 END), 0)::float AS return_logistics
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter}
    GROUP BY p.id, p.name, p.sku, c.name
    HAVING SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END) > 0
    ORDER BY return_qty DESC
    LIMIT 50
  `, params);

  const byProduct = byProductRes.rows.map((r: { product_id: number; name: string; sku: string; category: string; sales_qty: number; return_qty: number; return_amount: number; return_logistics: number }) => ({
    ...r,
    return_rate: (r.sales_qty + r.return_qty) > 0
      ? parseFloat(((r.return_qty / (r.sales_qty + r.return_qty)) * 100).toFixed(1)) : 0,
  }));

  // By category
  const byCatRes = await pool.query(`
    SELECT
      COALESCE(c.name, 'Без категории') AS category,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS sales_qty,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS return_qty,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS return_amount
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter}
    GROUP BY c.name
    ORDER BY return_qty DESC
  `, params);

  const byCategory = byCatRes.rows.map((r: { category: string; sales_qty: number; return_qty: number; return_amount: number }) => ({
    ...r,
    return_rate: (r.sales_qty + r.return_qty) > 0
      ? parseFloat(((r.return_qty / (r.sales_qty + r.return_qty)) * 100).toFixed(1)) : 0,
  }));

  // By warehouse (from office_name)
  const byWhRes = await pool.query(`
    SELECT
      COALESCE(s.office_name, 'Не указан') AS warehouse,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS return_qty,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS return_amount
    FROM sales s
    JOIN products p ON p.id = s.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= CURRENT_DATE - $1::int ${catFilter}
      AND s.quantity < 0
    GROUP BY s.office_name
    ORDER BY return_qty DESC
    LIMIT 20
  `, params);

  return {
    summary: {
      total_returns: cur.total_returns,
      total_sales: cur.total_sales,
      return_rate: parseFloat(curRate.toFixed(1)),
      return_amount: cur.return_amount,
      return_logistics: cur.return_logistics,
      lost_profit: cur.lost_profit,
    },
    changes: {
      returns: pctChange(cur.total_returns, prev.total_returns),
      return_rate: pctChange(curRate, prevRate),
      return_amount: pctChange(cur.return_amount, prev.return_amount),
    },
    daily,
    by_product: byProduct,
    by_category: byCategory,
    by_warehouse: byWhRes.rows,
  };
}
