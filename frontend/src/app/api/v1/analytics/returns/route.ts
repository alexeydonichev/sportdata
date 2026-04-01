import { NextRequest, NextResponse } from "next/server";
import { getReturnsAnalytics } from "@/lib/repositories/returns.repo";

const ALLOWED: Record<string, number> = { "7d": 7, "14d": 14, "30d": 30, "90d": 90, "180d": 180, "365d": 365 };

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const period = sp.get("period") || "30d";
  const days = ALLOWED[period] || 30;
  const category = sp.get("category") || undefined;

  try {
    const data = await getReturnsAnalytics(days, category);
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Returns analytics error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
