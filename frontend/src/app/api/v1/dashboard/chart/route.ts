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
    const data = await dashboardRepo.getChart(days, category, marketplace);
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Chart error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
