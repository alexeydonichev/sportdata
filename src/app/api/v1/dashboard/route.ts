import { NextRequest, NextResponse } from "next/server";
import { PERIOD_DAYS, type PeriodKey } from "@/types/models";
import { dashboardRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const period = (sp.get("period") || "7d") as PeriodKey;
  const days = PERIOD_DAYS[period] || 7;
  const category = sp.get("category") || undefined;
  const marketplace = sp.get("marketplace") || undefined;

  try {
    const { kpi, changes } = await dashboardRepo.getKPI(days, category, marketplace);
    const byMarketplace = await dashboardRepo.getByMarketplace(days, kpi.total_revenue, category);
    const topProducts = await dashboardRepo.getTopProducts(days, 10, category, marketplace);

    return NextResponse.json({
      period,
      date_from: kpi.date_from,
      date_to: kpi.date_to,
      total_revenue: kpi.total_revenue,
      total_profit: kpi.total_profit,
      total_orders: kpi.total_orders,
      total_quantity: kpi.total_quantity,
      total_sku: kpi.total_sku,
      avg_order_value: kpi.avg_order_value,
      profit_margin_pct: kpi.profit_margin_pct,
      total_commission: kpi.total_commission,
      total_logistics: kpi.total_logistics,
      changes,
      by_marketplace: byMarketplace,
      top_products: topProducts,
    });
  } catch (e: unknown) {
    console.error("Dashboard error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
