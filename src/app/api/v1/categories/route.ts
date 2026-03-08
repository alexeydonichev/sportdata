import { NextResponse } from "next/server";
import pool from "@/lib/db";

export async function GET() {
  try {
    const result = await pool.query(`
      SELECT
        c.slug,
        c.name,
        COUNT(p.id)::int AS product_count,
        COALESCE(SUM(s.revenue), 0)::float AS revenue
      FROM categories c
      LEFT JOIN products p ON p.category_id = c.id
      LEFT JOIN (
        SELECT product_id, SUM(revenue) AS revenue
        FROM sales WHERE sale_date >= CURRENT_DATE - 90
        GROUP BY product_id
      ) s ON s.product_id = p.id
      GROUP BY c.slug, c.name
      ORDER BY revenue DESC
    `);
    return NextResponse.json(result.rows);
  } catch (e: unknown) {
    console.error("Categories error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
