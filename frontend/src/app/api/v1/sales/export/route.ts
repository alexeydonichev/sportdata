import { NextRequest } from "next/server";
import { PERIOD_DAYS, type PeriodKey } from "@/types/models";
import { salesRepo } from "@/lib/repositories";

function sanitizeCSVCell(value: string): string {
  let s = String(value ?? "");
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  if (s.includes(",") || s.includes('"') || s.includes("\n")) {
    s = '"' + s.replace(/"/g, '""') + '"';
  }
  return s;
}

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const period = (sp.get("period") || "30d") as PeriodKey;
  const days = PERIOD_DAYS[period] || 30;
  const category = sp.get("category") || undefined;
  const marketplace = sp.get("marketplace") || undefined;

  try {
    const rows = await salesRepo.getSalesForExport(days, category, marketplace);

    const bom = "\uFEFF";
    const header = "Дата,Товар,SKU,Категория,Маркетплейс,Количество,Выручка,Прибыль,Комиссия,Логистика";
    const csvRows = rows.map((r) =>
      [r.date, r.product_name, r.sku, r.category, r.marketplace, r.quantity, r.revenue, r.profit, r.commission, r.logistics]
        .map((v) => sanitizeCSVCell(String(v ?? "")))
        .join(",")
    );

    const csv = bom + header + "\n" + csvRows.join("\n");
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
