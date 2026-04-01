import { NextRequest, NextResponse } from "next/server";
import { PERIOD_DAYS, type PeriodKey } from "@/types/models";
import { salesRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const period = (sp.get("period") || "30d") as PeriodKey;
  const days = PERIOD_DAYS[period] || 30;

  try {
    const data = await salesRepo.getSales({
      days,
      category: sp.get("category") || undefined,
      marketplace: sp.get("marketplace") || undefined,
      page: parseInt(sp.get("page") || "1") || 1,
      limit: parseInt(sp.get("limit") || "50") || 50,
    });
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Sales error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
