import { NextRequest, NextResponse } from "next/server";
import { productsRepo } from "@/lib/repositories";

const PERIODS: Record<string, number> = {
  "7": 7, "7d": 7, "14": 14, "14d": 14,
  "30": 30, "30d": 30, "90": 90, "90d": 90,
};

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const period = sp.get("period") || "90";
  const days = PERIODS[period + "d"] || PERIODS[period] || parseInt(period) || 90;
  const marketplace = sp.get("marketplace") || undefined;

  try {
    const products = await productsRepo.getProductsForABC(days, marketplace);
    return NextResponse.json({ products });
  } catch (e: unknown) {
    console.error("ABC error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
