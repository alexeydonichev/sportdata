import { NextRequest } from "next/server";
import pool from "@/lib/db";

const ALLOWED_PERIODS: Record<string, number> = { "7d": 7, "14d": 14, "30d": 30, "90d": 90 };

function sanitizeCSVCell(value: string): string {
  let s = String(value ?? "");
  // Prevent CSV injection: strip leading formula characters
  if (/^[=+\-@\t\r]/.test(s)) {
    s = "'" + s;
  }
  if (s.includes(",") || s.includes('"') || s.includes("\n")) {
    s = '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

export async function GET(req: NextRequest) {
  const period = req.nextUrl.searchParams.get("period") || "30d";
  const category = req.nextUrl.searchParams.get("category");
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

    const result = await pool.query(`
      SELECT
        s.sale_date::text AS date,
        p.name AS product_name,
        p.sku,
        c.name AS category,
        mp.name AS marketplace,
        s.quantity,
        s.revenue::float,
        s.net_profit::float AS profit,
        s.commission::float,
        s.logistics_cost::float AS logistics
      FROM sales s
      JOIN products p ON p.id = s.product_id
      JOIN categories c ON c.id = p.category_id
      JOIN marketplaces mp ON mp.id = s.marketplace_id
      ${where}
      ORDER BY s.sale_date DESC, s.id DESC
    `, params);

    const bom = "\uFEFF";
    const header = "Дата,Товар,SKU,Категория,Маркетплейс,Количество,Выручка,Прибыль,Комиссия,Логистика";
    const rows = result.rows.map((r: Record<string, unknown>) =>
      [r.date, r.product_name, r.sku, r.category, r.marketplace, r.quantity, r.revenue, r.profit, r.commission, r.logistics]
        .map((v) => sanitizeCSVCell(String(v ?? "")))
        .join(",")
    );

    const csv = bom + header + "\n" + rows.join("\n");
    const filename = `sales-${period}-${new Date().toISOString().slice(0, 10)}.csv`;

    return new Response(csv, {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": `attachment; filename="${filename}"`,
      },
    });
  } catch (e: unknown) {
    console.error("Sales export error:", e);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}
