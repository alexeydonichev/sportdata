import pool from "@/lib/db";
import type { Alert, NotificationsData } from "@/types/models";

export async function getNotifications(marketplace?: string): Promise<NotificationsData> {
  const alerts: Alert[] = [];
  const now = new Date().toISOString();
  const hasMP = !!(marketplace && marketplace !== "all");

  const mpParams: string[] = hasMP ? [marketplace] : [];

  const mpProductCond = hasMP
    ? `AND p.id IN (
        SELECT DISTINCT s_mp.product_id FROM sales s_mp
        JOIN marketplaces mp ON mp.id = s_mp.marketplace_id
        WHERE mp.slug = $${mpParams.length}
      )`
    : "";

  const mpSalesCond = hasMP
    ? `AND s.marketplace_id = (SELECT id FROM marketplaces WHERE slug = $${mpParams.length})`
    : "";

  // 1. Critical stock (≤ 7 days)
  const criticalStock = await pool.query(
    `WITH daily_sales AS (
      SELECT product_id, COALESCE(AVG(daily_qty), 0) AS avg_daily
      FROM (
        SELECT product_id, sale_date, SUM(quantity) AS daily_qty
        FROM sales
        WHERE sale_date >= CURRENT_DATE - 30
        GROUP BY product_id, sale_date
      ) d
      GROUP BY product_id
    )
    SELECT
      p.id::text AS product_id, p.name, p.sku,
      COALESCE(i.total_stock, 0)::int AS stock,
      COALESCE(ds.avg_daily, 0)::float AS avg_daily,
      CASE WHEN COALESCE(ds.avg_daily, 0) > 0
        THEN FLOOR(COALESCE(i.total_stock, 0) / ds.avg_daily)
        ELSE 999 END AS days_left
    FROM products p
    LEFT JOIN (
      SELECT product_id, SUM(quantity) AS total_stock
      FROM inventory GROUP BY product_id
    ) i ON i.product_id = p.id
    LEFT JOIN daily_sales ds ON ds.product_id = p.id
    WHERE COALESCE(i.total_stock, 0) > 0
      AND COALESCE(ds.avg_daily, 0) > 0
      AND FLOOR(COALESCE(i.total_stock, 0) / ds.avg_daily) <= 7
      ${mpProductCond}
    ORDER BY days_left ASC
    LIMIT 20`,
    mpParams
  );

  for (const row of criticalStock.rows) {
    const days = Math.floor(row.days_left);
    alerts.push({
      id: `stock_crit_${row.product_id}`,
      type: days <= 3 ? "stock_critical" : "stock_low",
      severity: days <= 3 ? "critical" : "warning",
      title: days <= 3 ? "Критический остаток" : "Низкий остаток",
      message: `${row.name} — осталось ${row.stock} шт (≈${days} дн при ${row.avg_daily.toFixed(1)} шт/день)`,
      product_id: row.product_id,
      product_name: row.name,
      sku: row.sku,
      value: days,
      threshold: 7,
      created_at: now,
    });
  }

  // 2. Low stock (8–21 days)
  const lowStock = await pool.query(
    `WITH daily_sales AS (
      SELECT product_id, COALESCE(AVG(daily_qty), 0) AS avg_daily
      FROM (
        SELECT product_id, sale_date, SUM(quantity) AS daily_qty
        FROM sales
        WHERE sale_date >= CURRENT_DATE - 30
        GROUP BY product_id, sale_date
      ) d
      GROUP BY product_id
    )
    SELECT
      p.id::text AS product_id, p.name, p.sku,
      COALESCE(i.total_stock, 0)::int AS stock,
      COALESCE(ds.avg_daily, 0)::float AS avg_daily,
      FLOOR(COALESCE(i.total_stock, 0) / ds.avg_daily)::int AS days_left
    FROM products p
    LEFT JOIN (
      SELECT product_id, SUM(quantity) AS total_stock
      FROM inventory GROUP BY product_id
    ) i ON i.product_id = p.id
    LEFT JOIN daily_sales ds ON ds.product_id = p.id
    WHERE COALESCE(i.total_stock, 0) > 0
      AND COALESCE(ds.avg_daily, 0) > 0
      AND FLOOR(COALESCE(i.total_stock, 0) / ds.avg_daily) BETWEEN 8 AND 21
      ${mpProductCond}
    ORDER BY days_left ASC
    LIMIT 10`,
    mpParams
  );

  for (const row of lowStock.rows) {
    alerts.push({
      id: `stock_low_${row.product_id}`,
      type: "stock_low",
      severity: "warning",
      title: "Запас заканчивается",
      message: `${row.name} — осталось ${row.stock} шт (≈${row.days_left} дн)`,
      product_id: row.product_id,
      product_name: row.name,
      sku: row.sku,
      value: row.days_left,
      threshold: 21,
      created_at: now,
    });
  }

  // 3. Sales anomalies
  const salesAnomalies = await pool.query(
    `WITH weekly_current AS (
      SELECT s.product_id, SUM(s.revenue)::float AS current_revenue
      FROM sales s
      WHERE s.sale_date >= CURRENT_DATE - 7
        ${mpSalesCond}
      GROUP BY s.product_id
    ),
    weekly_avg AS (
      SELECT product_id, AVG(week_revenue)::float AS avg_revenue
      FROM (
        SELECT s.product_id,
          DATE_TRUNC('week', s.sale_date) AS week,
          SUM(s.revenue) AS week_revenue
        FROM sales s
        WHERE s.sale_date >= CURRENT_DATE - 35 AND s.sale_date < CURRENT_DATE - 7
          ${mpSalesCond}
        GROUP BY s.product_id, DATE_TRUNC('week', s.sale_date)
      ) w
      GROUP BY product_id HAVING COUNT(*) >= 2
    )
    SELECT
      p.id::text AS product_id, p.name, p.sku,
      wc.current_revenue, wa.avg_revenue,
      CASE WHEN wa.avg_revenue > 0
        THEN ((wc.current_revenue - wa.avg_revenue) / wa.avg_revenue * 100)::float
        ELSE 0 END AS change_pct
    FROM weekly_current wc
    JOIN weekly_avg wa ON wa.product_id = wc.product_id
    JOIN products p ON p.id = wc.product_id
    WHERE wa.avg_revenue > 100
      AND ABS((wc.current_revenue - wa.avg_revenue) / wa.avg_revenue) > 0.5
    ORDER BY ABS((wc.current_revenue - wa.avg_revenue) / wa.avg_revenue) DESC
    LIMIT 10`,
    mpParams
  );

  for (const row of salesAnomalies.rows) {
    const pct = Math.round(row.change_pct);
    const isSpike = pct > 0;
    alerts.push({
      id: `sales_${isSpike ? "spike" : "drop"}_${row.product_id}`,
      type: isSpike ? "sales_spike" : "sales_drop",
      severity: Math.abs(pct) > 100 ? "critical" : "warning",
      title: isSpike ? "Всплеск продаж" : "Падение продаж",
      message: `${row.name} — ${isSpike ? "+" : ""}${pct}% к среднему за неделю`,
      product_id: row.product_id,
      product_name: row.name,
      sku: row.sku,
      value: pct,
      threshold: 50,
      created_at: now,
    });
  }

  // 4. High return rate
  const highReturns = await pool.query(
    `SELECT
      p.id::text AS product_id, p.name, p.sku,
      SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)::int AS returns,
      SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END)::int AS sold,
      CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
        THEN (SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)::float /
              SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) * 100)
        ELSE 0 END AS return_pct
    FROM sales s
    JOIN products p ON p.id = s.product_id
    WHERE s.sale_date >= CURRENT_DATE - 30
      ${mpSalesCond}
    GROUP BY p.id, p.name, p.sku
    HAVING SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) >= 10
      AND (SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)::float /
           NULLIF(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0) * 100) > 10
    ORDER BY return_pct DESC
    LIMIT 10`,
    mpParams
  );

  for (const row of highReturns.rows) {
    const pct = Math.round(row.return_pct);
    alerts.push({
      id: `returns_${row.product_id}`,
      type: "high_returns",
      severity: pct > 20 ? "critical" : "warning",
      title: "Высокий возврат",
      message: `${row.name} — ${pct}% возвратов (${row.returns} из ${row.sold} шт)`,
      product_id: row.product_id,
      product_name: row.name,
      sku: row.sku,
      value: pct,
      threshold: 10,
      created_at: now,
    });
  }

  const severityOrder: Record<string, number> = { critical: 0, warning: 1, info: 2 };
  alerts.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);

  return {
    alerts,
    summary: {
      total: alerts.length,
      critical: alerts.filter((a) => a.severity === "critical").length,
      warning: alerts.filter((a) => a.severity === "warning").length,
      info: alerts.filter((a) => a.severity === "info").length,
    },
  };
}
