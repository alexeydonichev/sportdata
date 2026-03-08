import { NextRequest, NextResponse } from "next/server";
import { productsRepo } from "@/lib/repositories";

const ALLOWED_DAYS = [30, 60, 90, 180, 365];

export async function GET(req: NextRequest) {
  let days = parseInt(req.nextUrl.searchParams.get("period") || "90") || 90;
  if (!ALLOWED_DAYS.includes(days)) {
    days = ALLOWED_DAYS.reduce((prev, curr) =>
      Math.abs(curr - days) < Math.abs(prev - days) ? curr : prev
    );
  }

  try {
    const products = await productsRepo.getProductsForABC(days);
    return NextResponse.json({ products });
  } catch (e: unknown) {
    console.error("ABC analysis error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
