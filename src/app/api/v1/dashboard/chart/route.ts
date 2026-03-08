import { NextRequest, NextResponse } from "next/server";
import { PERIOD_DAYS, type PeriodKey } from "@/types/models";
import { dashboardRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const period = (req.nextUrl.searchParams.get("period") || "7d") as PeriodKey;
  const days = PERIOD_DAYS[period] || 7;

  try {
    const data = await dashboardRepo.getChart(days);
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Chart error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
