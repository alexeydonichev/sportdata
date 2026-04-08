import pool from "@/lib/db";

export interface ReturnsData {
  summary: {
    total_returns: number;
    total_sales: number;
    return_rate: number;
    return_amount: number;
    lost_profit: number;
    return_logistics: number;
  };
  changes: {
    returns: number;
    return_rate: number;
    return_amount: number;
  };
  daily: { date: string; sales: number; returns: number; return_rate: number }[];
  by_product: {
    product_id: number;
    name: string;
    sku: string;
    category: string;
    sales_qty: number;
    return_qty: number;
    return_rate: number;
    return_amount: number;
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

function pct(c: number, p: number): number {
  if (p === 0 && c === 0) return 0;
  if (p === 0) return c > 0 ? 100 : -100;
  return parseFloat((((c - p) / Math.abs(p)) * 100).toFixed(1));
}

export async function getReturnsAnalytics(days: number, category?: string): Promise<ReturnsData> {
  const params: (number | string)[] = [days];
  let catF = "";
  if (category && category !== "all") {
    params.push(category);
    catF = "AND c.slug = $" + params.length;
  }

  const salesRes = await pool.query(
    "SELECT COALESCE(SUM(s.quantity), 0)::int AS total_sales, COALESCE(SUM(s.revenue), 0)::float AS total_revenue, COALESCE(SUM(s.net_profit), 0)::float AS total_profit FROM sales s JOIN products p ON p.id = s.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE s.sale_date >= CURRENT_DATE - $1::int AND s.quantity > 0 " + catF,
    params
  );

  const curRet = await pool.query(
    "SELECT COALESCE(SUM(r.quantity), 0)::int AS total_returns, COALESCE(SUM(r.return_amount), 0)::float AS return_amount, COALESCE(SUM(r.logistics_cost), 0)::float AS logistics_cost, COALESCE(SUM(r.penalty), 0)::float AS penalty FROM returns r JOIN products p ON p.id = r.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE r.return_date >= CURRENT_DATE - $1::int " + catF,
    params
  );

  const prevSales = await pool.query(
    "SELECT COALESCE(SUM(s.quantity), 0)::int AS total_sales FROM sales s JOIN products p ON p.id = s.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE s.sale_date >= CURRENT_DATE - ($1::int * 2) AND s.sale_date < CURRENT_DATE - $1::int AND s.quantity > 0 " + catF,
    params
  );

  const prevRet = await pool.query(
    "SELECT COALESCE(SUM(r.quantity), 0)::int AS total_returns, COALESCE(SUM(r.return_amount), 0)::float AS return_amount FROM returns r JOIN products p ON p.id = r.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE r.return_date >= CURRENT_DATE - ($1::int * 2) AND r.return_date < CURRENT_DATE - $1::int " + catF,
    params
  );

  const cs = salesRes.rows[0];
  const cr = curRet.rows[0];
  const ps = prevSales.rows[0];
  const pr = prevRet.rows[0];

  const curRate = (cs.total_sales + cr.total_returns) > 0 ? (cr.total_returns / (cs.total_sales + cr.total_returns)) * 100 : 0;
  const prevRate = (ps.total_sales + pr.total_returns) > 0 ? (pr.total_returns / (ps.total_sales + pr.total_returns)) * 100 : 0;
  const avgProfitPerItem = cs.total_sales > 0 ? cs.total_profit / cs.total_sales : 0;
  const lostProfit = avgProfitPerItem * cr.total_returns;

  const dailyRes = await pool.query(
    "WITH ds AS (SELECT s.sale_date AS d, COALESCE(SUM(s.quantity), 0)::int AS sales FROM sales s JOIN products p ON p.id = s.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE s.sale_date >= CURRENT_DATE - $1::int AND s.quantity > 0 " + catF + " GROUP BY s.sale_date), dr AS (SELECT r.return_date AS d, COALESCE(SUM(r.quantity), 0)::int AS returns FROM returns r JOIN products p ON p.id = r.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE r.return_date >= CURRENT_DATE - $1::int " + catF + " GROUP BY r.return_date) SELECT COALESCE(ds.d, dr.d)::text AS date, COALESCE(ds.sales, 0) AS sales, COALESCE(dr.returns, 0) AS returns FROM ds FULL OUTER JOIN dr ON ds.d = dr.d ORDER BY date",
    params
  );

  const daily = dailyRes.rows.map((d: { date: string; sales: number; returns: number }) => ({
    ...d,
    return_rate: (d.sales + d.returns) > 0 ? +((d.returns / (d.sales + d.returns)) * 100).toFixed(1) : 0,
  }));

  const byProdRes = await pool.query(
    "WITH product_sales AS (SELECT product_id, SUM(quantity)::int AS sales_qty, SUM(revenue)::float AS sales_amount FROM sales WHERE sale_date >= CURRENT_DATE - $1::int AND quantity > 0 GROUP BY product_id), product_returns AS (SELECT product_id, SUM(quantity)::int AS return_qty, COALESCE(SUM(return_amount), 0)::float AS return_amount FROM returns WHERE return_date >= CURRENT_DATE - $1::int GROUP BY product_id) SELECT p.id AS product_id, p.name, p.sku, COALESCE(c.name, 'Без категории') AS category, COALESCE(ps.sales_qty, 0)::int AS sales_qty, COALESCE(pr.return_qty, 0)::int AS return_qty, COALESCE(pr.return_amount, 0)::float AS return_amount FROM product_returns pr JOIN products p ON p.id = pr.product_id LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN product_sales ps ON ps.product_id = p.id ORDER BY pr.return_qty DESC LIMIT 50",
    params
  );

  const byProduct = byProdRes.rows.map((r: { product_id: number; name: string; sku: string; category: string; sales_qty: number; return_qty: number; return_amount: number }) => ({
    ...r,
    return_rate: (r.sales_qty + r.return_qty) > 0 ? +((r.return_qty / (r.sales_qty + r.return_qty)) * 100).toFixed(1) : 0,
  }));

  const byCatRes = await pool.query(
    "WITH cat_sales AS (SELECT p.category_id, SUM(s.quantity)::int AS sales_qty FROM sales s JOIN products p ON p.id = s.product_id WHERE s.sale_date >= CURRENT_DATE - $1::int AND s.quantity > 0 GROUP BY p.category_id), cat_returns AS (SELECT p.category_id, SUM(r.quantity)::int AS return_qty, COALESCE(SUM(r.return_amount), 0)::float AS return_amount FROM returns r JOIN products p ON p.id = r.product_id WHERE r.return_date >= CURRENT_DATE - $1::int GROUP BY p.category_id) SELECT COALESCE(c.name, 'Без категории') AS category, COALESCE(cs.sales_qty, 0)::int AS sales_qty, COALESCE(cr.return_qty, 0)::int AS return_qty, COALESCE(cr.return_amount, 0)::float AS return_amount FROM cat_returns cr LEFT JOIN categories c ON c.id = cr.category_id LEFT JOIN cat_sales cs ON cs.category_id = cr.category_id ORDER BY cr.return_qty DESC",
    params
  );

  const byCategory = byCatRes.rows.map((r: { category: string; sales_qty: number; return_qty: number; return_amount: number }) => ({
    ...r,
    return_rate: (r.sales_qty + r.return_qty) > 0 ? +((r.return_qty / (r.sales_qty + r.return_qty)) * 100).toFixed(1) : 0,
  }));

  const byWhRes = await pool.query(
    "SELECT COALESCE(r.warehouse, 'Неизвестный склад') AS warehouse, COALESCE(SUM(r.quantity), 0)::int AS return_qty, COALESCE(SUM(r.return_amount), 0)::float AS return_amount FROM returns r JOIN products p ON p.id = r.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE r.return_date >= CURRENT_DATE - $1::int " + catF + " GROUP BY r.warehouse ORDER BY return_qty DESC",
    params
  );

  return {
    summary: {
      total_returns: cr.total_returns,
      total_sales: cs.total_sales,
      return_rate: +curRate.toFixed(1),
      return_amount: cr.return_amount || 0,
      lost_profit: +lostProfit.toFixed(0),
      return_logistics: cr.logistics_cost || 0,
    },
    changes: {
      returns: pct(cr.total_returns, pr.total_returns),
      return_rate: pct(curRate, prevRate),
      return_amount: pct(cr.return_amount || 0, pr.return_amount || 0),
    },
    daily,
    by_product: byProduct,
    by_category: byCategory,
    by_warehouse: byWhRes.rows,
  };
}
