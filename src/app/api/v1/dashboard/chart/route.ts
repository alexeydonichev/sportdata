import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

const ALLOWED_PERIODS: Record<string, number> = { today: 1, "7d": 7, "14d": 14, "30d": 30, "90d": 90, "180d": 180, "365d": 365 };

export async function GET(req: NextRequest) {
  const period = req.nextUrl.searchParams.get("period") || "7d";
  const days = ALLOWED_PERIODS[period] || 7;

  try {
    const result = await pool.query(`
      SELECT
        sale_date::text AS date,
        COALESCE(SUM(revenue), 0)::float AS revenue,
        COALESCE(SUM(net_profit), 0)::float AS profit,
        COUNT(*)::int AS orders,
        COALESCE(SUM(quantity), 0)::int AS quantity
      FROM sales
      WHERE sale_date >= CURRENT_DATE - $1::int
      GROUP BY sale_date
      ORDER BY sale_date
    `, [days]);

    return NextResponse.json(result.rows);
  } catch (e: unknown) {
    console.error("Chart error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
