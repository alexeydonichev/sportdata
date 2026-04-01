import { NextRequest, NextResponse } from "next/server";
import { getPnL } from "@/lib/repositories/pnl.repo";

const PERIODS: Record<string, number> = {
  "7d": 7, "14d": 14, "30d": 30, "90d": 90, "180d": 180, "365d": 365,
};

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const period = sp.get("period") || "30d";
  const categorySlug = sp.get("category") || undefined;
  const marketplace = sp.get("marketplace") || undefined;
  const days = PERIODS[period] || 30;

  try {
    const data = await getPnL(days, categorySlug, marketplace);
    return NextResponse.json({ period, ...data });
  } catch (e) {
    console.error("PnL error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
