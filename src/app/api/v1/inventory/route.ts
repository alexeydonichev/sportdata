import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

export async function GET(req: NextRequest) {
  const category = req.nextUrl.searchParams.get("category");

  try {
    const conditions: string[] = [];
    const params: string[] = [];
    let idx = 0;

    if (category && category !== "all") {
      idx++;
      conditions.push(`c.slug = $${idx}`);
      params.push(category);
    }

    const where = conditions.length > 0 ? "AND " + conditions.join(" AND ") : "";

    const result = await pool.query(`
      SELECT
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
      LEFT JOIN (
        SELECT product_id, SUM(quantity)::float / 30 AS avg_daily
        FROM sales
        WHERE sale_date >= CURRENT_DATE - 30
        GROUP BY product_id
      ) s ON s.product_id = i.product_id
      WHERE i.quantity > 0 ${where}
      ORDER BY days_of_stock ASC, p.name
    `, params);

    const summary = await pool.query(`
      SELECT
        SUM(i.quantity)::int AS total_stock,
        COUNT(DISTINCT i.product_id)::int AS products_in_stock,
        COUNT(DISTINCT i.warehouse)::int AS warehouses
      FROM inventory i
      JOIN products p ON p.id = i.product_id
      JOIN categories c ON c.id = p.category_id
      WHERE i.quantity > 0 ${where}
    `, params);

    return NextResponse.json({
      items: result.rows,
      summary: summary.rows[0] || { total_stock: 0, products_in_stock: 0, warehouses: 0 },
    });
  } catch (e: unknown) {
    console.error("Inventory error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
