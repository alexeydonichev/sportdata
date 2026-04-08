import { NextRequest, NextResponse } from "next/server";
import { getProductDetail } from "@/lib/repositories/products-detail.repo";

const ALLOWED_PERIODS: Record<string, number> = { "7d": 7, "14d": 14, "30d": 30, "90d": 90, "180d": 180, "365d": 365 };

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const productId = parseInt(id, 10);
  if (isNaN(productId)) {
    return NextResponse.json({ error: "Invalid product ID" }, { status: 400 });
  }

  const period = req.nextUrl.searchParams.get("period") || "90d";
  const days = ALLOWED_PERIODS[period] || 90;

  try {
    const data = await getProductDetail(productId, days);
    if (!data) {
      return NextResponse.json({ error: "Product not found" }, { status: 404 });
    }
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Product detail error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
