import pool from "@/lib/db";
import type { InventoryRow, InventorySummary, InventoryData } from "@/types/models";

export async function getInventory(
  category?: string,
  marketplace?: string
): Promise<InventoryData> {
  const conditions: string[] = [];
  const params: string[] = [];
  let idx = 0;

  if (category && category !== "all") {
    idx++;
    conditions.push(`c.slug = $${idx}`);
    params.push(category);
  }

  const needMpJoin = !!(marketplace && marketplace !== "all");
  if (needMpJoin) {
    idx++;
    conditions.push(`mp.slug = $${idx}`);
    params.push(marketplace!);
  }

  const where = conditions.length > 0 ? "AND " + conditions.join(" AND ") : "";
  const mpJoin = needMpJoin
    ? "JOIN marketplaces mp ON mp.id = i.marketplace_id"
    : "";

  const itemsResult = await pool.query(
    `SELECT
      p.id::text AS product_id,
      p.name,
      p.sku,
      c.name AS category,
      i.warehouse,
      i.quantity::int AS stock,
      COALESCE(s.avg_daily, 0)::float AS avg_daily_sales,
      CASE
        WHEN COALESCE(s.avg_daily, 0) > 0
        THEN ROUND((i.quantity / s.avg_daily)::numeric, 0)::int
        ELSE 999
      END AS days_of_stock
    FROM inventory i
    JOIN products p ON p.id = i.product_id
    JOIN categories c ON c.id = p.category_id
    ${mpJoin}
    LEFT JOIN (
      SELECT product_id, SUM(quantity)::float / 30 AS avg_daily
      FROM sales
      WHERE sale_date >= CURRENT_DATE - 30
      GROUP BY product_id
    ) s ON s.product_id = i.product_id
    WHERE i.quantity > 0 ${where}
    ORDER BY days_of_stock ASC, p.name`,
    params
  );

  const summaryResult = await pool.query(
    `SELECT
      SUM(i.quantity)::int AS total_stock,
      COUNT(DISTINCT i.product_id)::int AS products_in_stock,
      COUNT(DISTINCT i.warehouse)::int AS warehouses
    FROM inventory i
    JOIN products p ON p.id = i.product_id
    JOIN categories c ON c.id = p.category_id
    ${mpJoin}
    WHERE i.quantity > 0 ${where}`,
    params
  );

  return {
    items: itemsResult.rows as InventoryRow[],
    summary: (summaryResult.rows[0] as InventorySummary) || {
      total_stock: 0,
      products_in_stock: 0,
      warehouses: 0,
    },
  };
}
