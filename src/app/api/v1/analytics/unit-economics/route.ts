import { NextRequest, NextResponse } from "next/server";
import { getUnitEconomics } from "@/lib/repositories/unit-economics.repo";

const PERIODS: Record<string, number> = {
  "7d": 7, "14d": 14, "30d": 30, "90d": 90, "180d": 180, "365d": 365,
};

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const period = sp.get("period") || "30d";
  const days = PERIODS[period] || 30;

  try {
    const data = await getUnitEconomics(days, {
      sort: sp.get("sort") || undefined,
      order: sp.get("order") || undefined,
      category: sp.get("category") || undefined,
      marketplace: sp.get("marketplace") || undefined,
    });
    return NextResponse.json({ period, ...data });
  } catch (e) {
    console.error("Unit economics error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
