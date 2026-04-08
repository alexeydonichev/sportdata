import { NextRequest, NextResponse } from "next/server";
import { getFinance } from "@/lib/repositories/finance.repo";

const PERIODS: Record<string, number> = { "7d":7,"14d":14,"30d":30,"90d":90,"180d":180,"365d":365 };

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const days = PERIODS[sp.get("period")||"30d"] || 30;
  try {
    const data = await getFinance(days, sp.get("category")||undefined, sp.get("marketplace")||undefined);
    return NextResponse.json({ period: sp.get("period")||"30d", ...data });
  } catch (e: unknown) {
    console.error("Finance error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
