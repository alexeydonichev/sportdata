import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

const ALLOWED_PERIODS: Record<string, number> = { "7d": 7, "14d": 14, "30d": 30, "90d": 90 };
const MAX_LIMIT = 200;

export async function GET(req: NextRequest) {
  const period = req.nextUrl.searchParams.get("period") || "30d";
  const category = req.nextUrl.searchParams.get("category");
  const page = Math.max(1, parseInt(req.nextUrl.searchParams.get("page") || "1") || 1);
  const limit = Math.min(MAX_LIMIT, Math.max(1, parseInt(req.nextUrl.searchParams.get("limit") || "50") || 50));
  const offset = (page - 1) * limit;

  const days = ALLOWED_PERIODS[period] || 30;

  try {
    const conditions: string[] = [];
    const params: (string | number)[] = [];
    let idx = 0;

    idx++;
    conditions.push(`s.sale_date >= CURRENT_DATE - $${idx}::int`);
    params.push(days);

    if (category && category !== "all") {
      idx++;
      conditions.push(`c.slug = $${idx}`);
      params.push(category);
    }

    const where = "WHERE " + conditions.join(" AND ");

    const countResult = await pool.query(
      `SELECT COUNT(*)::int AS total FROM sales s
       JOIN products p ON p.id = s.product_id
       JOIN categories c ON c.id = p.category_id ${where}`, params
    );

    const dataParams = [...params, limit, offset];
    const result = await pool.query(`
      SELECT
        s.id::text,
        s.sale_date::text AS date,
        p.name AS product_name,
        p.sku,
        c.name AS category,
        s.quantity,
        s.revenue::float,
        s.net_profit::float AS profit,
        s.commission::float,
        s.logistics_cost::float AS logistics,
        mp.name AS marketplace
      FROM sales s
      JOIN products p ON p.id = s.product_id
      JOIN categories c ON c.id = p.category_id
      JOIN marketplaces mp ON mp.id = s.marketplace_id
      ${where}
      ORDER BY s.sale_date DESC, s.id DESC
      LIMIT $${idx + 1} OFFSET $${idx + 2}
    `, dataParams);

    return NextResponse.json({
      items: result.rows,
      total: countResult.rows[0].total,
      page,
      limit,
      pages: Math.ceil(countResult.rows[0].total / limit),
    });
  } catch (e: unknown) {
    console.error("Sales error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
