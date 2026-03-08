import pool from "@/lib/db";
import type { ProductDetail } from "@/types/models";

function pctChange(cur: number, prev: number): number | null {
  if (prev === 0 && cur === 0) return 0;
  if (prev === 0) return cur > 0 ? 100 : -100;
  return parseFloat((((cur - prev) / prev) * 100).toFixed(1));
}

export async function getProductDetail(productId: number, days: number): Promise<ProductDetail | null> {
  const productRes = await pool.query(`
    SELECT
      p.id::text, p.name, p.sku, p.barcode,
      p.cost_price::float, p.price::float,
      c.name AS category, c.slug AS category_slug,
      p.created_at::text
    FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE p.id = $1
  `, [productId]);

  if (productRes.rows.length === 0) return null;

  const product = productRes.rows[0];

  const metricsRes = await pool.query(`
    SELECT
      COALESCE(SUM(revenue), 0)::float AS total_revenue,
      COALESCE(SUM(net_profit), 0)::float AS total_profit,
      COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END), 0)::int AS total_sold,
      COUNT(*)::int AS total_orders,
      COALESCE(AVG(CASE WHEN revenue > 0 THEN revenue END), 0)::float AS avg_price,
      COALESCE(SUM(commission), 0)::float AS total_commission,
      COALESCE(SUM(logistics_cost), 0)::float AS total_logistics,
      COALESCE(SUM(CASE WHEN quantity < 0 THEN ABS(quantity) ELSE 0 END), 0)::int AS total_returns
    FROM sales
    WHERE product_id = $1 AND sale_date >= CURRENT_DATE - $2::int
  `, [productId, days]);

  const metrics = metricsRes.rows[0];
  const marginPct = metrics.total_revenue > 0
    ? (metrics.total_profit / metrics.total_revenue) * 100 : 0;
  const returnPct = metrics.total_sold > 0
    ? (metrics.total_returns / metrics.total_sold) * 100 : 0;

  const prevRes = await pool.query(`
    SELECT
      COALESCE(SUM(revenue), 0)::float AS total_revenue,
      COALESCE(SUM(net_profit), 0)::float AS total_profit,
      COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END), 0)::int AS total_sold,
      COUNT(*)::int AS total_orders
    FROM sales
    WHERE product_id = $1
      AND sale_date >= CURRENT_DATE - ($2::int * 2)
      AND sale_date < CURRENT_DATE - $2::int
  `, [productId, days]);

  const prev = prevRes.rows[0];

  const changes = {
    revenue: pctChange(metrics.total_revenue, prev.total_revenue),
    profit: pctChange(metrics.total_profit, prev.total_profit),
    quantity: pctChange(metrics.total_sold, prev.total_sold),
    orders: pctChange(metrics.total_orders, prev.total_orders),
  };

  const chartRes = await pool.query(`
    SELECT
      sale_date::text AS date,
      COALESCE(SUM(revenue), 0)::float AS revenue,
      COALESCE(SUM(net_profit), 0)::float AS profit,
      COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END), 0)::int AS quantity,
      COUNT(*)::int AS orders
    FROM sales
    WHERE product_id = $1 AND sale_date >= CURRENT_DATE - $2::int
    GROUP BY sale_date
    ORDER BY sale_date
  `, [productId, days]);

  const inventoryRes = await pool.query(`
    SELECT
      w.name AS warehouse,
      COALESCE(i.quantity, 0)::int AS stock,
      i.updated_at::text
    FROM inventory i
    JOIN warehouses w ON w.id = i.warehouse_id
    WHERE i.product_id = $1 AND i.quantity > 0
    ORDER BY i.quantity DESC
  `, [productId]);

  const totalStock = inventoryRes.rows.reduce((s: number, r: { stock: number }) => s + r.stock, 0);

  const dailyAvgRes = await pool.query(`
    SELECT COALESCE(AVG(daily_qty), 0)::float AS avg_daily
    FROM (
      SELECT SUM(quantity) AS daily_qty
      FROM sales
      WHERE product_id = $1 AND sale_date >= CURRENT_DATE - 30 AND quantity > 0
      GROUP BY sale_date
    ) d
  `, [productId]);

  const avgDaily = dailyAvgRes.rows[0]?.avg_daily || 0;
  const daysOfStock = avgDaily > 0 ? Math.floor(totalStock / avgDaily) : 999;

  const abcRes = await pool.query(`
    WITH product_revenues AS (
      SELECT product_id, SUM(revenue)::float AS revenue
      FROM sales
      WHERE sale_date >= CURRENT_DATE - $1::int
      GROUP BY product_id
    ),
    ranked AS (
      SELECT product_id, revenue,
        SUM(revenue) OVER (ORDER BY revenue DESC) AS cumulative,
        SUM(revenue) OVER () AS total
      FROM product_revenues
    )
    SELECT
      CASE
        WHEN total > 0 AND (cumulative - revenue) / total < 0.8 THEN 'A'
        WHEN total > 0 AND (cumulative - revenue) / total < 0.95 THEN 'B'
        ELSE 'C'
      END AS grade,
      CASE WHEN total > 0 THEN (revenue / total * 100)::float ELSE 0 END AS revenue_share
    FROM ranked
    WHERE product_id = $2
  `, [days, productId]);

  const abc = abcRes.rows[0] || { grade: "C", revenue_share: 0 };

  const mpRes = await pool.query(`
    SELECT
      mp.slug AS marketplace,
      mp.name,
      COALESCE(SUM(s.revenue), 0)::float AS revenue,
      COALESCE(SUM(s.net_profit), 0)::float AS profit,
      COALESCE(SUM(s.quantity), 0)::int AS quantity
    FROM sales s
    JOIN marketplaces mp ON mp.id = s.marketplace_id
    WHERE s.product_id = $1 AND s.sale_date >= CURRENT_DATE - $2::int
    GROUP BY mp.slug, mp.name
    ORDER BY revenue DESC
  `, [productId, days]);

  return {
    product,
    metrics: {
      ...metrics,
      margin_pct: parseFloat(marginPct.toFixed(1)),
      return_pct: parseFloat(returnPct.toFixed(1)),
    },
    changes,
    chart: chartRes.rows,
    inventory: {
      items: inventoryRes.rows,
      total_stock: totalStock,
      avg_daily_sales: parseFloat(avgDaily.toFixed(1)),
      days_of_stock: daysOfStock,
    },
    abc: {
      grade: abc.grade,
      revenue_share: parseFloat(Number(abc.revenue_share).toFixed(1)),
    },
    by_marketplace: mpRes.rows,
  } as ProductDetail;
}
