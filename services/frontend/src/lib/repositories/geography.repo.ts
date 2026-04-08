import pool from "@/lib/db";

export interface GeoData {
  by_country: { country: string; revenue: number; quantity: number; orders: number; returns: number; return_rate: number }[];
  by_warehouse: { warehouse: string; revenue: number; quantity: number; orders: number; returns: number }[];
  by_pvz: { pvz: string; revenue: number; quantity: number }[];
  summary: { countries: number; warehouses: number; total_revenue: number; top_country: string; top_warehouse: string };
}

export async function getGeography(days: number, category?: string, marketplace?: string): Promise<GeoData> {
  const params: (number | string)[] = [days];
  let catF = "", mpF = "";
  if (category && category !== "all") { params.push(category); catF = "AND c.slug = $" + params.length; }
  if (marketplace && marketplace !== "all") { params.push(marketplace); mpF = "AND mp.slug = $" + params.length; }

  const countryRes = await pool.query(
    "SELECT COALESCE(s.country, 'Неизвестно') AS country, COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue, COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS quantity, COUNT(CASE WHEN s.quantity > 0 THEN 1 END)::int AS orders, COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS returns FROM sales s JOIN marketplaces mp ON mp.id = s.marketplace_id JOIN products p ON p.id = s.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE s.sale_date >= CURRENT_DATE - $1::int " + catF + " " + mpF + " GROUP BY s.country ORDER BY revenue DESC",
    params
  );

  const byCountry = countryRes.rows.map((r: { country: string; revenue: number; quantity: number; orders: number; returns: number }) => ({
    ...r,
    return_rate: (r.quantity + r.returns) > 0 ? +((r.returns / (r.quantity + r.returns)) * 100).toFixed(1) : 0,
  }));

  const warehouseRes = await pool.query(
    "SELECT COALESCE(s.warehouse, 'Неизвестный склад') AS warehouse, COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue, COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS quantity, COUNT(CASE WHEN s.quantity > 0 THEN 1 END)::int AS orders, COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS returns FROM sales s JOIN marketplaces mp ON mp.id = s.marketplace_id JOIN products p ON p.id = s.product_id LEFT JOIN categories c ON c.id = p.category_id WHERE s.sale_date >= CURRENT_DATE - $1::int " + catF + " " + mpF + " GROUP BY s.warehouse ORDER BY revenue DESC",
    params
  );

  const pvzRes = await pool.query(
    "SELECT COALESCE(pp.name, 'ПВЗ #' || s.pickup_point_id::text, 'Неизвестный ПВЗ') AS pvz, COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue, COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS quantity FROM sales s JOIN marketplaces mp ON mp.id = s.marketplace_id JOIN products p ON p.id = s.product_id LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN pickup_points pp ON pp.id = s.pickup_point_id WHERE s.sale_date >= CURRENT_DATE - $1::int AND s.pickup_point_id IS NOT NULL " + catF + " " + mpF + " GROUP BY pp.name, s.pickup_point_id ORDER BY revenue DESC LIMIT 100",
    params
  );

  const totalRev = byCountry.reduce((s: number, r: { revenue: number }) => s + r.revenue, 0);

  return {
    by_country: byCountry,
    by_warehouse: warehouseRes.rows,
    by_pvz: pvzRes.rows,
    summary: {
      countries: byCountry.filter((c: { country: string }) => c.country !== 'Неизвестно').length,
      warehouses: warehouseRes.rows.filter((w: { warehouse: string }) => w.warehouse !== 'Неизвестный склад').length,
      total_revenue: totalRev,
      top_country: byCountry[0]?.country || "-",
      top_warehouse: warehouseRes.rows[0]?.warehouse || "-",
    },
  };
}
