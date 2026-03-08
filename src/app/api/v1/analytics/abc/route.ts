import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

const ALLOWED_DAYS = [30, 60, 90, 180, 365];

export async function GET(req: NextRequest) {
  const period = req.nextUrl.searchParams.get("period") || "90";
  let days = parseInt(period) || 90;
  // Clamp to allowed values
  if (!ALLOWED_DAYS.includes(days)) {
    days = ALLOWED_DAYS.reduce((prev, curr) =>
      Math.abs(curr - days) < Math.abs(prev - days) ? curr : prev
    );
  }

  try {
    const result = await pool.query(`
      SELECT
        p.id::text AS id,
        p.name,
        p.sku,
        c.name AS category,
        COALESCE(s.revenue, 0)::float AS revenue,
        COALESCE(s.profit, 0)::float AS profit,
        COALESCE(s.quantity, 0)::int AS quantity,
        COALESCE(s.orders, 0)::int AS orders
      FROM products p
      JOIN categories c ON c.id = p.category_id
      LEFT JOIN (
        SELECT product_id,
          SUM(revenue) AS revenue,
          SUM(net_profit) AS profit,
          SUM(quantity) AS quantity,
          COUNT(*) AS orders
        FROM sales
        WHERE sale_date >= CURRENT_DATE - $1::int
        GROUP BY product_id
      ) s ON s.product_id = p.id
      ORDER BY revenue DESC NULLS LAST
    `, [days]);

    return NextResponse.json({ products: result.rows });
  } catch (e: unknown) {
    console.error("ABC analysis error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
