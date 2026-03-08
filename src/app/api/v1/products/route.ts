import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

const ALLOWED_SORTS: Record<string, string> = {
  revenue: "revenue", profit: "profit", quantity: "quantity",
  name: "p.name", price: "avg_price", margin: "margin_pct", stock: "stock"
};

export async function GET(req: NextRequest) {
  const category = req.nextUrl.searchParams.get("category");
  const search = req.nextUrl.searchParams.get("search");
  const sort = req.nextUrl.searchParams.get("sort") || "revenue";
  const order = req.nextUrl.searchParams.get("order") || "desc";

  try {
    const conditions: string[] = [];
    const params: string[] = [];
    let idx = 0;

    if (category && category !== "all") {
      idx++;
      conditions.push(`c.slug = $${idx}`);
      params.push(category);
    }
    if (search && search.length <= 100) {
      idx++;
      // Sanitize: only use parameterized ILIKE
      conditions.push(`(p.name ILIKE $${idx} OR p.sku ILIKE $${idx})`);
      params.push(`%${search}%`);
    }

    const where = conditions.length > 0 ? "WHERE " + conditions.join(" AND ") : "";
    const sortCol = ALLOWED_SORTS[sort] || "revenue";
    const sortDir = order === "asc" ? "ASC" : "DESC";

    const result = await pool.query(`
      SELECT
        p.id::text AS id,
        p.name,
        p.sku,
        p.cost_price::float,
        c.name AS category,
        c.slug AS category_slug,
        COALESCE(s.revenue, 0)::float AS revenue,
        COALESCE(s.profit, 0)::float AS profit,
        COALESCE(s.quantity, 0)::int AS quantity,
        COALESCE(s.orders, 0)::int AS orders,
        CASE WHEN COALESCE(s.quantity, 0) > 0
          THEN ROUND((s.revenue / s.quantity)::numeric, 0)::float
          ELSE COALESCE(p.cost_price::float, 0)
        END AS avg_price,
        CASE WHEN COALESCE(s.revenue, 0) > 0
          THEN ROUND((s.profit / s.revenue * 100)::numeric, 1)::float
          ELSE 0
        END AS margin_pct,
        COALESCE(inv.total_stock, 0)::int AS stock,
        COALESCE(ret.total_returns, 0)::int AS returns,
        CASE WHEN COALESCE(s.quantity, 0) > 0
          THEN ROUND((COALESCE(ret.total_returns, 0)::numeric / s.quantity * 100), 1)::float
          ELSE 0
        END AS return_pct
      FROM products p
      JOIN categories c ON c.id = p.category_id
      LEFT JOIN (
        SELECT product_id,
          SUM(revenue) AS revenue,
          SUM(net_profit) AS profit,
          SUM(quantity) AS quantity,
          COUNT(*) AS orders
        FROM sales
        WHERE sale_date >= CURRENT_DATE - 90
        GROUP BY product_id
      ) s ON s.product_id = p.id
      LEFT JOIN (
        SELECT product_id, SUM(quantity) AS total_stock
        FROM inventory
        GROUP BY product_id
      ) inv ON inv.product_id = p.id
      LEFT JOIN (
        SELECT product_id, SUM(quantity) AS total_returns
        FROM returns
        GROUP BY product_id
      ) ret ON ret.product_id = p.id
      ${where}
      ORDER BY ${sortCol} ${sortDir} NULLS LAST
    `, params);

    return NextResponse.json(result.rows);
  } catch (e: unknown) {
    console.error("Products error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
