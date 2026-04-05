import { NextRequest, NextResponse } from "next/server";
import { rnpRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const startDate = sp.get("startDate") || undefined;
  const endDate = sp.get("endDate") || undefined;
  const marketplace = sp.get("marketplace") || undefined;
  const category = sp.get("category") || undefined;
  const limit = parseInt(sp.get("limit") || "50");
  const offset = parseInt(sp.get("offset") || "0");
  const view = sp.get("view"); // 'summary' | 'trend' | 'categories'

  try {
    if (view === "summary") {
      const summary = await rnpRepo.getSummaryByCategory({ startDate, endDate, marketplace });
      return NextResponse.json({ summary });
    }

    if (view === "trend") {
      const groupBy = (sp.get("groupBy") as "day" | "week" | "month") || "day";
      const trend = await rnpRepo.getTrend({ startDate, endDate, marketplace, groupBy });
      return NextResponse.json({ trend });
    }

    if (view === "categories") {
      const categories = await rnpRepo.getCategories();
      return NextResponse.json({ categories });
    }

    const { records, total } = await rnpRepo.getAll({
      startDate,
      endDate,
      marketplace,
      category,
      limit,
      offset,
    });

    return NextResponse.json({ records, total, limit, offset });
  } catch (e: unknown) {
    console.error("RNP GET error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { marketplace, operation_date, category, subcategory, description, amount, document_id } = body;

    if (!marketplace || !operation_date || !category || amount === undefined) {
      return NextResponse.json(
        { error: "Required fields: marketplace, operation_date, category, amount" },
        { status: 400 }
      );
    }

    const record = await rnpRepo.create({
      marketplace,
      operation_date,
      category,
      subcategory,
      description,
      amount: parseFloat(amount),
      document_id,
    });

    return NextResponse.json({ record }, { status: 201 });
  } catch (e: unknown) {
    console.error("RNP POST error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
